extends Control
## Kingdom Rush parchment/wood warboard loading screen with soldier-chasing-goblin march,
## ambient warm-gold motes, contextual headers/stage thumbnails, and smooth fade transitions.

const MARCH_TEXTURE_PATH := "res://data/loading/march_strip.png"
const MARCH_META_PATH := "res://data/loading/march_meta.json"
const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const INK_GOLD := Color("f7e4a3")
const INK_CREAM := Color("ebdfb8")
const INK_OUTLINE := Color("241b12")
const MODE_COLORS := {
	1: Color("f6de8c"),
	2: Color("ffae66"),
	3: Color("9ad8ff"),
}

var heading_label: Label
var description_label: Label
var progress_bar: ProgressBar
var retry_button: Button
var back_button: Button

var _audio: Node
var _font_ready := false
var _fonts: RefCounted
var _fallback_font: Font
var _catalog: RefCounted
var _logo_frames: Array[AtlasTexture] = []
var _logo_time := 0.0
var _march_tex: Texture2D
var _march_meta: Dictionary = {}
var _bar_bg_tex: Texture2D
var _bar_fill_tex: Texture2D
var _panel_tex: Texture2D
var _btn_normal_tex: Texture2D
var _btn_hover_tex: Texture2D

var _bg_rect: TextureRect
var _vignette_rect: TextureRect
var _atmosphere: Control
var _design: Control
var _logo_view: TextureRect
var _thumb_holder: Control
var _thumb_image: TextureRect
var _thumb_frame: TextureRect
var _panel_fallback: Panel
var _panel_art: TextureRect
var _plaque_label: Label
var _percent_label: Label
var _march_stage: Control
var _fade_tween: Tween

var _context_kind := "boot"
var _error_mode := false
var _target_ratio := 0.0
var _display_ratio := 0.0
var _elapsed := 0.0
var _shimmer_phase := 0.0
var _motes: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _dust_timer := 0.0
var _web_dismissed := false
var _shown_frames := 0


func _ready() -> void:
	name = "LoadingScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_march_assets()
	_init_motes()
	_build_tree()
	resized.connect(_layout_design)
	_layout_design()
	set_context("boot")


func _load_march_assets() -> void:
	if ResourceLoader.exists(MARCH_TEXTURE_PATH):
		var loaded := load(MARCH_TEXTURE_PATH)
		if loaded is Texture2D:
			_march_tex = loaded
	if FileAccess.file_exists(MARCH_META_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MARCH_META_PATH))
		if parsed is Dictionary:
			_march_meta = parsed


func _init_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261126
	for i in range(28):
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(0.018, 0.052),
			"radius": rng.randf_range(2.0, 5.2),
			"phase": rng.randf_range(0.0, TAU),
			"drift": rng.randf_range(0.008, 0.022),
			"alpha": rng.randf_range(0.25, 0.68),
		})


func _build_tree() -> void:
	var base := ColorRect.new()
	base.name = "BackdropBase"
	base.color = Color("101b17")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_bg_rect = TextureRect.new()
	_bg_rect.name = "BackdropImage"
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.modulate = Color(0.46, 0.43, 0.39, 0.0)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	var vignette_grad := Gradient.new()
	vignette_grad.colors = PackedColorArray([
		Color(0.95, 0.76, 0.36, 0.06),
		Color(0.05, 0.09, 0.07, 0.24),
		Color(0.02, 0.05, 0.04, 0.80),
	])
	vignette_grad.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	var vignette_tex := GradientTexture2D.new()
	vignette_tex.gradient = vignette_grad
	vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	vignette_tex.fill_from = Vector2(0.5, 0.54)
	vignette_tex.fill_to = Vector2(0.5, 1.18)
	vignette_tex.width = 256
	vignette_tex.height = 256
	_vignette_rect = TextureRect.new()
	_vignette_rect.name = "VignetteOverlay"
	_vignette_rect.texture = vignette_tex
	_vignette_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette_rect)

	_atmosphere = Control.new()
	_atmosphere.name = "AtmosphereLayer"
	_atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere.draw.connect(_draw_atmosphere)
	add_child(_atmosphere)

	_design = Control.new()
	_design.name = "DesignRoot"
	_design.size = DESIGN_SIZE
	_design.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_design)

	_logo_view = TextureRect.new()
	_logo_view.name = "LogoView"
	_logo_view.position = Vector2(716, -6)
	_logo_view.size = Vector2(488, 448)
	_logo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_view.hide()
	_design.add_child(_logo_view)

	_thumb_holder = Control.new()
	_thumb_holder.name = "StageThumbnail"
	_thumb_holder.position = Vector2(732, 86)
	_thumb_holder.size = Vector2(456, 332)
	_thumb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_holder.hide()
	_design.add_child(_thumb_holder)

	var thumb_shadow := Panel.new()
	thumb_shadow.position = Vector2(30, 34)
	thumb_shadow.size = Vector2(396, 268)
	thumb_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_sb := StyleBoxFlat.new()
	shadow_sb.bg_color = Color(0.03, 0.02, 0.01, 0.52)
	shadow_sb.set_corner_radius_all(12)
	shadow_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	shadow_sb.shadow_size = 20
	shadow_sb.shadow_offset = Vector2(0, 10)
	thumb_shadow.add_theme_stylebox_override("panel", shadow_sb)
	_thumb_holder.add_child(thumb_shadow)

	_thumb_image = TextureRect.new()
	_thumb_image.position = Vector2(24, 24)
	_thumb_image.size = Vector2(408, 284)
	_thumb_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_holder.add_child(_thumb_image)

	_thumb_frame = TextureRect.new()
	_thumb_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thumb_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_holder.add_child(_thumb_frame)

	# Stylized wood-and-iron fallback panel shown immediately before menu atlas finishes loading
	_panel_fallback = Panel.new()
	_panel_fallback.name = "WarboardFallback"
	_panel_fallback.position = Vector2(548, 476)
	_panel_fallback.size = Vector2(824, 420)
	_panel_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fallback_sb := StyleBoxFlat.new()
	fallback_sb.bg_color = Color("3a2b1f")
	fallback_sb.border_color = Color("8c7d65")
	fallback_sb.set_border_width_all(6)
	fallback_sb.set_corner_radius_all(14)
	fallback_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	fallback_sb.shadow_size = 18
	fallback_sb.shadow_offset = Vector2(0, 10)
	_panel_fallback.add_theme_stylebox_override("panel", fallback_sb)
	_design.add_child(_panel_fallback)

	var plaque_bg := Panel.new()
	plaque_bg.position = Vector2(252, -14)
	plaque_bg.size = Vector2(320, 56)
	plaque_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plaque_sb := StyleBoxFlat.new()
	plaque_sb.bg_color = Color("2b2622")
	plaque_sb.border_color = Color("a69b88")
	plaque_sb.set_border_width_all(4)
	plaque_sb.set_corner_radius_all(10)
	plaque_bg.add_theme_stylebox_override("panel", plaque_sb)
	_panel_fallback.add_child(plaque_bg)

	# Authentic Dove wooden warboard (main_options_bg_notxt: 700x370 scaled cleanly to 824x436)
	_panel_art = TextureRect.new()
	_panel_art.name = "WarboardArt"
	_panel_art.position = Vector2(548, 468)
	_panel_art.size = Vector2(824, 436)
	_panel_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel_art.stretch_mode = TextureRect.STRETCH_SCALE
	_panel_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_art.hide()
	_design.add_child(_panel_art)

	_plaque_label = _make_label("正在出征", Vector2(780, 484), Vector2(360, 56), 24, INK_GOLD)
	_plaque_label.name = "PlaqueLabel"
	_design.add_child(_plaque_label)

	heading_label = _make_label("KINGDOM RUSH", Vector2(600, 554), Vector2(720, 62), 44, INK_GOLD)
	heading_label.name = "HeadingLabel"
	_design.add_child(heading_label)

	# Hidden standard ProgressBar kept synced for backward-compatible test inspection (0..100)
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.position = Vector2(640, 712)
	progress_bar.size = Vector2(640, 34)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.modulate.a = 0.0
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(progress_bar)

	# Marching stage: renders gilded bar trough/fill, shimmer sweep, dust puffs, soldier & goblin
	_march_stage = Control.new()
	_march_stage.name = "MarchStage"
	_march_stage.position = Vector2(590, 610)
	_march_stage.size = Vector2(740, 152)
	_march_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_march_stage.draw.connect(_draw_march_stage)
	_design.add_child(_march_stage)

	_percent_label = _make_label("0%", Vector2(880, 756), Vector2(160, 34), 22, Color("d8c58c"))
	_percent_label.name = "PercentLabel"
	_design.add_child(_percent_label)

	description_label = _make_label("Preparing...", Vector2(610, 796), Vector2(700, 72), 25, INK_CREAM)
	description_label.name = "DescriptionLabel"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_design.add_child(description_label)

	retry_button = _make_button("RetryButton", "Retry", Vector2(720, 782), Vector2(216, 74))
	retry_button.hide()
	_design.add_child(retry_button)

	back_button = _make_button("BackButton", "返回", Vector2(984, 782), Vector2(216, 74))
	back_button.hide()
	_design.add_child(back_button)


func _make_label(text_value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK_OUTLINE)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(node_name: String, text_value: String, at: Vector2, dimensions: Vector2) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text_value
	btn.position = at
	btn.size = dimensions
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_color_override("font_color", INK_GOLD)
	btn.add_theme_color_override("font_hover_color", Color("fff4c2"))
	btn.add_theme_color_override("font_focus_color", Color("fff4c2"))
	btn.add_theme_color_override("font_pressed_color", Color("ffd97a"))
	btn.add_theme_color_override("font_outline_color", INK_OUTLINE)
	btn.add_theme_constant_override("outline_size", 4)
	_apply_button_styles(btn)
	return btn


func _apply_button_styles(btn: Button) -> void:
	if _btn_normal_tex != null and _btn_hover_tex != null:
		var normal := StyleBoxTexture.new()
		normal.texture = _btn_normal_tex
		var hover := StyleBoxTexture.new()
		hover.texture = _btn_hover_tex
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("focus", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		return
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color("4b3523")
	sb_n.border_color = Color("b6985e")
	sb_n.set_border_width_all(3)
	sb_n.set_corner_radius_all(10)
	var sb_h := StyleBoxFlat.new()
	sb_h.bg_color = Color("6b4926")
	sb_h.border_color = Color("f0cf7b")
	sb_h.set_border_width_all(3)
	sb_h.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("focus", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)


func bind_audio(audio_node: Node) -> void:
	_audio = audio_node


func play_button_click() -> void:
	if _audio != null and _audio.has_method("play_click"):
		_audio.play_click()


func apply_font(font: Font) -> void:
	_font_ready = true
	_fallback_font = font
	var loading_theme := Theme.new()
	loading_theme.default_font = font
	theme = loading_theme
	retry_button.text = "重试"
	if _context_kind == "boot" and not _error_mode:
		_plaque_label.text = "正在出征"
		heading_label.text = "王国保卫战"


func apply_boot_resources(loader: Node) -> void:
	if loader == null:
		return
	if loader.get("fonts") != null:
		_fonts = loader.fonts
		_apply_font_roles()
	var manifest: Dictionary = loader.get("manifest") if loader.get("manifest") is Dictionary else {}
	var resources: Dictionary = loader.get("resources") if loader.get("resources") is Dictionary else {}
	var bg_path := str(manifest.get("background", ""))
	if bg_path != "" and resources.has(bg_path) and resources[bg_path] is Texture2D:
		_bg_rect.texture = resources[bg_path]
		_bg_rect.modulate = Color(0.46, 0.43, 0.39, 1.0)
	var catalog: RefCounted = loader.get("catalog")
	if catalog == null:
		return
	_catalog = catalog
	var art := preload("res://scripts/ui/menu_art.gd")
	_panel_tex = art.texture(catalog, "main_options_bg_notxt", "screen_slots")
	if _panel_tex != null:
		_panel_art.texture = _panel_tex
		_panel_art.show()
		_panel_fallback.hide()
	_bar_bg_tex = art.texture(catalog, "options_barBg", "view_options")
	_bar_fill_tex = art.texture(catalog, "options_bar", "view_options")
	_btn_normal_tex = art.texture(catalog, "options_button_bg_0001", "view_options")
	_btn_hover_tex = art.texture(catalog, "options_button_bg_0002", "view_options")
	_apply_button_styles(retry_button)
	_apply_button_styles(back_button)
	_logo_frames.clear()
	for i in range(1, 18):
		var tex: AtlasTexture = art.texture(catalog, "homeMenu_logo_%04d" % i, "screen_slots")
		if tex != null:
			_logo_frames.append(tex)
	if not _logo_frames.is_empty():
		_logo_view.texture = _logo_frames[_logo_frames.size() - 1]
		if _context_kind != "level":
			_logo_view.show()
	_march_stage.queue_redraw()


func _apply_font_roles() -> void:
	if _fonts == null:
		return
	var h_font: Font = _fonts.font_for("h")
	var body_font: Font = _fonts.font_for("body")
	var btn_font: Font = _fonts.font_for("button")
	var num_font: Font = _fonts.font_for("numbers_bold")
	if h_font != null:
		heading_label.add_theme_font_override("font", h_font)
		_plaque_label.add_theme_font_override("font", h_font)
	if body_font != null:
		description_label.add_theme_font_override("font", body_font)
	if btn_font != null:
		retry_button.add_theme_font_override("font", btn_font)
		back_button.add_theme_font_override("font", btn_font)
	if num_font != null:
		_percent_label.add_theme_font_override("font", num_font)


func set_context(kind: String, info: Dictionary = {}) -> void:
	_context_kind = kind
	_error_mode = false
	_target_ratio = 0.0
	_display_ratio = 0.0
	_dust.clear()
	progress_bar.value = 0.0
	_percent_label.text = "0%"
	retry_button.hide()
	back_button.hide()
	_march_stage.show()
	_percent_label.show()
	description_label.position = Vector2(610, 796)
	description_label.size = Vector2(700, 72)
	description_label.add_theme_color_override("font_color", INK_CREAM)

	var plaque_color := INK_GOLD
	if kind == "boot":
		_plaque_label.text = "正在出征" if _font_ready else "LOADING"
		heading_label.text = "王国保卫战" if _font_ready else "KINGDOM RUSH"
		description_label.text = "正在准备王国战场…" if _font_ready else "Preparing..."
		_thumb_holder.hide()
		_logo_view.visible = not _logo_frames.is_empty()
		_logo_time = 0.0
	elif kind == "map":
		var returning := bool(info.get("returning", false))
		_plaque_label.text = "返回大地图" if returning else "前往王国地图"
		heading_label.text = "利尼维亚王国"
		description_label.text = "正在展开王国地图…"
		_thumb_holder.hide()
		_logo_view.visible = not _logo_frames.is_empty()
		if not _logo_frames.is_empty():
			_logo_view.texture = _logo_frames[_logo_frames.size() - 1]
	elif kind == "level":
		var level_id := int(info.get("level_id", 1))
		var title := str(info.get("title", "第 %d 关" % level_id))
		var mode := int(info.get("mode", 1))
		var mode_name := "战役模式" if mode == 1 else ("英雄模式" if mode == 2 else "钢铁挑战")
		plaque_color = MODE_COLORS.get(mode, INK_GOLD)
		_plaque_label.text = mode_name
		heading_label.text = "第 %d 关 · %s" % [level_id, title]
		description_label.text = "正在整备部队与战场…"
		var thumb_tex: Variant = info.get("thumbnail_texture")
		var frame_tex: Variant = info.get("frame_texture")
		if thumb_tex is Texture2D:
			_thumb_image.texture = thumb_tex
			_thumb_frame.texture = frame_tex if frame_tex is Texture2D else null
			_thumb_holder.show()
			_logo_view.hide()
		else:
			_thumb_holder.hide()
			_logo_view.visible = not _logo_frames.is_empty()
	elif kind == "ending":
		_plaque_label.text = "终章"
		heading_label.text = "王国的凯歌"
		description_label.text = "正在展开终章画卷…"
		_thumb_holder.hide()
		_logo_view.visible = not _logo_frames.is_empty()
		if not _logo_frames.is_empty():
			_logo_view.texture = _logo_frames[_logo_frames.size() - 1]
	_plaque_label.add_theme_color_override("font_color", plaque_color)
	_fit_heading_font()
	_march_stage.queue_redraw()


func _fit_heading_font() -> void:
	var size := 42
	var face: Font = heading_label.get_theme_font("font")
	if face == null:
		face = _fallback_font
	if face != null:
		while size > 24 and face.get_string_size(heading_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > heading_label.size.x - 24:
			size -= 2
	heading_label.add_theme_font_size_override("font_size", size)


func set_progress(done: int, total: int, message: String) -> void:
	var ratio := clampf(float(done) / float(maxi(1, total)), 0.0, 1.0)
	_target_ratio = ratio
	progress_bar.value = ratio * 100.0
	if _error_mode:
		return
	description_label.text = message if _font_ready else "Loading... %d%%" % int(round(ratio * 100.0))


func show_error(message: String, allow_back: bool) -> void:
	_error_mode = true
	_plaque_label.text = "加载受阻" if _font_ready else "ERROR"
	_plaque_label.add_theme_color_override("font_color", Color("ff9e7a"))
	_march_stage.hide()
	_percent_label.hide()
	description_label.position = Vector2(604, 624)
	description_label.size = Vector2(712, 138)
	description_label.add_theme_color_override("font_color", Color("ffdcc4"))
	description_label.text = ("加载失败，请重试。\n" if _font_ready else "Loading failed. Please retry.\n") + message
	retry_button.show()
	back_button.visible = allow_back
	if allow_back:
		retry_button.position = Vector2(720, 782)
		back_button.position = Vector2(984, 782)
	else:
		retry_button.position = Vector2(852, 782)
	retry_button.grab_focus()


func present_smooth() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_shown_frames = 0
	show()
	if DisplayServer.get_name() == "headless":
		modulate.a = 1.0
		return
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.18)


func should_animate_dismiss() -> bool:
	return visible and _shown_frames >= 2 and DisplayServer.get_name() != "headless"


func dismiss_immediate() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_shown_frames = 0
	modulate.a = 1.0
	retry_button.hide()
	back_button.hide()
	_release_transient_textures()
	hide()


func dismiss_smooth() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_target_ratio = 1.0
	_display_ratio = 1.0
	progress_bar.value = 100.0
	_percent_label.text = "100%"
	_march_stage.queue_redraw()
	if not should_animate_dismiss():
		_shown_frames = 0
		modulate.a = 1.0
		_release_transient_textures()
		hide()
		return
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	await _fade_tween.finished
	if is_inside_tree():
		_shown_frames = 0
		_release_transient_textures()
		hide()
		modulate.a = 1.0


func _release_transient_textures() -> void:
	if _thumb_image != null:
		_thumb_image.texture = null
	if _thumb_frame != null:
		_thumb_frame.texture = null


func set_backdrop_texture(tex: Texture2D) -> void:
	if _bg_rect != null and tex != null and _bg_rect.texture != tex:
		_bg_rect.texture = tex
		_bg_rect.modulate = Color(0.46, 0.43, 0.39, 1.0)


func notify_web_ready() -> void:
	if _web_dismissed:
		return
	_web_dismissed = true
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		Engine.get_singleton("JavaScriptBridge").eval("if(window.__krDismissBootOverlay){window.__krDismissBootOverlay();}")


func _layout_design() -> void:
	if _design == null:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_design.scale = Vector2.ONE * factor
	_design.position = (size - DESIGN_SIZE * factor) * 0.5
	if _atmosphere != null:
		_atmosphere.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_shown_frames += 1
	var dt := minf(delta, 0.05)
	_elapsed += dt
	_shimmer_phase = fmod(_shimmer_phase + dt * 0.62, 1.0)
	var lerp_rate := 1.0 - exp(-9.0 * dt)
	_display_ratio = lerpf(_display_ratio, _target_ratio, lerp_rate)
	if absf(_target_ratio - _display_ratio) < 0.002:
		_display_ratio = _target_ratio
	_percent_label.text = "%d%%" % int(round(_display_ratio * 100.0))

	# Subtle Ken Burns breath on backdrop image
	if _bg_rect != null and _bg_rect.texture != null:
		var zoom := 1.035 + 0.025 * sin(_elapsed * 0.35)
		_bg_rect.pivot_offset = _bg_rect.size * 0.5
		_bg_rect.scale = Vector2.ONE * zoom

	# Play 17-frame original Logo drop-in on boot
	if _context_kind == "boot" and not _logo_frames.is_empty():
		_logo_time += dt
		var idx := mini(int(_logo_time * 30.0), _logo_frames.size() - 1)
		_logo_view.texture = _logo_frames[idx]

	# Update floating warm-gold motes
	for m: Dictionary in _motes:
		m.y -= float(m.speed) * dt
		if float(m.y) < -0.04:
			m.y = 1.04
	_atmosphere.queue_redraw()

	# Update soldier & goblin foot dust puffs
	if not _error_mode:
		_dust_timer += dt
		if _dust_timer >= 0.075:
			_dust_timer = 0.0
			_spawn_dust()
		var kept: Array[Dictionary] = []
		for p: Dictionary in _dust:
			p.age += dt
			p.x += float(p.vx) * dt
			p.y += float(p.vy) * dt
			if float(p.age) < float(p.life):
				kept.append(p)
		_dust = kept
		_march_stage.queue_redraw()


func _spawn_dust() -> void:
	var bar_left := 50.0
	var bar_w := 640.0
	var soldier_x := bar_left + clampf(_display_ratio, 0.03, 0.96) * bar_w
	var goblin_x := minf(bar_left + bar_w - 14.0, soldier_x + 78.0)
	var foot_y := 96.0
	for cx: float in [soldier_x - 14.0, goblin_x - 12.0]:
		_dust.append({
			"x": cx,
			"y": foot_y + randf_range(-3.0, 2.0),
			"vx": randf_range(-42.0, -18.0),
			"vy": randf_range(-16.0, -4.0),
			"r": randf_range(3.5, 7.0),
			"age": 0.0,
			"life": randf_range(0.32, 0.52),
		})


func _draw_atmosphere() -> void:
	var rect := Rect2(Vector2.ZERO, _atmosphere.size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	# Floating warm-gold motes over the smooth radial vignette
	for m: Dictionary in _motes:
		var mx := (float(m.x) + sin(_elapsed * 0.9 + float(m.phase)) * float(m.drift)) * rect.size.x
		var my := float(m.y) * rect.size.y
		var pulse := 0.65 + 0.35 * sin(_elapsed * 2.2 + float(m.phase))
		var alpha := float(m.alpha) * pulse
		var rad := float(m.radius)
		_atmosphere.draw_circle(Vector2(mx, my), rad * 2.3, Color(1.0, 0.80, 0.36, alpha * 0.24))
		_atmosphere.draw_circle(Vector2(mx, my), rad, Color(1.0, 0.91, 0.62, alpha))


func _draw_march_stage() -> void:
	var bar_left := 50.0
	var bar_w := 640.0
	var bar_y := 102.0
	var bar_h := 36.0
	var bar_rect := Rect2(bar_left, bar_y, bar_w, bar_h)

	# Progress bar trough
	if _bar_bg_tex != null:
		_march_stage.draw_texture_rect(_bar_bg_tex, bar_rect, false)
	else:
		_march_stage.draw_rect(bar_rect.grow(3.0), Color("8a7652"))
		_march_stage.draw_rect(bar_rect, Color("1c1610"))

	# Gilded fill
	var inner_pad_x := 16.0
	var inner_pad_y := 8.0
	var max_fill_w := bar_w - inner_pad_x * 2.0
	var fill_w := maxf(0.0, max_fill_w * clampf(_display_ratio, 0.0, 1.0))
	var fill_h := bar_h - inner_pad_y * 2.0
	if fill_w > 1.0:
		var fill_rect := Rect2(bar_left + inner_pad_x, bar_y + inner_pad_y, fill_w, fill_h)
		if _bar_fill_tex != null:
			var src_w := _bar_fill_tex.get_width() * clampf(_display_ratio, 0.0, 1.0)
			if _bar_fill_tex is AtlasTexture:
				var atlas: AtlasTexture = _bar_fill_tex
				var region := atlas.region
				var sub := Rect2(region.position.x, region.position.y, maxf(1.0, region.size.x * clampf(_display_ratio, 0.0, 1.0)), region.size.y)
				_march_stage.draw_texture_rect_region(atlas.atlas, fill_rect, sub)
			else:
				_march_stage.draw_texture_rect_region(_bar_fill_tex, fill_rect, Rect2(0, 0, maxf(1.0, src_w), _bar_fill_tex.get_height()))
		else:
			_march_stage.draw_rect(fill_rect, Color("d8a846"))
			_march_stage.draw_rect(Rect2(fill_rect.position, Vector2(fill_w, fill_h * 0.42)), Color("f6d67a"))

		# Subtle warm glow at the leading edge of progress
		_march_stage.draw_circle(Vector2(fill_rect.end.x, fill_rect.position.y + fill_h * 0.5), 14.0, Color(1.0, 0.88, 0.45, 0.22))

		# Specular shimmer sweep gliding across filled region
		var sweep_x := bar_left + inner_pad_x - 80.0 + (_shimmer_phase * (max_fill_w + 160.0))
		var shimmer_left := maxf(fill_rect.position.x, sweep_x)
		var shimmer_right := minf(fill_rect.end.x, sweep_x + 76.0)
		if shimmer_right > shimmer_left:
			var shimmer_rect := Rect2(shimmer_left, fill_rect.position.y, shimmer_right - shimmer_left, fill_h)
			_march_stage.draw_rect(shimmer_rect, Color(1.0, 0.96, 0.78, 0.34))

	# Foot dust puffs
	for p: Dictionary in _dust:
		var t := clampf(float(p.age) / float(p.life), 0.0, 1.0)
		var a := (1.0 - t) * 0.42
		var r := float(p.r) * (0.7 + t * 0.9)
		_march_stage.draw_circle(Vector2(float(p.x), float(p.y)), r, Color(0.86, 0.78, 0.62, a))

	# Soldier chasing Goblin sprites
	if _march_tex != null and not _march_meta.is_empty():
		var cell: Array = _march_meta.get("cell_size", [64, 80])
		var cw := float(cell[0])
		var ch := float(cell[1])
		var draw_scale := 1.18
		var dw := cw * draw_scale
		var dh := ch * draw_scale
		var ground_y := bar_y + 4.0
		var soldier_x := bar_left + inner_pad_x + clampf(_display_ratio, 0.04, 0.95) * max_fill_w
		var gap := lerpf(82.0, 56.0, clampf(_display_ratio, 0.0, 1.0))
		var goblin_x := minf(bar_left + bar_w - 20.0, soldier_x + gap)

		# Goblin running ahead
		var g_info: Dictionary = _march_meta.get("goblin", {})
		var g_seq: Array = g_info.get("frames", [0])
		var g_fps := float(g_info.get("fps", 26.0))
		var g_row := int(g_info.get("row", 1))
		var g_col := int(g_seq[int(_elapsed * g_fps) % maxi(1, g_seq.size())])
		var g_src := Rect2(g_col * cw, g_row * ch, cw, ch)
		var g_dst := Rect2(goblin_x - dw * 0.5, ground_y - dh + 6.0, dw, dh)
		_march_stage.draw_texture_rect_region(_march_tex, g_dst, g_src)

		# Soldier pursuing closely behind
		var s_info: Dictionary = _march_meta.get("soldier", {})
		var s_seq: Array = s_info.get("frames", [0])
		var s_fps := float(s_info.get("fps", 12.0))
		var s_row := int(s_info.get("row", 0))
		var s_col := int(s_seq[int(_elapsed * s_fps) % maxi(1, s_seq.size())])
		var s_src := Rect2(s_col * cw, s_row * ch, cw, ch)
		var s_dst := Rect2(soldier_x - dw * 0.5, ground_y - dh + 6.0, dw, dh)
		_march_stage.draw_texture_rect_region(_march_tex, s_dst, s_src)
