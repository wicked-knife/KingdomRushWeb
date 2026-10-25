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
const CampaignProgress = preload("res://scripts/services/campaign_progress.gd")
var battle: Control
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
var progress_path := CampaignProgress.DEFAULT_PATH


func _ready() -> void:
	get_tree().auto_accept_quit = false
	settings = MenuSettings.new()
	settings.name = "Settings"
	add_child(settings)
	slots = SaveSlots.new()
	slots.initialize(slots_path if slots_path != "" else (SaveSlots.DEFAULT_ROOT if progress_path == CampaignProgress.DEFAULT_PATH else progress_path + ".slots"), progress_path)
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
	loading = Control.new()
	loading.name = "LoadingScreen"
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(loading)
	var background := ColorRect.new()
	background.color = Color("122722")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(background)
	heading = Label.new()
	heading.text = "KINGDOM RUSH"
	heading.add_theme_font_size_override("font_size", 68)
	heading.add_theme_color_override("font_color", Color("edda98"))
	heading.position = Vector2(420, 395)
	heading.size = Vector2(1080, 110)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(heading)
	description = Label.new()
	description.text = "Preparing..."
	description.add_theme_font_size_override("font_size", 30)
	description.position = Vector2(350, 550)
	description.size = Vector2(1220, 95)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(description)
	progress = ProgressBar.new()
	progress.position = Vector2(620, 670)
	progress.size = Vector2(680, 24)
	progress.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("cfa858")
	fill.set_corner_radius_all(8)
	progress.add_theme_stylebox_override("fill", fill)
	loading.add_child(progress)
	retry = Button.new()
	retry.text = "Retry"
	retry.position = Vector2(840, 735)
	retry.size = Vector2(240, 65)
	retry.pressed.connect(func():
		if retry_action.is_valid(): retry_action.call()
		else: _start()
	)
	retry.hide()
	loading.add_child(retry)


func _start() -> void:
	retry.hide()
	settings.initialize(settings_path)
	loader.initialize()


func _on_font(font: Font) -> void:
	_font_ready = true
	var loading_theme := Theme.new()
	loading_theme.default_font = font
	loading.theme = loading_theme
	retry.text = "重试"


func _on_progress(done: int, total: int, message: String) -> void:
	progress.value = float(done) / float(total) * 100.0
	description.text = message if _font_ready else "Loading... %d%%" % int(progress.value)


func _on_failed(message: String) -> void:
	description.text = ("加载失败，请重试。\n" if _font_ready else "Loading failed. Please retry.\n") + message
	retry.show()
	retry.grab_focus()


func _on_completed() -> void:
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu], loader.resources[loader.manifest.audio.GUIButtonCommon], settings)
	menu = Menu.instantiate()
	add_child(menu)
	menu.initialize(loader, settings, audio, slots)
	menu.campaign_requested.connect(_start_campaign)
	loading.hide()
	menu_ready.emit()


func _start_campaign(slot_id: int) -> void:
	if battle != null or campaign_map != null or transitioning: return
	campaign = slots.select_slot(slot_id)
	if campaign == null: return
	camera_state = slot_cameras.get(slot_id, {})
	_open_map()


func _open_map() -> void:
	if transitioning: return
	transitioning = true
	menu.hide()
	menu.set_process_input(false)
	loading.show(); retry.hide()
	if map_loader != null: remove_child(map_loader); map_loader.queue_free()
	map_loader = MapLoader.new(); add_child(map_loader)
	map_loader.progress_changed.connect(_on_progress)
	var loaded: bool = await map_loader.initialize()
	transitioning = false
	if not loaded:
		retry_action = _open_map
		_on_failed(map_loader.error_message)
		return
	campaign_map = MapScreen.new(); add_child(campaign_map)
	campaign_map.initialize(map_loader, loader, audio, settings, campaign, camera_state)
	campaign_map.battle_requested.connect(_start_level)
	campaign_map.returned_to_menu.connect(_return_to_menu)
	retry_action = Callable(); loading.hide(); map_ready.emit()


func _release_map() -> void:
	if campaign_map != null:
		camera_state = campaign_map.snapshot()
		slot_cameras[slots.active_slot] = camera_state
		remove_child(campaign_map); campaign_map.queue_free(); campaign_map = null
	if map_loader != null:
		remove_child(map_loader); map_loader.queue_free(); map_loader = null


func _start_level(level_id: int, mode: int, difficulty: int) -> void:
	if battle != null or transitioning or not campaign.is_playable(level_id, mode, difficulty): return
	_release_map()
	battle = Battle.new()
	add_child(battle)
	battle.initialize(loader, audio)
	battle.finished.connect(campaign.record_result)
	battle.returned_to_map.connect(_return_to_map)


func _return_to_map() -> void:
	if battle != null:
		remove_child(battle); battle.queue_free(); battle = null
	_open_map()


func _return_to_menu() -> void:
	_release_map()
	if battle != null:
		remove_child(battle)
		battle.queue_free()
		battle = null
	loading.hide()
	audio.music_player.volume_db = 0.0
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu], loader.resources[loader.manifest.audio.GUIButtonCommon], settings)
	menu.show()
	menu.set_process_input(true)
	menu.start_button.grab_focus()


func _input(event: InputEvent) -> void:
	if audio != null and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		audio.unlock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and settings != null:
		if battle != null:
			if not battle.sim.paused: battle.sim.command("pause")
		elif campaign_map != null:
			campaign_map._action("options")
		elif menu != null:
			menu.show_quit()
		else:
			get_tree().quit()
