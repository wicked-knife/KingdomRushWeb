extends Control

signal menu_ready

const BootLoader = preload("res://scripts/services/menu_boot_loader.gd")
const MenuSettings = preload("res://scripts/services/menu_settings.gd")
const MenuAudio = preload("res://scripts/services/menu_audio.gd")
const Menu = preload("res://scenes/main_menu.tscn")
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
	settings = MenuSettings.new()
	settings.name = "Settings"
	add_child(settings)
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
	retry.pressed.connect(_start)
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
	menu.initialize(loader, settings, audio)
	loading.hide()
	menu_ready.emit()


func _input(event: InputEvent) -> void:
	if audio != null and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		audio.unlock()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and settings != null:
		if menu != null:
			menu.show_quit()
		else:
			get_tree().quit()
