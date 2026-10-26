extends Control
## Source hero_room_view.lua coordinates. All child controls share the panel transform.
const Layout = preload("res://scripts/battle/dove_ui_layout.gd")
const Loader = preload("res://scripts/services/hero_loader.gd")
const GOLD := Color("e7e1b5")
var map: Control
var progress: RefCounted
var fonts: RefCounted
var paint: RefCounted
var loader: Node
var catalog: RefCounted
var frames := {}
var zoom := 1.0
var view_size := Vector2(1920, 1080)
var panel_at := Vector2.ZERO
var panel_scale := 1.35
var hits: Array = []
var hovered := ""
var shown := ""
var details_mode := false
var skill := 0
var scroll: ScrollContainer
var grid: Control
var detail_scroll: ScrollContainer
var detail_text: RichTextLabel
var voice: AudioStreamPlayer
var click_sound: AudioStreamPlayer
var streams := {}
var load_fraction := 0.0
var stats_time := 0.0

class ThumbGrid extends Control:
	var room: Control
	var paint: RefCounted
	var zoom := 1.0
	var hits: Array = []
	var hovered := ""
	func _frame(id: String) -> Dictionary: return room._frame(id)
	func _draw() -> void:
		if paint == null or not room.loader.loaded: return
		hits.clear(); paint.begin()
		var rows: Array = room.progress.hero_definition.heroes
		for i in rows.size():
			var row: Dictionary = rows[i]
			var at := Vector2((i % 7) * 46, (i / 7) as int * 50)
			paint.push(at, 0.625)
			paint.image(row.thumbnail)
			paint.image("hero_room_thumbs_0000")
			if not room.progress.is_hero_unlocked(row.name): paint.image("hero_room_portraits_lock")
			if room.shown == row.name: paint.image("hero_room_thumbs_select_0000")
			if hovered == row.name: paint.image("hero_room_thumbs_select_0003")
			var slot: int = room.progress.heroes.selected.find(row.name)
			if slot >= 0:
				paint.image("hero_room_thumbs_select_0000")
				paint._apply(); draw_circle(Vector2(65, 64), 15, Color(0.05, 0.04, 0.03, 0.85))
				paint.display_label(str(slot + 1), Rect2(50, 49, 30, 30), 28, Color.WHITE, "numbers_bold", "slot", 1)
			paint.hit(Rect2(0, 0, 74, 74), "hero", {"id": row.name})
			paint.pop()
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hovered = ""
			for hit: Dictionary in hits:
				if hit.rect.has_point(event.position): hovered = hit.args.id
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" else CURSOR_ARROW
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				for hit: Dictionary in hits:
					if hit.rect.has_point(event.position): room.show_hero(hit.args.id); room.play_sound("GUIQuickMenuOpen"); accept_event(); break
			elif event.button_index == MOUSE_BUTTON_RIGHT: room.map.close_overlay(); accept_event()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT: hovered = ""; queue_redraw()

func initialize(owner_map: Control) -> void:
	map = owner_map; progress = map.progress; fonts = map.fonts
	name = "HeroRoom"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = MOUSE_FILTER_STOP
	paint = Layout.new(self, fonts, 1080)
	loader = Loader.new(); add_child(loader)
	loader.progress_changed.connect(func(done: int, total: int): load_fraction = float(done) / maxf(1, total); queue_redraw())
	voice = AudioStreamPlayer.new(); voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM; voice.bus = "SFX"; add_child(voice)
	click_sound = AudioStreamPlayer.new(); click_sound.playback_type = AudioServer.PLAYBACK_TYPE_STREAM; click_sound.bus = "SFX"; add_child(click_sound)
	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.size = Vector2(355, 244); add_child(scroll)
	grid = ThumbGrid.new(); grid.room = self; grid.custom_minimum_size = Vector2(330, ceil(progress.hero_rows.size() / 7.0) * 50 + 3)
	grid.mouse_filter = MOUSE_FILTER_PASS; grid.paint = Layout.new(grid, fonts, 1080); scroll.add_child(grid)
	detail_scroll = ScrollContainer.new(); detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; detail_scroll.size = Vector2(455, 210); add_child(detail_scroll)
	detail_text = RichTextLabel.new(); detail_text.fit_content = true; detail_text.scroll_active = false; detail_text.custom_minimum_size = Vector2(435, 0)
	detail_text.add_theme_font_override("normal_font", fonts.font_for("body")); detail_text.add_theme_font_size_override("normal_font_size", fonts.size_for("body", 15))
	detail_text.add_theme_color_override("default_color", GOLD); detail_text.mouse_filter = MOUSE_FILTER_PASS; detail_scroll.add_child(detail_text)
	for container: ScrollContainer in [scroll, detail_scroll]:
		var bar := container.get_v_scroll_bar()
		var track := StyleBoxFlat.new(); track.bg_color = Color("281e14b4"); track.content_margin_left = 7; track.content_margin_right = 7
		var thumb := StyleBoxFlat.new(); thumb.bg_color = Color("8c6e3cdc"); thumb.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("scroll", track)
		for style in ["grabber", "grabber_highlight", "grabber_pressed"]: bar.add_theme_stylebox_override(style, thumb)
		bar.focus_mode = Control.FOCUS_NONE
		container.gui_input.connect(_scroll_input)
		bar.gui_input.connect(_scroll_input)
	hide()

func _scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		map.close_overlay(); get_viewport().set_input_as_handled()

func open() -> void:
	show()
	if shown == "": shown = progress.heroes.selected[0] if not progress.heroes.selected.is_empty() else "hero_gerald"
	if loader.loaded: show_hero(shown); return
	_load.call_deferred()

func _load() -> void:
	if loader.loading: return
	scroll.hide(); detail_scroll.hide()
	frames.clear(); streams.clear(); catalog = null
	if await loader.initialize():
		catalog = loader.catalog; show_hero(shown)
	queue_redraw()

func _process(delta: float) -> void:
	if not visible: return
	stats_time += delta
	zoom = size.y / 1080.0; view_size = size / maxf(0.001, zoom)
	panel_scale = minf(1.35, minf((view_size.x - 60) / 920.0, (1080.0 - 40) / 752.0))
	panel_at = (view_size - Vector2(920, 752) * panel_scale) / 2
	for item: Array in [[scroll, Vector2(128, 146)], [detail_scroll, Vector2(317, 449)]]:
		item[0].position = (panel_at + item[1] * panel_scale) * zoom
		item[0].scale = Vector2.ONE * panel_scale * zoom
	scroll.visible = loader.loaded
	detail_scroll.visible = loader.loaded and details_mode
	queue_redraw()

func _frame(id: String) -> Dictionary:
	if not frames.has(id):
		var atlas: Dictionary = catalog.load_group("heroes")
		frames[id] = catalog.get_frame("heroes", id) if atlas.lookup.has(id) else map._frame(id)
	return frames[id]

func _draw() -> void:
	if paint == null: return
	hits.clear(); paint.begin()
	if not loader.loaded:
		paint.label("加载英雄殿堂… %d%%" % int(load_fraction * 100) if loader.loading else "英雄殿堂加载失败\n" + loader.error_message, Rect2(view_size / 2 - Vector2(500, 100), Vector2(1000, 160)), 26, GOLD)
		if not loader.loading:
			paint.label("重试", Rect2(view_size / 2 + Vector2(-150, 80), Vector2(120, 60)), 26, GOLD)
			paint.hit(Rect2(view_size / 2 + Vector2(-150, 80), Vector2(120, 60)), "retry")
		paint.label("返回", Rect2(view_size / 2 + Vector2(30, 80), Vector2(120, 60)), 26, GOLD)
		paint.hit(Rect2(view_size / 2 + Vector2(30, 80), Vector2(120, 60)), "close")
		return
	paint.push(panel_at, panel_scale)
	paint.image("heroroom_bg")
	var row: Dictionary = progress.hero(shown)
	var strings: Dictionary = progress.hero_definition.strings
	paint.label(strings["HERO ROOM"], Rect2(335, 26, 260, 45), 34, GOLD, "center", "middle", 1, 2, "hero_room_title", "h")
	paint.label(strings["Select hero"], Rect2(157, 108, 300, 30), 19, GOLD, "center", "middle", 1, 1, "hero_select_title", "h")
	if row.portrait_fallback:
		paint.push(Vector2(602, 140), 2.0); paint.image(row.portrait); paint.pop()
	else: paint.image(row.portrait, Vector2(585, 112), Vector2.ZERO, Color.WHITE, Vector2(0.77, 0.76))
	paint.display_label(row.title, Rect2(562, 329, 255, 54), 30, Color("f5d98a"), "h", "hero_name", 2, Color("582600"))
	if not details_mode: paint.image("heroroom_descriptionBox", Vector2(89, 432))
	if details_mode:
		var entries: Array = row.details
		var step := minf(32, 208.0 / entries.size())
		for i in entries.size():
			var box := Rect2(112, 450 + i * step, 190, step - 2)
			paint._apply(); draw_rect(box, Color("5e412d") if i == skill else Color("392b20"), true)
			paint.label(entries[i].title, box.grow(-3), 16, GOLD, "center", "middle", 1, 0, "skill_title")
			paint.hit(box, "skill", {"index": i})
	else:
		paint.label(strings.MAP_HEROROOM_BIO, Rect2(136, 442, 330, 24), 17, Color("9b4e1d"), "left", "bottom", 1, 0, "hero_bio_title", "body_bold")
		paint.label(row.bio, Rect2(136, 468, 330, 85), 15, GOLD, "left", "top", 0, 0, "hero_bio")
		paint.label(strings["Special abilities"], Rect2(136, 556, 330, 24), 17, Color("9b4e1d"), "left", "bottom", 1, 0, "hero_special_title", "body_bold")
		paint.label(row.special, Rect2(136, 582, 330, 65), 15, GOLD, "left", "top", 0, 0, "hero_special")
		for stat in range(4):
			for dot in mini(8, mini(int(row.stats[stat]), int(stats_time * 20))):
				paint.image("heroroom_buttons", Vector2(610 + dot * 20, 483 + stat * 35))
	# The source select group is above the description plate in sibling order.
	if not progress.is_hero_unlocked(shown):
		paint.image("heroroom_unlock", Vector2(567, 396))
		paint.label(strings.MAP_HERO_ROOM_UNLOCK % str(int(row.available_level)), Rect2(662, 417, 108, 36), 13, Color.WHITE, "center", "middle", 2, 1, "hero_unlock", "sans_bold")
	else:
		var selected: bool = shown in progress.heroes.selected
		_button("heroroom_selectBtn_0001" if selected else "heroroom_selectBtn_0003", Vector2(612, 400), strings.MAP_HERO_ROOM_DESELECT if selected else strings.MAP_HERO_ROOM_SELECT, "deselect" if selected else "select")
	_button("heroroom_btnDone_large_0001", Vector2(665.5, 662.5), strings.BUTTON_DONE, "close")
	_button("heroroom_btnDone_large_0001", Vector2(151.5, 662.5), "英雄资料" if details_mode else "技能详情", "toggle")
	paint.label("当前试玩版英雄尚不参战", Rect2(310, 695, 305, 25), 13, Color("ccb58b"), "center", "middle", 1, 0, "hero_preview_notice")
	paint.image("levelSelect_closeBtn_0002" if hovered == "close_icon{}" else "levelSelect_closeBtn_0001", Vector2(869, 23))
	paint.hit(Rect2(869, 23, 40, 38), "close_icon")
	if progress.notice != "": paint.label(progress.notice, Rect2(90, 728, 740, 24), 12, GOLD, "center", "middle", 1)
	paint.pop()

func _button(image: String, at: Vector2, text: String, action: String) -> void:
	var over := hovered == action + "{}"
	paint.image(image.replace("_0001", "_0002").replace("_0003", "_0004") if over else image, at)
	var dimensions: Vector2 = paint.image_size(image)
	paint.display_label(text, Rect2(at + Vector2(16, 5), dimensions - Vector2(32, 16)), 24, GOLD, "button", action, 1)
	paint.hit(Rect2(at, dimensions), action)

func show_hero(id: String) -> void:
	if progress.hero(id).is_empty(): return
	shown = id; skill = 0; stats_time = 0; _update_detail()
	grid.queue_redraw(); queue_redraw()

func _update_detail() -> void:
	var entries: Array = progress.hero(shown).get("details", [])
	if entries.is_empty(): return
	skill = clampi(skill, 0, entries.size() - 1)
	detail_text.text = entries[skill].text
	detail_scroll.scroll_vertical = 0

func tab_focus() -> void:
	var selected: Array = progress.heroes.selected
	if selected.is_empty(): return
	var index: int = selected.find(shown)
	show_hero(selected[(index + 1) % selected.size()])
	var rows: Array = progress.hero_definition.heroes
	for i in rows.size():
		if rows[i].name == shown:
			var top := (i / 7) as int * 50
			if top < scroll.scroll_vertical: scroll.scroll_vertical = top
			elif top + 53 > scroll.scroll_vertical + 244: scroll.scroll_vertical = top + 53 - 244

func _action(action: String, args: Dictionary = {}) -> void:
	hits.clear(); hovered = ""
	match action:
		"close", "close_icon": map.close_overlay(); return
		"retry": _load(); return
		"toggle": details_mode = not details_mode; _update_detail()
		"skill": skill = int(args.index); _update_detail()
		"select":
			if progress.select_hero(shown): play_sound(progress.hero(shown).get("sound", ""), true)
		"deselect": progress.deselect_hero(shown)
	play_sound("GUIBuyUpgrade" if action in ["select", "deselect"] else "GUIButtonCommon")
	map.queue_redraw(); grid.queue_redraw(); queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = ""
		for hit: Dictionary in hits:
			if hit.rect.has_point(event.position / zoom): hovered = hit.action + str(hit.args)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" else CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: map.close_overlay()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			for hit: Dictionary in hits:
				if hit.rect.has_point(event.position / zoom): _action(hit.action, hit.args); break
	accept_event(); queue_redraw()

func play_sound(id: String, is_voice: bool = false) -> void:
	if id == "" or catalog == null or DisplayServer.get_name() == "headless": return
	var sound: Dictionary = catalog.get_sound(id)
	if sound.is_empty(): return
	var path: String = sound.paths[randi_range(0, sound.paths.size() - 1)]
	if not streams.has(path): streams[path] = load(path)
	var player: AudioStreamPlayer = voice if is_voice else click_sound
	player.stop(); player.stream = streams[path]; player.volume_db = linear_to_db(float(sound.get("gain", 1))); player.play()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and voice != null: voice.stop(); click_sound.stop()

func _exit_tree() -> void:
	voice.stop(); voice.stream = null; click_sound.stop(); click_sound.stream = null
	frames.clear(); streams.clear(); catalog = null
