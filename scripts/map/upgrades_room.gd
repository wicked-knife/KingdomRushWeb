extends Control
## Default Dove tree; the same transform controls art, text and hit testing.
const Layout = preload("res://scripts/battle/dove_ui_layout.gd")
const Upgrades = preload("res://scripts/battle/dove_upgrades.gd")
var map: Control
var paint: RefCounted
var zoom := 1.0
var hits: Array = []
var hovered := ""
var shown := ""
var original := {}
var can_undo := false
var bought_fx := {}
var elapsed := 0.0
var panel_at := Vector2.ZERO
var panel_scale := 1.0

func initialize(owner_map: Control) -> void:
	map = owner_map; name = "UpgradesRoom"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = MOUSE_FILTER_STOP
	paint = Layout.new(self, map.fonts, 1080); hide()

func open() -> void:
	original = map.progress.data.upgrades.duplicate(true); can_undo = false
	hits.clear(); hovered = ""; shown = ""; bought_fx.clear(); show(); queue_redraw()

func _frame(id: String) -> Dictionary: return map._frame(id)

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta; queue_redraw()

func _draw() -> void:
	if paint == null or not visible or size.y <= 0: return
	zoom = size.y / 1080.0
	var view_size := size / zoom
	panel_scale = minf(1.25, minf((view_size.x - 48) / 920, (1080 - 48) / 764.0))
	panel_at = (view_size - Vector2(920, 764) * panel_scale) / 2
	hits.clear(); paint.begin(); paint.push(panel_at, panel_scale)
	paint.image("Upgrades_BG_notxt")
	paint.display_label(Upgrades.definition().title, Rect2(300, 30, 300, 42), 32, Color("f7eaba"), "h_map", "technology_title", 1)
	paint.button("levelSelect_closeBtn_0001", Vector2(865, 20), "", "close")
	var summary: Dictionary = map.progress.upgrade_summary()
	if not summary.supported:
		paint.label(summary.error, Rect2(170, 250, 580, 180), 24, Color("f7eaba"), "center", "middle")
		paint.pop(); return
	paint.image("Upgrades_StarContainer", Vector2(75, 640))
	paint.display_label(str(summary.available), Rect2(88, 653, 110, 37), 30, Color("fff6cf"), "numbers_bold", "available_stars", 1)
	var classes: Array = Upgrades.definition().classes
	for index in classes.size():
		var x: float = [121, 243, 361, 483, 604, 724][index]
		paint.label(["弓箭", "兵营", "法师", "炮兵", "火雨", "援军"][index], Rect2(x - 6, 80, 80, 24), 17, Color("eac88d"), "center", "middle", 1, 1)
	for id: String in Upgrades.definition().techs:
		var tech: Dictionary = Upgrades.definition().techs[id]
		var index: int = classes.find(tech.class)
		var point := Vector2([121, 243, 361, 483, 604, 724][index], 520 - int(tech.level) * 80 * 0.83)
		var bought: bool = int(summary.levels[tech.class]) >= int(tech.level)
		var candidate: Dictionary = summary.levels.duplicate(); candidate[tech.class] = int(tech.level)
		var enabled: bool = bought or Upgrades.spent(candidate) <= int(summary.total)
		paint.push(point, 0.83)
		paint.image(tech.image, Vector2.ZERO, Vector2.ZERO, Color.WHITE if enabled else Color(0.45, 0.45, 0.45))
		if bought: paint.image("Upgrades_Icons_Bought")
		elif shown == id: paint.image("Upgrades_Icons_over")
		if not bought:
			var prefix := "" if enabled else "Disabled_"
			paint.image(prefix + "Upgrades_Icons_PriceTag", Vector2(35, 55))
			paint.image(prefix + "Upgrades_Icons_PriceTag_Nm_%04d" % int(tech.price), Vector2(51, 65), Vector2(0.5, 0.5))
		if bought_fx.has(id) and elapsed - float(bought_fx[id]) < 0.6:
			paint.image("Upgrades_Icons_buyFx_%04d" % (1 + mini(17, int((elapsed - float(bought_fx[id])) * 30))), Vector2(-22, -22))
		paint.hit(Rect2(0, 0, 82, 82), "upgrade", {"id":id}, enabled)
		paint.pop()
	paint.button("Upgrades_Btns_notxt_0001", Vector2(240, 630), Upgrades.definition().strings.BUTTON_RESET, "reset", {}, summary.spent > 0)
	paint.button("Upgrades_Btns_notxt_0001", Vector2(550, 630), Upgrades.definition().strings.BUTTON_UNDO, "undo", {}, can_undo)
	paint.button("Upgrades_Btns_notxt_0001", Vector2(680, 630), Upgrades.definition().strings.BUTTON_DONE, "close")
	paint.pop()
	if shown != "": _tooltip(summary, view_size)

func _tooltip(summary: Dictionary, view_size: Vector2) -> void:
	var tech: Dictionary = Upgrades.definition().techs[shown]
	var column: int = Upgrades.definition().classes.find(tech.class)
	var point := Vector2([121, 243, 361, 483, 604, 724][column], 520 - int(tech.level) * 80 * 0.83)
	var tip_size := Vector2(330, 165)
	var at := panel_at + (point + Vector2(85, -170)) * panel_scale
	if at.x + tip_size.x * panel_scale > view_size.x - 20: at.x = panel_at.x + (point.x - tip_size.x - 5) * panel_scale
	at.y = clampf(at.y, 24, view_size.y - tip_size.y * panel_scale - 24)
	paint.push(at, panel_scale); paint._apply()
	draw_rect(Rect2(Vector2.ZERO, tip_size), Color(0.082, 0.067, 0.051, 0.96))
	draw_rect(Rect2(Vector2.ZERO, tip_size), Color("92784b"), false, 1)
	paint.display_label(tech.title, Rect2(16, 10, 240, 27), 20, Color.WHITE, "body", "tech_title")
	paint.image("Upgrades_Tips_Star", Vector2(275, 13))
	paint.display_label(str(int(tech.price)), Rect2(299, 10, 24, 27), 19, Color.WHITE, "numbers", "tech_price")
	paint.label(tech.description, Rect2(16, 42, 298, 85), 18, Color("f5cb06"), "left", "top", 0, 0, "tech_description")
	var bought: bool = int(summary.levels[tech.class]) >= int(tech.level)
	var candidate: Dictionary = summary.levels.duplicate(); candidate[tech.class] = int(tech.level)
	var cost := Upgrades.spent(candidate) - int(summary.spent)
	paint.label("已购买 · 点击退还本级及之后等级" if bought else ("购买至此级共需 %d 星" % cost if cost <= int(summary.available) else "需要 %d 星，余额不足" % cost), Rect2(16, 134, 298, 22), 15, Color("ccb58e"), "left", "middle", 1)
	paint.pop()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = ""; shown = ""
		for hit: Dictionary in hits:
			if hit.rect.has_point(event.position / zoom):
				hovered = hit.action + str(hit.args)
				if hit.action == "upgrade": shown = hit.args.id
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" else CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: map.close_overlay(); accept_event(); return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		for hit: Dictionary in hits:
			if hit.rect.has_point(event.position / zoom):
				if hit.action == "upgrade": shown = hit.args.id
				if hit.enabled: action(hit.action, hit.args)
				accept_event(); break

func action(kind: String, args: Dictionary = {}) -> void:
	hits.clear()
	match kind:
		"close": map.close_overlay(); map._sound("GUIButtonCommon"); return
		"reset":
			if map.progress.reset_upgrades(): original = map.progress.data.upgrades.duplicate(true); can_undo = false
		"undo":
			if can_undo and map.progress.restore_upgrades(original): can_undo = false
		"upgrade":
			var tech: Dictionary = Upgrades.definition().techs[args.id]
			var current := int(map.progress.data.upgrades.get(tech.class, 0))
			var target: int = int(tech.level) - 1 if current >= int(tech.level) else int(tech.level)
			if not map.progress.set_upgrade_level(tech.class, target): return
			can_undo = true; bought_fx[args.id] = elapsed; map._sound("GUIBuyUpgrade"); queue_redraw(); return
	map._sound("GUIButtonCommon"); queue_redraw()
