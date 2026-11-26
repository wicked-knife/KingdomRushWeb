extends Control

signal menu_ready
signal map_ready

const BootLoader = preload("res://scripts/services/menu_boot_loader.gd")
const MenuSettings = preload("res://scripts/services/menu_settings.gd")
const MenuAudio = preload("res://scripts/services/menu_audio.gd")
const Menu = preload("res://scenes/main_menu.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const MapScreen = preload("res://scripts/map/map_screen.gd")
const MapLoader = preload("res://scripts/services/map_loader.gd")
const SaveSlots = preload("res://scripts/services/save_slots.gd")
const ContentPacks = preload("res://scripts/services/content_packs.gd")
const LoadingScreen = preload("res://scripts/ui/loading_screen.gd")
var packs: Node
var back: Button
var _prefetch_epoch := 0
var battle: Control
var ending: Control
var pending_route := ""
var campaign_map: Control
var map_loader: Node
var slots: RefCounted
var campaign: RefCounted
var slot_cameras := {}
var slots_path := ""
var camera_state := {}
var transitioning := false
var retry_action: Callable
var loader: Node
var settings: Node
var audio: Node
var menu: Control
var loading: Control
var heading: Label
var description: Label
var progress: ProgressBar
var retry: Button
var _font_ready := false
var settings_path := MenuSettings.DEFAULT_PATH


func _ready() -> void:
	get_tree().auto_accept_quit = false
	packs = ContentPacks.new()
	add_child(packs)
	packs.progress_changed.connect(_on_progress)
	settings = MenuSettings.new()
	settings.name = "Settings"
	add_child(settings)
	slots = SaveSlots.new()
	audio = MenuAudio.new()
	audio.name = "Audio"
	add_child(audio)
	loader = BootLoader.new()
	loader.name = "BootLoader"
	add_child(loader)
	_build_loading()
	loader.progress_changed.connect(_on_progress)
	loader.font_loaded.connect(_on_font)
	loader.failed.connect(_on_failed)
	loader.completed.connect(_on_completed)
	_start.call_deferred()


func _build_loading() -> void:
	loading = LoadingScreen.new()
	add_child(loading)
	loading.bind_audio(audio)
	heading = loading.heading_label
	description = loading.description_label
	progress = loading.progress_bar
	retry = loading.retry_button
	back = loading.back_button
	retry.pressed.connect(func():
		loading.play_button_click()
		if retry_action.is_valid(): retry_action.call()
		else: _start()
	)
	back.pressed.connect(func():
		loading.play_button_click()
		_recover_after_failure()
	)
	_notify_web_after_first_frame.call_deferred()


func _notify_web_after_first_frame() -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	if is_inside_tree() and loading != null:
		loading.notify_web_ready()


func _start() -> void:
	loading.set_context("boot")
	retry.hide()
	back.hide()
	settings.initialize(settings_path)
	slots.initialize(slots_path if slots_path != "" else SaveSlots.DEFAULT_ROOT, settings)
	loader.initialize()


func _on_font(font: Font) -> void:
	_font_ready = true
	loading.apply_font(font)


func _on_progress(done: int, total: int, message: String) -> void:
	if menu == null and loader != null and loader.manifest.has("background"):
		var bg_path := str(loader.manifest.background)
		if loader.resources.has(bg_path) and loader.resources[bg_path] is Texture2D:
			loading.set_backdrop_texture(loader.resources[bg_path])
	loading.set_progress(done, total, message)


func _on_failed(message: String) -> void:
	loading.show_error(message, menu != null)


func _recover_after_failure() -> void:
	if pending_route!="":
		pending_route="";transitioning=false;_return_to_map();return
	retry_action = Callable()
	transitioning = false
	loading.dismiss_immediate()
	if campaign_map != null:
		campaign_map.show()
		campaign_map.set_process_input(true)
	else:
		menu.show()
		menu.set_process_input(true)


func _on_completed() -> void:
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu], loader.resources[loader.manifest.audio.GUIButtonCommon], settings)
	loading.apply_boot_resources(loader)
	menu = Menu.instantiate()
	add_child(menu)
	menu.initialize(loader, settings, audio, slots)
	menu.campaign_requested.connect(_start_campaign)
	move_child(loading, get_child_count() - 1)
	if loading.should_animate_dismiss():
		await loading.dismiss_smooth()
	else:
		loading.dismiss_immediate()
	menu_ready.emit()


func _start_campaign(slot_id: int) -> void:
	if battle != null or campaign_map != null or transitioning: return
	campaign = slots.select_slot(slot_id)
	if campaign == null: return
	camera_state = slot_cameras.get(slot_id, {})
	_open_map(false)


func _open_map(returning: bool = false) -> void:
	if transitioning: return
	transitioning = true
	menu.hide()
	menu.set_process_input(false)
	loading.set_context("map", {"returning": returning})
	loading.present_smooth()
	move_child(loading, get_child_count() - 1)
	if not await packs.ensure_bundle("map"):
		transitioning = false
		retry_action = _open_map.bind(returning)
		_on_failed(packs.error_message)
		return
	if map_loader != null: remove_child(map_loader); map_loader.queue_free()
	map_loader = MapLoader.new(); add_child(map_loader)
	map_loader.progress_changed.connect(_on_progress)
	var loaded: bool = await map_loader.initialize()
	transitioning = false
	if not loaded:
		retry_action = _open_map.bind(returning)
		_on_failed(map_loader.error_message)
		return
	var next_map := MapScreen.new(); add_child(next_map)
	next_map.initialize(map_loader, loader, audio, settings, campaign, camera_state)
	next_map.battle_requested.connect(_start_level)
	next_map.returned_to_menu.connect(_return_to_menu)
	move_child(loading, get_child_count() - 1)
	if loading.should_animate_dismiss():
		await loading.dismiss_smooth()
	else:
		loading.dismiss_immediate()
	campaign_map = next_map
	retry_action = Callable(); map_ready.emit()


func _release_map() -> void:
	if campaign_map != null:
		camera_state = campaign_map.snapshot()
		slot_cameras[slots.active_slot] = camera_state
		remove_child(campaign_map); campaign_map.queue_free(); campaign_map = null
	if map_loader != null:
		remove_child(map_loader); map_loader.queue_free(); map_loader = null


func _level_loading_info(level_id: int, mode: int) -> Dictionary:
	var info := {"level_id": level_id, "mode": mode, "title": "第 %d 关" % level_id}
	var stage_def: Dictionary = {}
	if map_loader != null and map_loader.definition is Dictionary:
		for item: Dictionary in map_loader.definition.get("levels", []):
			if int(item.get("id", 0)) == level_id:
				stage_def = item
				break
	if stage_def.is_empty():
		var map_def: Dictionary = preload("res://scripts/services/campaign_levels.gd").read_json("res://data/map_kr1/definition.json")
		for item: Dictionary in map_def.get("levels", []):
			if int(item.get("id", 0)) == level_id:
				stage_def = item
				break
	if not stage_def.is_empty():
		info["title"] = str(stage_def.get("title", info["title"]))
		var thumb_name := str(stage_def.get("thumbnail", ""))
		if thumb_name != "" and map_loader != null and map_loader.catalog != null:
			var thumb_frame: Dictionary = map_loader.catalog.get_frame("map_kr1", thumb_name)
			if not thumb_frame.is_empty() and thumb_frame.get("texture") is Texture2D:
				info["thumbnail_texture"] = thumb_frame.texture
			var frame_art: Dictionary = map_loader.catalog.get_frame("map_kr1", "levelSelect_thumbFrame")
			if not frame_art.is_empty() and frame_art.get("texture") is Texture2D:
				info["frame_texture"] = frame_art.texture
	return info


func _start_level(level_id: int, mode: int, difficulty: int) -> void:
	if battle != null or transitioning or not campaign.is_playable(level_id, mode, difficulty): return
	transitioning = true
	loading.set_context("level", _level_loading_info(level_id, mode))
	loading.present_smooth()
	move_child(loading, get_child_count() - 1)
	if not await packs.ensure_bundle("level%02d" % level_id):
		_level_failed(packs.error_message, level_id, mode, difficulty)
		return
	var definition := preload("res://scripts/services/campaign_levels.gd").load_definition(level_id, mode, difficulty)
	if definition.is_empty():
		_level_failed(preload("res://scripts/services/campaign_levels.gd").last_error, level_id, mode, difficulty)
		return
	var overrides: Array = definition.layout.get("level_mode_overrides", [])
	var override: Dictionary = overrides[mode - 1] if overrides.size() >= mode else {}
	if not override.get("locked_hero", definition.layout.get("locked_hero", false)):
		var content: Dictionary = preload("res://scripts/services/campaign_levels.gd").catalog()
		var hero_bundles: Array = []
		for id: String in campaign.data.heroes.selected:
			if content.get("combat_heroes", {}).has(id): hero_bundles.append("hero:" + id)
		if not await packs.ensure_bundles(hero_bundles):
			_level_failed(packs.error_message, level_id, mode, difficulty)
			return
	definition = preload("res://scripts/services/battle_setup.gd").create(definition, campaign.data)
	if definition.is_empty():
		_level_failed(preload("res://scripts/services/battle_setup.gd").last_error, level_id, mode, difficulty)
		return
	_release_map()
	var next_battle := Battle.new()
	add_child(next_battle)
	next_battle.initialize(loader, audio, definition)
	next_battle.finished.connect(campaign.record_result)
	next_battle.seen_flushed.connect(campaign.flush_seen)
	next_battle.returned_to_map.connect(_return_to_map)
	next_battle.routed.connect(_route_battle)
	move_child(loading, get_child_count() - 1)
	if loading.should_animate_dismiss():
		await loading.dismiss_smooth()
	else:
		loading.dismiss_immediate()
	battle = next_battle
	transitioning = false
	retry_action = Callable()
	_prefetch_epoch += 1
	_prefetch_next.call_deferred(level_id, _prefetch_epoch)


func _level_failed(message: String, level_id: int, mode: int, difficulty: int) -> void:
	transitioning = false
	retry_action = _start_level.bind(level_id, mode, difficulty)
	_on_failed(message)


func _prefetch_next(level_id: int, epoch: int) -> void:
	if not packs.enabled: return
	await get_tree().create_timer(3.0).timeout
	if epoch != _prefetch_epoch or battle == null: return
	var next: String = packs.index.get("next_levels", {}).get("level%02d" % level_id, "")
	if next != "": packs.prefetch_bundle(next)


func _return_to_map() -> void:
	pending_route=""
	if ending!=null:
		remove_child(ending);ending.queue_free();ending=null
	_prefetch_epoch += 1
	packs.stop_prefetch()
	if battle != null:
		remove_child(battle); battle.queue_free(); battle = null
	_open_map(true)

func _route_battle(route:String) -> void:
	if route!="kr1_end" or transitioning or ending!=null:return
	pending_route=route
	_open_ending()

func _open_ending() -> void:
	if transitioning or pending_route!="kr1_end":return
	transitioning=true
	_prefetch_epoch+=1;packs.stop_prefetch()
	loading.set_context("ending")
	loading.present_smooth();move_child(loading,get_child_count()-1)
	if battle!=null:battle.set_process_input(false);battle.hide()
	if not await packs.ensure_bundle("kr1_end"):
		transitioning=false;retry_action=_open_ending;_on_failed(packs.error_message);return
	var script=load("res://scripts/ui/kr1_ending.gd")
	if script==null:
		transitioning=false;retry_action=_open_ending;_on_failed("结尾资源无法载入，请重试。");return
	var next_ending = script.new(); add_child(next_ending)
	if not next_ending.initialize(loader,audio):
		remove_child(next_ending);next_ending.queue_free()
		transitioning=false;retry_action=_open_ending;_on_failed("结尾资源不完整，请重试或返回地图。");return
	ending = next_ending
	ending.completed.connect(_return_to_map)
	move_child(loading,get_child_count()-1)
	if loading.should_animate_dismiss():
		await loading.dismiss_smooth()
	else:
		loading.dismiss_immediate()
	transitioning=false;retry_action=Callable()


func _return_to_menu() -> void:
	if ending!=null:
		remove_child(ending);ending.queue_free();ending=null
	_prefetch_epoch += 1
	packs.stop_prefetch()
	_release_map()
	if battle != null:
		remove_child(battle)
		battle.queue_free()
		battle = null
	loading.dismiss_immediate()
	audio.music_player.volume_db = 0.0
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu], loader.resources[loader.manifest.audio.GUIButtonCommon], settings)
	menu.show()
	menu.set_process_input(true)
	menu.start_button.grab_focus()


func _input(event: InputEvent) -> void:
	if audio != null and (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch or event is InputEventJoypadButton) and event.is_pressed():
		audio.unlock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and settings != null:
		if ending!=null:get_tree().quit();return
		if battle != null:
			if not battle.sim.paused: battle.sim.command("pause")
		elif campaign_map != null:
			campaign_map._action("options")
		elif menu != null:
			menu.show_quit()
		else:
			get_tree().quit()
