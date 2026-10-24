extends Control
## Run this scene with F6. It is deliberately separate from the game's main scene.

const Catalog = preload("res://scripts/dove_asset_catalog.gd")

var catalog: Catalog
var group_picker: OptionButton
var frame_picker: OptionButton
var preview: TextureRect
var details: Label
var audio: AudioStreamPlayer
var frame_data: Dictionary = {}
var elapsed: float = 0.0
var animation: Dictionary = {}
var play_animation: bool = false
var smoke_frames: int = 0
var smoke_mode: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("142329"))
	catalog = Catalog.new()
	if not catalog.is_available():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var font: Font = load(Catalog.ROOT + "all-desktop/fonts/msyh.ttc") as Font
	if font != null:
		var preview_theme := Theme.new()
		preview_theme.default_font = font
		preview_theme.default_font_size = 18
		column.theme = preview_theme
	var title := Label.new()
	title.text = "Dove 素材预览 · 已安装版本"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	group_picker = OptionButton.new()
	group_picker.custom_minimum_size.x = 300
	for group in catalog.list_groups():
		group_picker.add_item(str(group))
	toolbar.add_child(group_picker)
	group_picker.item_selected.connect(_select_group)
	frame_picker = OptionButton.new()
	frame_picker.fit_to_longest_item = false
	frame_picker.clip_text = true
	frame_picker.custom_minimum_size.x = 200
	frame_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(frame_picker)
	frame_picker.item_selected.connect(_select_frame)
	var background_button := Button.new()
	background_button.text = "第一关背景"
	background_button.pressed.connect(_show_background)
	toolbar.add_child(background_button)
	var animation_button := Button.new()
	animation_button.text = "士兵动画"
	animation_button.pressed.connect(_show_animation)
	toolbar.add_child(animation_button)
	var sound_button := Button.new()
	sound_button.text = "播放音效"
	sound_button.pressed.connect(_play_sound)
	toolbar.add_child(sound_button)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel.add_child(preview)
	var note := Label.new()
	note.text = "图片、裁切帧、中文字体与 OGG 音效验证。动画和纹理按需加载。"
	column.add_child(note)
	audio = AudioStreamPlayer.new()
	audio.volume_db = -12
	add_child(audio)
	_select_group(0)
	_show_background()
	smoke_mode = "--asset-smoke" in OS.get_cmdline_user_args()
	if smoke_mode:
		_smoke_check()


func _select_group(index: int) -> void:
	play_animation = false
	var data: Dictionary = catalog.load_group(group_picker.get_item_text(index))
	frame_picker.clear()
	var names: Array = data.get("frames", {}).keys()
	names.sort()
	for name in names:
		frame_picker.add_item(str(name))
	if frame_picker.item_count > 0:
		_select_frame(0)


func _select_frame(index: int) -> void:
	play_animation = false
	frame_data = catalog.get_frame(group_picker.get_item_text(group_picker.selected), frame_picker.get_item_text(index))
	if frame_data.is_empty():
		return
	preview.texture = frame_data["texture"]
	details.text = "%s / %s  ·  逻辑尺寸 %s  ·  原尺寸 %s  ·  裁切偏移 %s" % [frame_data["group"], frame_data["name"], frame_data["logical_size"], frame_data["original_size"], frame_data["trim"]]


func _show_background() -> void:
	play_animation = false
	preview.texture = catalog.get_texture(Catalog.ROOT + "kr1-desktop/images/fullhd/go_stage01_bg-1.png")
	details.text = "第一关背景 · 1920 × 1080 · 原分辨率与透明度已保留"


func _show_animation() -> void:
	animation = catalog.get_animation("soldier_barbarian_running")
	if animation.is_empty():
		return
	elapsed = 0.0
	play_animation = true
	details.text = "soldier_barbarian_running · 原版默认 30 FPS · 按需加载图集"


func _play_sound() -> void:
	var sound: Dictionary = catalog.get_sound("AmazonTaunt")
	if sound.is_empty() or sound["paths"].is_empty():
		return
	audio.stream = load(sound["paths"][0]) as AudioStream
	audio.play()


func _process(delta: float) -> void:
	if play_animation and not animation.is_empty():
		elapsed += delta
		var names: PackedStringArray = animation["frames"]
		if not names.is_empty():
			var index: int = int(elapsed * float(animation["fps"])) % names.size()
			var frame: Dictionary = catalog.get_frame("go_towers_group4", names[index])
			if not frame.is_empty():
				preview.texture = frame["texture"]
	if smoke_mode:
		smoke_frames += 1
		if smoke_frames == 3:
			get_viewport().get_texture().get_image().save_png("res://reports/asset_preview_background.png")
			_show_animation()
		if smoke_frames == 8:
			var capture: Image = get_viewport().get_texture().get_image()
			if capture != null:
				capture.save_png("res://reports/asset_preview.png")
			print("ASSET_PREVIEW_SMOKE_OK")
			get_tree().quit()


func _smoke_check() -> void:
	assert(preview.texture != null, "background texture failed")
	var sample: Dictionary = catalog.get_frame("go_towers_group4", "soldier_lvl4_barbarian_0003")
	assert(not sample.is_empty(), "soldier frame failed")
	assert(not catalog.get_exoskeleton("archer4Def").is_empty(), "composition data failed")
	assert(not catalog.get_static("locale_zh-Hans").is_empty(), "Chinese localization failed")
	_play_sound()
	assert(audio.stream != null, "OGG import failed")
