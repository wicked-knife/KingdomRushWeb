extends Control

signal campaign_requested

const Art = preload("res://scripts/ui/menu_art.gd")
const INK := Color("f3e5ae")
var boot: Node
var settings: Node
var audio: Node
var overlay: ColorRect
var status: Label
var start_button: TextureButton
var options_button: TextureButton
var credits_button: TextureButton
var quit_button: TextureButton
var music_slider: HSlider
var sfx_slider: HSlider
var modal_kind := ""
var _previous_focus: Control
var _logo: TextureRect
var _logo_time := 0.0
var _logo_frames: Array[AtlasTexture] = []
var _design: Control


func initialize(loader: Node, preferences: Node, sound: Node) -> void:
	boot = loader
	settings = preferences
	audio = sound
	var theme := Theme.new()
	theme.default_font = boot.resources[boot.manifest.font]
	theme.default_font_size = 30
	self.theme = theme
	var background := TextureRect.new()
	background.name = "MenuBackground"
	background.texture = boot.resources[boot.manifest.background]
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_logo = Art.image(boot.catalog, "homeMenu_logo_0001", Vector2(130, 0))
	add_child(_logo)
	for index in range(1, 18):
		_logo_frames.append(Art.texture(boot.catalog, "homeMenu_logo_%04d" % index))
	var banner := Art.image(boot.catalog, "homeMenu_buttonsBg", Vector2(100, 632))
	add_child(banner)
	start_button = _menu_button("StartButton", "homeMenu_btnStart_zh-Hans", Vector2(279, 739), func(): campaign_requested.emit())
	options_button = _menu_button("OptionsButton", "homeMenu_btnOptions_zh-Hans", Vector2(310, 894), show_options)
	credits_button = _menu_button("CreditsButton", "homeMenu_btnCredits_zh-Hans", Vector2(330, 994), func(): _show_message(_text("CREDITS"), "制作人员页面暂未开放。"))
	if not OS.has_feature("web"):
		quit_button = _menu_button("QuitButton", "homeMenu_quit", Vector2(1450, 880), show_quit)
		quit_button.pivot_offset = Vector2(100, 170)
		quit_button.rotation = -0.1
		quit_button.add_child(_label(_text("QUIT"), Vector2(58, 76), Vector2(110, 50), 38))
	status = _label("", Vector2(800, 1012), Vector2(1050, 50), 24)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	settings.notice_changed.connect(_update_status.unbind(1))
	_update_status()
	# A blocking overlay keeps pointer and keyboard events inside the active modal.
	overlay = ColorRect.new()
	overlay.name = "ModalOverlay"
	overlay.color = Color(0.02, 0.04, 0.03, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	add_child(overlay)
	_design = Control.new()
	_design.name = "MenuDesign"
	_design.size = Vector2(1920, 1080)
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_design)
	for child in get_children():
		if child != background and child != _design:
			remove_child(child)
			_design.add_child(child)
	resized.connect(_layout_design)
	_layout_design()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	start_button.grab_focus()
	if OS.is_debug_build():
		print("MENU_READY music=", settings.music_volume, " sfx=", settings.sfx_volume, " web=", OS.has_feature("web"))


func _layout_design() -> void:
	if _design == null: return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	_design.scale = Vector2.ONE * factor
	_design.position = (size - Vector2(1920, 1080) * factor) / 2


func _process(delta: float) -> void:
	if _logo == null:
		return
	_logo_time += delta
	var index := mini(int(_logo_time * 30.0), _logo_frames.size() - 1)
	_logo.texture = _logo_frames[index]
	if index == _logo_frames.size() - 1:
		set_process(false)


func _input(event: InputEvent) -> void:
	if status != null and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		audio.unlock()
		_update_status()
	if event.is_action_pressed("ui_cancel") and overlay != null and overlay.visible:
		close_modal()
		get_viewport().set_input_as_handled()


func _menu_button(id: String, prefix: String, at: Vector2, action: Callable) -> TextureButton:
	var control := Art.button(boot.catalog, prefix, at)
	control.name = id
	control.pressed.connect(func():
		audio.play_click()
		action.call()
	)
	add_child(control)
	return control


func _label(value: String, at: Vector2, dimensions: Vector2, font_size: int = 30) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", Color("272519"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _begin_modal(kind: String, background: String, dimensions: Vector2) -> Control:
	_previous_focus = get_viewport().gui_get_focus_owner()
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	modal_kind = kind
	for button: TextureButton in [start_button, options_button, credits_button, quit_button]:
		if button != null:
			button.focus_mode = Control.FOCUS_NONE
	var panel := Art.image(boot.catalog, background, (Vector2(1920, 1080) - dimensions) / 2)
	panel.name = "Dialog"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(panel)
	overlay.show()
	return panel


func close_modal() -> void:
	if modal_kind == "options":
		settings.save()
	overlay.hide()
	modal_kind = ""
	for button: TextureButton in [start_button, options_button, credits_button, quit_button]:
		if button != null:
			button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()


func _dialog_button(parent: Control, value: String, at: Vector2, action: Callable) -> TextureButton:
	var button := Art.button(boot.catalog, "options_button_bg", at, "view_options", 2)
	button.add_child(_label(value, Vector2.ZERO, Vector2(194, 76), 28))
	button.pressed.connect(func():
		audio.play_click()
		action.call()
	)
	parent.add_child(button)
	return button


func _show_message(title: String, message: String) -> void:
	var panel := _begin_modal("message", "homeMenu_confirm_menu_0001", Vector2(720, 260))
	panel.add_child(_label(title, Vector2(60, 24), Vector2(600, 44), 36))
	panel.add_child(_label(message, Vector2(40, 82), Vector2(640, 50), 28))
	_dialog_button(panel, _text("Done"), Vector2(263, 154), close_modal).grab_focus()


func show_options() -> void:
	var panel := _begin_modal("options", "main_options_bg_notxt", Vector2(700, 370))
	panel.add_child(_label(_text("OPTIONS"), Vector2(232, 18), Vector2(242, 45), 34))
	panel.add_child(_label(_text("SFX"), Vector2(250, 78), Vector2(200, 32), 28))
	panel.add_child(_label(_text("Music"), Vector2(250, 170), Vector2(200, 32), 28))
	sfx_slider = _volume_slider(panel, "SFXSlider", Vector2(139, 118), settings.sfx_volume)
	music_slider = _volume_slider(panel, "MusicSlider", Vector2(139, 210), settings.music_volume)
	sfx_slider.value_changed.connect(func(value: float): settings.set_volumes(settings.music_volume, value))
	sfx_slider.drag_ended.connect(func(_changed: bool): audio.play_click())
	music_slider.value_changed.connect(func(value: float): settings.set_volumes(value, settings.sfx_volume))
	_dialog_button(panel, _text("Done"), Vector2(253, 270), close_modal)
	sfx_slider.grab_focus()


func _volume_slider(parent: Control, id: String, at: Vector2, volume: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = id
	slider.position = at
	slider.size = Vector2(422, 34)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = volume
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var track := StyleBoxTexture.new()
	track.texture = Art.texture(boot.catalog, "options_barBg", "view_options")
	track.texture_margin_left = 15
	track.texture_margin_right = 15
	track.content_margin_top = 17
	track.content_margin_bottom = 17
	slider.add_theme_stylebox_override("slider", track)
	var area := StyleBoxFlat.new()
	area.bg_color = Color("c9a34b")
	area.set_corner_radius_all(4)
	area.content_margin_top = 4
	area.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", area)
	slider.add_theme_stylebox_override("grabber_area_highlight", area)
	var knob := GradientTexture2D.new()
	knob.width = 28
	knob.height = 36
	knob.gradient = Gradient.new()
	knob.gradient.colors = PackedColorArray([Color("f5d681"), Color("956030")])
	knob.fill_from = Vector2(0, 0)
	knob.fill_to = Vector2(0, 1)
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob)
	parent.add_child(slider)
	var percentage := _label("%d%%" % roundi(volume * 100), at + Vector2(430, -3), Vector2(90, 40), 24)
	parent.add_child(percentage)
	slider.value_changed.connect(func(value: float): percentage.text = "%d%%" % roundi(value * 100))
	return slider


func show_quit() -> void:
	if OS.has_feature("web"):
		return
	var panel := _begin_modal("quit", "homeMenu_confirm_menu_0001", Vector2(720, 260))
	panel.add_child(_label("确定退出游戏？", Vector2(60, 45), Vector2(600, 60), 32))
	_dialog_button(panel, _text("Yes"), Vector2(153, 140), func():
		settings.save()
		get_tree().quit()
	)
	_dialog_button(panel, _text("No"), Vector2(373, 140), close_modal).grab_focus()


func _update_status() -> void:
	if not settings.notice.is_empty():
		status.text = settings.notice
	elif OS.has_feature("web") and not audio.unlocked:
		status.text = "点击任意按钮或按键开启声音"
	else:
		status.text = ""


func _text(key: String) -> String:
	return str(boot.locale.get(key, key))
