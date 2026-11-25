extends Node
## Immutable, content-addressed downloads with concurrent foreground transfers,
## time-budgeted verification, verified cache index, and idle smart prefetch.
signal progress_changed(completed: int, total: int, description: String)
signal transfer_started(pack_id: String, background: bool)

const INDEX := "res://data/web_packs.json"
const MAX_PACK_BYTES := 24 * 1024 * 1024
const MAX_CONCURRENT_FOREGROUND := 3
const VERIFY_BUDGET_USEC := 6000
const VERIFY_CHUNK_BYTES := 512 * 1024
const MAP_PREFETCH_DELAY := 0.5
const LEVEL_PREFETCH_DELAY := 0.6

var enabled := false
var error_message := ""
var index: Dictionary = {}
var base_url := ""
var cache_root := "user://content_cache"
var mounted := {}
var network_requests := 0
var _initialized := false
var _configuration_valid := false
var _jobs := {}
var _foreground: Array[String] = []
var _background: Array[String] = []
var _needed := {}
var _active := ""
var _active_background := false
var _slots := {}
var _verified_index := {}
var _token := 0
var _menu_prefetch_timer := 0.0
var _menu_prefetched := false
var _map_prefetch_level := 0
var _map_prefetch_timer := 0.0
var _prefetched_levels := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("content_packs")
	if not _initialized: initialize()


func initialize(override_index: Dictionary = {}, override_url: String = "", override_cache: String = "") -> bool:
	_initialized = true
	_configuration_valid = false
	_cancel_all_slots()
	_foreground.clear()
	_background.clear()
	_jobs.clear()
	_needed.clear()
	_verified_index.clear()
	_menu_prefetch_timer = 0.0
	_menu_prefetched = false
	_map_prefetch_level = 0
	_map_prefetch_timer = 0.0
	_prefetched_levels.clear()
	enabled = OS.has_feature("web") or not override_index.is_empty() or FileAccess.file_exists(INDEX)
	if not enabled: return true
	if override_cache != "": cache_root = override_cache
	base_url = override_url
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--content-base-url=") and override_url == "": base_url = argument.trim_prefix("--content-base-url=")
		if argument.begins_with("--content-cache-root=") and override_cache == "": cache_root = argument.trim_prefix("--content-cache-root=")
	index = override_index
	if index.is_empty() and FileAccess.file_exists(INDEX):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if parsed is Dictionary: index = parsed
	if index.get("schema_version", 0) != 1 or index.get("engine_version", "") != "4.7.2" or not index.get("packs") is Dictionary or not index.get("bundles") is Dictionary:
		return _error("资源包目录无效，请重新加载页面。")
	if not (base_url.begins_with("http://") or base_url.begins_with("https://")) or not base_url.ends_with("/"):
		return _error("资源包下载地址无效，请重新加载页面。")
	for id: String in index.packs:
		var row: Variant = index.packs[id]
		if id.length() != 64 or not id.is_valid_hex_number(false) or not row is Dictionary:
			return _error("资源包校验目录无效。")
		if row.get("sha256", "") != id or row.get("url", "") != "packs/" + id + ".pck" or not row.get("size") is float and not row.get("size") is int:
			return _error("资源包校验目录无效。")
		if int(row.size) <= 0 or int(row.size) > MAX_PACK_BYTES: return _error("资源包大小无效。")
	for bundle: String in index.bundles:
		if not index.bundles[bundle] is Array: return _error("资源包依赖目录无效。")
		for id: Variant in index.bundles[bundle]:
			if not id is String or not index.packs.has(id): return _error("资源包依赖缺失。")
	if DirAccess.make_dir_recursive_absolute(cache_root) != OK: return _error("无法创建资源缓存目录。")
	_load_verified_index()
	error_message = ""
	_configuration_valid = true
	return true


func ensure_bundle(bundle: String) -> bool:
	return await ensure_bundles([bundle])


func ensure_bundles(bundles: Array) -> bool:
	if not enabled: return true
	if not _configuration_valid: return false
	_menu_prefetch_timer = 0.0
	_map_prefetch_timer = 0.0
	var required: Array[String] = []
	for bundle: String in bundles:
		if not index.get("bundles", {}).has(bundle): return _error("缺少资源分组：" + bundle)
		for id: String in index.bundles[bundle]:
			if not id in required: required.append(id)
	for id: String in required:
		_needed[id] = int(_needed.get(id, 0)) + 1
		_queue(id, false)
	for active_id: String in _slots.keys():
		if _slots[active_id].background:
			if _needed.has(active_id):
				_slots[active_id].background = false
			else:
				_cancel_slot(active_id)
	_sync_active_state()
	_pump()
	var success := true
	while is_inside_tree():
		var ready := true
		for id: String in required:
			var job: Dictionary = _jobs[id]
			if job.status == "failed":
				error_message = job.error
				success = false
				break
			if job.status != "ready": ready = false
		if not success or ready: break
		await get_tree().process_frame
	for id: String in required:
		_needed[id] -= 1
		if _needed[id] == 0: _needed.erase(id)
	for active_id: String in _slots.keys():
		if not _slots[active_id].background and not _needed.has(active_id):
			_cancel_slot(active_id)
	_sync_active_state()
	if not is_inside_tree(): return false
	if not success: return false
	for id: String in required:
		if mounted.has(id): continue
		if not ProjectSettings.load_resource_pack(_path(id), false):
			_jobs[id].status = "failed"
			_verified_index.erase(id)
			_save_verified_index()
			DirAccess.remove_absolute(_path(id))
			return _error("资源包无法载入，请重试。")
		mounted[id] = true
	error_message = ""
	return true


func prefetch_bundle(bundle: String) -> void:
	if not enabled or not _configuration_valid or not index.get("bundles", {}).has(bundle): return
	stop_prefetch()
	for id: String in index.bundles[bundle]: _queue(id, true)


func stop_prefetch() -> void:
	_background.clear()
	for active_id: String in _slots.keys():
		if _slots[active_id].background:
			_cancel_slot(active_id)
	_sync_active_state()


func _queue(id: String, background: bool) -> void:
	if not _jobs.has(id) or _jobs[id].status in ["failed", "cancelled"]:
		_jobs[id] = {"status": "pending", "error": ""}
	if _jobs[id].status == "ready": return
	if background:
		if not id in _background and not _needed.has(id) and not _slots.has(id):
			_background.append(id)
	else:
		_background.erase(id)
		if not id in _foreground and not _slots.has(id):
			_foreground.append(id)


func _process(delta: float) -> void:
	if not enabled: return
	_pump()
	_tick_smart_prefetch(delta)
	if _needed.is_empty(): return
	var done := 0
	var total := 0
	for id: String in _needed:
		var size := int(index.packs[id].size)
		total += size
		if _jobs[id].status == "ready":
			done += size
		elif _slots.has(id):
			var http: HTTPRequest = _slots[id].http
			if is_instance_valid(http):
				done += mini(size, http.get_downloaded_bytes())
	progress_changed.emit(done, maxi(1, total), "下载游戏资源… %.1f / %.1f MB" % [done / 1000000.0, total / 1000000.0])


func _tick_smart_prefetch(delta: float) -> void:
	if not _configuration_valid or not _needed.is_empty() or not _foreground.is_empty() or not _slots.is_empty():
		return
	var parent := get_parent()
	if parent == null: return
	var menu: Variant = parent.get("menu")
	var campaign_map: Variant = parent.get("campaign_map")
	var battle: Variant = parent.get("battle")
	var transitioning: bool = parent.get("transitioning") == true
	if transitioning or battle != null:
		_menu_prefetch_timer = 0.0
		_map_prefetch_timer = 0.0
		return
	if menu != null and menu is Control and menu.visible and menu.get("slots_open") == true and campaign_map == null:
		if not _menu_prefetched and index.bundles.has("map"):
			_menu_prefetch_timer += delta
			if _menu_prefetch_timer >= MAP_PREFETCH_DELAY:
				_menu_prefetched = true
				prefetch_bundle("map")
	else:
		_menu_prefetch_timer = 0.0
	if campaign_map != null and campaign_map is Control and campaign_map.visible and str(campaign_map.get("overlay")) == "level":
		var raw_level: Variant = campaign_map.get("selected_level")
		var level_id := int(raw_level) if raw_level != null else 0
		if level_id != _map_prefetch_level:
			_map_prefetch_level = level_id
			_map_prefetch_timer = 0.0
		var bundle := "level%02d" % level_id
		if level_id > 0 and not _prefetched_levels.has(bundle) and index.bundles.has(bundle):
			_map_prefetch_timer += delta
			if _map_prefetch_timer >= LEVEL_PREFETCH_DELAY:
				_prefetched_levels[bundle] = true
				prefetch_bundle(bundle)
	else:
		_map_prefetch_level = 0
		_map_prefetch_timer = 0.0


func _pump() -> void:
	if not _foreground.is_empty():
		for active_id: String in _slots.keys():
			if _slots[active_id].background:
				if _needed.has(active_id):
					_slots[active_id].background = false
				else:
					_cancel_slot(active_id)
		while not _foreground.is_empty() and _slots.size() < MAX_CONCURRENT_FOREGROUND:
			var id: String = _foreground.pop_front()
			if not _needed.has(id) or _slots.has(id): continue
			if _jobs[id].status != "pending": continue
			_start_slot(id, false)
	elif _slots.is_empty() and _needed.is_empty() and not _background.is_empty():
		while not _background.is_empty():
			var id: String = _background.pop_front()
			if _jobs[id].status != "pending": continue
			_start_slot(id, true)
			break
	_sync_active_state()


func _start_slot(id: String, background: bool) -> void:
	_token += 1
	var token := _token
	_slots[id] = {"token": token, "background": background, "http": null}
	_jobs[id].status = "checking"
	_sync_active_state()
	_run_job.call_deferred(id, token)


func _sync_active_state() -> void:
	if _slots.is_empty():
		_active = ""
		_active_background = false
		return
	for id: String in _slots:
		if _slots[id].background:
			_active = id
			_active_background = true
			return
	for id: String in _slots:
		_active = id
		_active_background = false
		return


func _slot_valid(id: String, token: int) -> bool:
	return _slots.has(id) and int(_slots[id].token) == token


func _run_job(id: String, token: int) -> void:
	if not _slot_valid(id, token): return
	if FileAccess.file_exists(_path(id)):
		var expected_size := int(index.packs[id].size)
		var existing := FileAccess.open(_path(id), FileAccess.READ)
		var actual_size := existing.get_length() if existing != null else -1
		if existing != null: existing.close()
		if actual_size == expected_size and int(_verified_index.get(id, -1)) == expected_size:
			_finish(id, token, "")
			return
		var valid: bool = await _verify(_path(id), id, token)
		if not _slot_valid(id, token): return
		if valid:
			_verified_index[id] = expected_size
			_save_verified_index()
			_finish(id, token, "")
			return
		_verified_index.erase(id)
		_save_verified_index()
		DirAccess.remove_absolute(_path(id))
	if not _slot_valid(id, token): return
	var http := HTTPRequest.new()
	http.use_threads = false
	http.timeout = 120.0
	http.body_size_limit = MAX_PACK_BYTES
	http.download_file = _temporary(id, token)
	add_child(http)
	_slots[id].http = http
	http.request_completed.connect(_download_completed.bind(id, token))
	_jobs[id].status = "downloading"
	network_requests += 1
	transfer_started.emit(id, bool(_slots[id].background))
	var result := http.request(base_url + str(index.packs[id].url))
	if result != OK: _finish(id, token, "无法开始资源下载，请重试。")


func _download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, id: String, token: int) -> void:
	if not _slot_valid(id, token): return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(id, token, "资源下载失败（HTTP %d，错误 %d），请重试。" % [code, result])
		return
	_jobs[id].status = "checking"
	var valid: bool = await _verify(_temporary(id, token), id, token)
	if not _slot_valid(id, token):
		DirAccess.remove_absolute(_temporary(id, token))
		return
	if not valid:
		_finish(id, token, "资源包不完整或校验失败，请重试。")
		return
	if DirAccess.rename_absolute(_temporary(id, token), _path(id)) != OK:
		_finish(id, token, "无法保存资源缓存，请检查可用空间后重试。")
		return
	_verified_index[id] = int(index.packs[id].size)
	_save_verified_index()
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		Engine.get_singleton("JavaScriptBridge").force_fs_sync()
	_finish(id, token, "")


func _verify(path: String, id: String, token: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var length := file.get_length()
	if length != int(index.packs[id].size):
		file.close()
		return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var deadline := Time.get_ticks_usec() + VERIFY_BUDGET_USEC
	while file.get_position() < length:
		if not _slot_valid(id, token):
			file.close()
			return false
		hash.update(file.get_buffer(VERIFY_CHUNK_BYTES))
		if file.get_position() < length and Time.get_ticks_usec() >= deadline:
			await get_tree().process_frame
			deadline = Time.get_ticks_usec() + VERIFY_BUDGET_USEC
	file.close()
	return hash.finish().hex_encode() == id


func _finish(id: String, token: int, failure: String) -> void:
	if not _slot_valid(id, token): return
	var slot: Dictionary = _slots[id]
	_slots.erase(id)
	_jobs[id] = {"status": "ready" if failure == "" else "failed", "error": failure}
	var http: Variant = slot.get("http")
	if is_instance_valid(http):
		http.queue_free()
	DirAccess.remove_absolute(_temporary(id, token))
	_sync_active_state()


func _cancel_slot(id: String) -> void:
	if not _slots.has(id): return
	var slot: Dictionary = _slots[id]
	var token := int(slot.token)
	_slots.erase(id)
	var http: Variant = slot.get("http")
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	_jobs[id].status = "cancelled"
	DirAccess.remove_absolute(_temporary(id, token))
	_sync_active_state()


func _cancel_all_slots() -> void:
	for id: String in _slots.keys():
		_cancel_slot(id)


func _verified_index_path() -> String:
	return cache_root.trim_suffix("/") + ".verified.json"


func _load_verified_index() -> void:
	_verified_index.clear()
	var path := _verified_index_path()
	if not FileAccess.file_exists(path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary: _verified_index = parsed


func _save_verified_index() -> void:
	var file := FileAccess.open(_verified_index_path(), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(_verified_index))
	file.close()


func _path(id: String) -> String: return cache_root.path_join(id + ".pck")
func _temporary(id: String, token: int) -> String: return cache_root.path_join(id + ".%d.part" % token)
func _error(message: String) -> bool:
	error_message = message
	return false


func _exit_tree() -> void:
	_cancel_all_slots()
