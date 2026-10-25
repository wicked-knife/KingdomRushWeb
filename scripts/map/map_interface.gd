extends RefCounted
## Source-sized map HUD and popup compositions. Fixed artwork is never resized to fit text.
var view: Control
var paint: RefCounted
const PAPER_INK := Color("403924")
const GOLD := Color("f7eaba")
var flow_cache := {}

func _init(owner_view: Control) -> void: view = owner_view; paint = view.paint

func draw() -> void:
	var sw: float = view.view_size.x
	_button("map_configBtn_0001", "map_configBtn_0002", Vector2(15, 5), "options")
	paint.image("mapStarsContainerEmpty", Vector2(sw - 347, 30))
	paint.image("mapStarsContainerIcons_0001", Vector2(sw - 287, 30))
	# map_counters_view.lua uses numbers_bold (TOONISH), a 110 x 36 box,
	# capital-height centering and a 2 px shadow, rather than italic numbers.
	paint.label("%d/%d" % [view.progress.total_stars(), int(view.definition.max_stars)], Rect2(sw - 232, 40, 110, 36), 30, Color("e4bc72"), "left", "middle-caps", 1, 0, "map_stars", "numbers_bold", Vector2(2, 2), Color("25241e"))
	var buttons := [["mapButtons_notxt_0001", "mapButtons_notxt_0002", "英雄", 95.0], ["mapButtons_notxt_0010", "mapButtons_notxt_0011", "科技", sw - 440], ["mapButtons_notxt_0007", "mapButtons_notxt_0008", "图鉴", sw - 270], ["mapButtons_notxt_0004", "mapButtons_notxt_0005", "成就", sw - 100]]
	for item: Array in buttons:
		var at := Vector2(float(item[3]) - 113, 898)
		var hero_button: bool = item[2] == "英雄"
		paint.image(item[1] if hero_button and view.hovered == "heroes{}" else item[0], at, Vector2.ZERO, Color.WHITE if hero_button else Color(0.65, 0.65, 0.65))
		if hero_button: _hero_icon(at)
		paint.label(item[2], Rect2(at + Vector2(50, 121), Vector2(126, 30)), 18, Color("e4bc72"), "center", "middle", 1, 1, "", "h_map")
		if not hero_button: paint.label("暂未开放", Rect2(at + Vector2(50, 151), Vector2(126, 24)), 15, Color("ccb58b"), "center", "middle", 1, 1)
		if view.overlay == "": paint.hit(Rect2(at + Vector2(40, 20), Vector2(146, 152)), "heroes" if hero_button else "unavailable")
	if view.overlay != "":
		paint._apply(); view.draw_rect(Rect2(Vector2.ZERO, view.view_size), Color(0, 0, 0, 0.58))
		# Underlying HUD is also inert while a modal is open.
		view.hits.clear()
		if view.overlay == "level": _level()
		elif view.overlay == "options": _options()
	if view.message_until > view.animation_player.time:
		paint.label(view.message, Rect2(sw / 2 - 360, 1002, 720, 42), 23, GOLD, "center", "middle", 2, 2)
	elif view.progress.notice != "":
		paint.label(view.progress.notice, Rect2(180, 1010, sw - 360, 50), 18, GOLD, "center", "middle", 2, 1)

func _hero_icon(at: Vector2) -> void:
	var selected: Array = view.progress.heroes.selected
	if selected.is_empty(): paint.image("mapButtons_portrait_hero_0000", at); return
	if selected.size() == 1: paint.image(view.progress.hero(selected[0]).map_icon, at); return
	# Clip in the original 226 x 184 canvas, then map the trimmed polygon back to
	# the derived atlas. This preserves Dove's diagonal without sampling neighbours.
	var w := 226.0; var h := 184.0; var d := w / 5.0
	var halves := [PackedVector2Array([Vector2.ZERO, Vector2(w / 2 + d, 0), Vector2(w / 2 - d, h), Vector2(0, h)]), PackedVector2Array([Vector2(w / 2 + d, 0), Vector2(w, 0), Vector2(w, h), Vector2(w / 2 - d, h)])]
	paint._apply()
	for i in range(2):
		var frame: Dictionary = view._frame(view.progress.hero(selected[i]).map_icon)
		var texture: AtlasTexture = frame.texture
		var trim: Vector2 = frame.trim * frame.ref_scale
		var dimensions: Vector2 = frame.logical_size * frame.ref_scale
		var bounds := PackedVector2Array([trim, trim + Vector2(dimensions.x, 0), trim + dimensions, trim + Vector2(0, dimensions.y)])
		for polygon: PackedVector2Array in Geometry2D.intersect_polygons(halves[i], bounds):
			var points := PackedVector2Array(); var uv := PackedVector2Array()
			for point: Vector2 in polygon:
				points.append(point + at)
				uv.append((texture.region.position + (point - trim) / frame.ref_scale) / texture.atlas.get_size())
			view.draw_polygon(points, PackedColorArray([Color.WHITE]), uv, texture.atlas)

func _button(normal: String, over: String, at: Vector2, action: String, args: Dictionary = {}, enabled: bool = true, caption: String = "") -> void:
	var dimensions: Vector2 = paint.image_size(normal)
	paint.image(over if enabled and view.hovered == action + str(args) else normal, at, Vector2.ZERO, Color.WHITE if enabled else Color(0.55, 0.55, 0.55))
	if caption != "": paint.label(caption, Rect2(at + Vector2(8, 8), dimensions - Vector2(16, 16)), 22, GOLD, "center", "middle", 2, 1, "button:" + action, "button")
	paint.hit(Rect2(at, dimensions), action, args, enabled)

func _popup(frame: String) -> void:
	var dimensions: Vector2 = paint.image_size(frame)
	var factor := minf(1.0, minf((view.view_size.x - 60) / dimensions.x, 980.0 / dimensions.y))
	var at: Vector2 = (view.view_size - dimensions * factor) / 2 - Vector2(0, 50)
	paint.push(at, factor); paint.image(frame)

func _level() -> void:
	var stage: Dictionary = {}
	for item: Dictionary in view.definition.levels:
		if int(item.id) == view.selected_level: stage = item; break
	if stage.is_empty(): return
	var record: Dictionary = view.progress.record(view.selected_level)
	var stars := int(record.get("stars", 0))
	_popup("levelSelect_background")
	_button("levelSelect_closeBtn_0001", "levelSelect_closeBtn_0002", Vector2(1152, 30), "close")
	_title("%d %s" % [view.selected_level, stage.title], Vector2(214, 86), 360, 36, 2)
	paint.image(stage.thumbnail, Vector2(215, 190))
	paint.image("levelSelect_thumbFrame", Vector2(202, 175))
	for i in range(5):
		var badge := (1 if i < stars else 2) if i < 3 else (4 if i == 3 else 6)
		paint.push(Vector2(310 + i * 35, 490), 0.8)
		paint.image("levelSelect_badges_%04d" % badge); paint.pop()
	var titles := [view.definition.strings.Campaign, view.definition.strings.Heroic, view.definition.strings.Iron]
	for index in range(3):
		var mode := index + 1
		var enabled: bool = mode == 1 or stars >= 3
		var base: int = [1, 5, 9][index] if enabled else [1, 4, 8][index]
		if mode == view.mode: base = [3, 7, 11][index]
		var at := Vector2(1105, 175 + index * 85)
		var args := {"mode": mode, "reason": "战役获得三星后开放查看"}
		var over: bool = enabled and mode != view.mode and view.hovered == "mode" + str(args)
		# Locked tabs already have their own artwork; do not gray-tint them again.
		paint.image("levelSelect_Mode_notxt_%04d" % (base + 1 if over else base), at)
		paint.hit(Rect2(at, paint.image_size("levelSelect_Mode_notxt_%04d" % base)), "mode", args, enabled)
		var center_x := 53 if mode == view.mode else 40
		var ink := Color("8ed5f6") if mode == view.mode else (Color("5f3b26") if over else Color("c6865f"))
		paint.display_label(titles[index], Rect2(at + Vector2(center_x - 34, 47 if mode == 1 else 45), Vector2(68, 22)), 13, ink, "body", "mode_tab")
	_title(titles[view.mode - 1], Vector2(690, 84), 360, 32)
	if view.mode == 1:
		_description(str(stage.history))
	else:
		_description(view.definition.strings["LEVEL_MODE_HEROIC_DESCRIPTION" if view.mode == 2 else "LEVEL_MODE_IRON_DESCRIPTION"], 278)
		paint.image("levelSelect_modebg_notxt_0001", Vector2(682, 310))
		_title("挑战规则", Vector2(690, 270), 360, 26, 1, Color("8e835b"))
		var level: int = int(stage.rules.get("upgrades", {}).get("level", 0))
		var heroes: bool = stage.rules.get("upgrades", {}).get("heroe", false)
		paint.image("levelSelect_modeRules_0010", Vector2(710, 328))
		paint.label("科技等级上限\n%d" % level, Rect2(756, 328, 90, 46), 11, PAPER_INK, "center", "middle", 2)
		paint.image("levelSelect_modeRules_%04d" % (11 if heroes else 9), Vector2(890, 328))
		paint.label("允许英雄" if heroes else "无英雄", Rect2(936, 328, 90, 46), 11, PAPER_INK, "center", "middle", 2)
		if view.mode == 3:
			paint.image("levelSelect_modebg_notxt_0002", Vector2(682, 380))
			for index in range(4):
				var locked: Array = stage.rules.get("iron", [])
				var value: int = 2 * index + (2 if ["archers", "barracks", "mages", "artillery"][index] in locked else 1)
				paint.image("levelSelect_modeRules_%04d" % value, Vector2(770 + index * 50, 400))
	paint.image("levelSelect_difficulty_0003", Vector2(982, 522))
	if int(record.get("campaign", 0)) > 0 and view.mode == 1: paint.image("levelSelect_difficultyCompleted_0002", Vector2(690, 520))
	var playable: bool = view.progress.is_playable(view.selected_level, view.mode, 2)
	var battle_args := {"reason": "尚未实现" if view.mode == 1 else "此挑战玩法暂未开放"}
	_button("levelSelect_startMode_notxt_%04d" % (2 * view.mode - 1), "levelSelect_startMode_notxt_%04d" % (2 * view.mode), Vector2(805, 470), "battle", battle_args, playable)
	var over: bool = playable and view.hovered == "battle" + str(battle_args)
	var ink := Color.WHITE if over else Color("f3c698")
	var edge := Color("ce2316") if over else Color("5f060d")
	if not playable: ink = Color("a38b72")
	paint.display_label("进入", Rect2(805, 537, 122, 26), 15, ink, "h_noti", "battle_caption_top", 3, edge)
	paint.display_label("战斗", Rect2(805, 557, 122, 36), 22, ink, "h_noti", "battle_caption_bottom", 3, edge)
	if not playable:
		paint.label("尚未实现" if view.mode == 1 else "暂未开放", Rect2(784, 593, 164, 30), 20, Color("a04423"), "center", "middle", 1, 0, "", "button")
	paint.pop()

func _title(value: String, at: Vector2, width: float, font_size: int, lines: int = 1, ink: Color = Color("645934")) -> void:
	var rect := Rect2(at + Vector2(60, 0), Vector2(width - 120, 80 if lines == 2 else 40))
	paint.label(value, rect, font_size, ink, "center", "middle", lines, 0, "level_title", "h_book")
	# Decorative curls follow the measured title width, as in the source.
	var half: float = paint.audit[-1].extent.x / 2
	paint.image("levelSelect_volutas_0001", at + Vector2(width / 2 - half - 8, rect.size.y / 2 + 3), Vector2(0, 0.5), Color.WHITE, Vector2(-1, 1))
	paint.image("levelSelect_volutas_0001", at + Vector2(width / 2 + half + 10, rect.size.y / 2 + 3), Vector2(0, 0.5))

func _description(value: String, bottom: float = 468) -> void:
	paint.image("levelSelect_capitular_bg", Vector2(690, 124))
	# Exclude the crown ornament and the font's internal line leading.
	paint.display_label(value.substr(0, 1), Rect2(694, 155, 80, 70), 56, GOLD, "capitals", "history_capital")
	_history(value.substr(1), Rect2(700, 154, 350, bottom - 154))

func _history(value: String, rect: Rect2) -> void:
	# Keep mandatory breaks beside the capital, then join the remaining CJK
	# lines as add_level_description does, without translation-file paragraph gaps.
	value = value.replace("\r", "")
	var face: Font = view.fonts.font_for("body")
	var key := str([value, rect.size, face.get_instance_id()])
	if not flow_cache.has(key):
		for half_size in range(35, 11, -1):
			var nominal := half_size / 2.0
			var actual: int = view.fonts.size_for("body", nominal)
			var paragraph := TextParagraph.new(); paragraph.width = 272
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.add_string(value, face, actual, "zh_CN")
			var count := 0; var height := 0.0
			var beside_lines := maxi(1, ceili(71.0 / paragraph.get_line_size(0).y))
			while count < mini(paragraph.get_line_count(), beside_lines):
				height += paragraph.get_line_size(count).y; count += 1
			var end := paragraph.get_line_range(maxi(0, count - 1)).y
			var remainder := value.substr(end).replace("\n", "")
			var rest := TextParagraph.new(); rest.width = rect.size.x; rest.break_flags = paragraph.break_flags
			rest.add_string(remainder, face, actual, "zh_CN")
			flow_cache[key] = {"first": value.left(end).strip_edges(), "rest": remainder, "height": height, "size": nominal}
			if height + rest.get_size().y <= rect.size.y: break
	var flow: Dictionary = flow_cache[key]
	paint.label(flow.first, Rect2(rect.position + Vector2(76, 0), Vector2(272, flow.height)), flow.size, PAPER_INK, "left", "top", 0, 0, "level_history")
	paint.label(flow.rest, Rect2(rect.position + Vector2(0, flow.height), Vector2(rect.size.x, rect.size.y - flow.height)), flow.size, PAPER_INK, "left", "top", 0, 0, "level_history")

func _options() -> void:
	_popup("options_bg_notxt")
	paint.label("选 项", Rect2(200, 34, 320, 48), 34, Color.WHITE, "center", "middle", 1, 2, "", "h_popup")
	_volume("音效", 130, "sfx", view.settings.sfx_volume, 4)
	_volume("音乐", 235, "music", view.settings.music_volume, 1)
	paint.label("普通难度", Rect2(200, 358, 320, 40), 26, GOLD, "center", "middle", 1, 1)
	_button("options_button_bg_0001", "options_button_bg_0002", Vector2(78, 445), "menu", {}, true, "返回主菜单")
	_button("options_button_bg_0001", "options_button_bg_0002", Vector2(420, 445), "close", {}, true, "继续")
	paint.pop()

func _volume(caption: String, y: float, bus: String, value: float, index: int) -> void:
	paint.label(caption, Rect2(240, y, 240, 30), 25, GOLD, "center", "middle", 1, 1)
	var track: Vector2 = paint.image_size("options_barBg")
	var at := Vector2((720 - track.x) / 2, y + 42)
	var fill: Vector2 = paint.image_size("options_bar")
	var offset := Vector2(track.x * 0.0266666667, track.y / 3)
	paint.image("options_barBg", at)
	paint.image("options_bar", at + offset, Vector2.ZERO, Color.WHITE, Vector2(value, 1))
	paint.image("options_sounds_%04d" % index, at + Vector2(offset.x + fill.x * value, track.y / 2), Vector2(0.5, 0.5))
	paint.hit(Rect2(at, track).grow(14), "volume", {"bus": bus, "track": paint.region(Rect2(at + offset, fill))})
