extends Node
## Immutable, content-addressed downloads. The editor still uses source resources.
signal progress_changed(completed: int, total: int, description: String)
signal transfer_started(pack_id: String, background: bool)

const INDEX := "res://data/web_packs.json"
const MAX_PACK_BYTES := 24 * 1024 * 1024
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
var _token := 0
var _http: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("content_packs")
	if not _initialized: initialize()


func initialize(override_index: Dictionary = {}, override_url: String = "", override_cache: String = "") -> bool:
	_initialized = true
	_configuration_valid = false
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
	error_message = ""
	_configuration_valid = true
	return true


func ensure_bundle(bundle: String) -> bool:
	return await ensure_bundles([bundle])


func ensure_bundles(bundles: Array) -> bool:
	if not enabled: return true
	if not _configuration_valid: return false
	var required: Array[String] = []
	for bundle: String in bundles:
		if not index.get("bundles", {}).has(bundle): return _error("缺少资源分组：" + bundle)
		for id: String in index.bundles[bundle]:
			if not id in required: required.append(id)
	for id: String in required:
		_needed[id] = int(_needed.get(id, 0)) + 1
		_queue(id, false)
	if _active != "" and _active_background:
		if _needed.has(_active): _active_background = false
		else: _cancel_active()
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
	if _active != "" and not _active_background and not _needed.has(_active): _cancel_active()
	if not is_inside_tree(): return false
	if not success: return false
	for id: String in required:
		if mounted.has(id): continue
		if not ProjectSettings.load_resource_pack(_path(id), false):
			_jobs[id].status = "failed"
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
	if _active != "" and _active_background: _cancel_active()


func _queue(id: String, background: bool) -> void:
	if not _jobs.has(id) or _jobs[id].status in ["failed", "cancelled"]:
		_jobs[id] = {"status": "pending", "error": ""}
	if _jobs[id].status == "ready": return
	if background:
		if not id in _background and not _needed.has(id): _background.append(id)
	else:
		_background.erase(id)
		if not id in _foreground: _foreground.append(id)


func _process(_delta: float) -> void:
	if not enabled: return
	if _active == "": _pump()
	if _needed.is_empty(): return
	var done := 0
	var total := 0
	for id: String in _needed:
		var size := int(index.packs[id].size)
		total += size
		if _jobs[id].status == "ready": done += size
		elif id == _active and is_instance_valid(_http): done += mini(size, _http.get_downloaded_bytes())
	progress_changed.emit(done, maxi(1, total), "下载游戏资源… %.1f / %.1f MB" % [done / 1000000.0, total / 1000000.0])


func _pump() -> void:
	while not _foreground.is_empty() or not _background.is_empty():
		var background := _foreground.is_empty()
		var id: String = _background.pop_front() if background else _foreground.pop_front()
		if not background and not _needed.has(id): continue
		if _jobs[id].status != "pending": continue
		_active = id; _active_background = background; _token += 1
		_jobs[id].status = "checking"
		_run_job.call_deferred(id, _token)
		return


func _run_job(id: String, token: int) -> void:
	if token != _token or _active != id: return
	if FileAccess.file_exists(_path(id)):
		var valid: bool = await _verify(_path(id), id, token)
		if token != _token: return
		if valid:
			_finish(id, token, "")
			return
		DirAccess.remove_absolute(_path(id))
	if token != _token: return
	_http = HTTPRequest.new()
	_http.use_threads = false
	_http.timeout = 120.0
	_http.body_size_limit = MAX_PACK_BYTES
	_http.download_file = _temporary(id, token)
	add_child(_http)
	_http.request_completed.connect(_download_completed.bind(id, token))
	_jobs[id].status = "downloading"
	network_requests += 1
	transfer_started.emit(id, _active_background)
	var result := _http.request(base_url + str(index.packs[id].url))
	if result != OK: _finish(id, token, "无法开始资源下载，请重试。")


func _download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, id: String, token: int) -> void:
	if token != _token: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(id, token, "资源下载失败（HTTP %d，错误 %d），请重试。" % [code, result])
		return
	_jobs[id].status = "checking"
	var valid: bool = await _verify(_temporary(id, token), id, token)
	if token != _token:
		DirAccess.remove_absolute(_temporary(id, token))
		return
	if not valid:
		_finish(id, token, "资源包不完整或校验失败，请重试。")
		return
	if DirAccess.rename_absolute(_temporary(id, token), _path(id)) != OK:
		_finish(id, token, "无法保存资源缓存，请检查可用空间后重试。")
		return
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		Engine.get_singleton("JavaScriptBridge").force_fs_sync()
	_finish(id, token, "")


func _verify(path: String, id: String, token: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	if file.get_length() != int(index.packs[id].size):
		file.close()
		return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		if token != _token:
			file.close()
			return false
		hash.update(file.get_buffer(1024 * 1024))
		await get_tree().process_frame
	file.close()
	return hash.finish().hex_encode() == id


func _finish(id: String, token: int, failure: String) -> void:
	if token != _token: return
	_jobs[id] = {"status": "ready" if failure == "" else "failed", "error": failure}
	if is_instance_valid(_http):
		_http.queue_free()
		_http = null
	DirAccess.remove_absolute(_temporary(id, token))
	_active = ""


func _cancel_active() -> void:
	var id := _active
	var token := _token
	_token += 1
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
		_http = null
	_jobs[id].status = "cancelled"
	_active = ""
	DirAccess.remove_absolute(_temporary(id, token))


func _path(id: String) -> String: return cache_root.path_join(id + ".pck")
func _temporary(id: String, token: int) -> String: return cache_root.path_join(id + ".%d.part" % token)
func _error(message: String) -> bool:
	error_message = message
	return false


func _exit_tree() -> void:
	if _active != "": _cancel_active()
