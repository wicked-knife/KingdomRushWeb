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
var pointer := Vector2.ZERO

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
	paint.image("Upgrades_StarContainer", Vector2(100,637))
	paint.display_label(str(summary.available), Rect2(145,648,72,38),32,Color("e7deaf"),"numbers","available_stars")
	var classes: Array = Upgrades.definition().classes
	for index in classes.size():
		var x: float = [121, 243, 361, 483, 604, 724][index]
		var level := int(summary.levels[classes[index]])
		if level > 0:
			paint.image("YellowBar",Vector2([152,274,394,514,636,755][index],538),Vector2(6,376)/paint.image_size("YellowBar"),Color.WHITE,Vector2(1,0.2*level*0.83))
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
		var icon_size: Vector2 = paint.image_size(tech.image)
		if bought: paint.image("Upgrades_Icons_Bought",icon_size/2,Vector2(0.5,0.5))
		elif shown == id and enabled: paint.image("Upgrades_Icons_over",icon_size/2,Vector2(0.5,0.5))
		if not bought:
			var prefix := "" if enabled else "Disabled_"
			paint.image(prefix + "Upgrades_Icons_PriceTag", Vector2(35, 55))
			paint.image(prefix + "Upgrades_Icons_PriceTag_Nm_%04d" % int(tech.price), Vector2(35,55)+paint.image_size(prefix+"Upgrades_Icons_PriceTag")/2+Vector2(4,0), Vector2(0.5, 0.5))
		if bought_fx.has(id) and elapsed - float(bought_fx[id]) < 0.6:
			paint.image("Upgrades_Icons_buyFx_%04d" % (1 + mini(17, int((elapsed - float(bought_fx[id])) * 30))), Vector2(-22, -22))
		paint.hit(Rect2(0, 0, 82, 82), "upgrade", {"id":id}, enabled)
		paint.pop()
	paint.button("Upgrades_Btns_notxt_0001", Vector2(240, 630), Upgrades.definition().strings.BUTTON_RESET, "reset", {}, summary.spent > 0)
	paint.button("Upgrades_Btns_notxt_0001", Vector2(550, 630), Upgrades.definition().strings.BUTTON_UNDO, "undo", {}, can_undo)
	paint.button("Upgrades_Btns_notxt_0001", Vector2(680, 630), Upgrades.definition().strings.BUTTON_DONE, "close")
	paint.pop()
	if shown != "": _tooltip(summary, view_size)

func _tooltip(_summary: Dictionary, view_size: Vector2) -> void:
	var tech: Dictionary = Upgrades.definition().techs[shown]
	var text_height: float=paint.text_size(tech.description,280,18).y
	var tip_size := Vector2(320,33+text_height+22)
	# Source tooltip follows the pointer, anchored fifteen units right and above.
	var at := pointer+Vector2(15,-tip_size.y-10)*panel_scale
	at.x=clampf(at.x,20,view_size.x-tip_size.x*panel_scale-20)
	at.y=clampf(at.y,20,view_size.y-tip_size.y*panel_scale-20)
	paint.push(at, panel_scale); paint._apply()
	draw_rect(Rect2(Vector2.ZERO, tip_size), Color(21.0/255,17.0/255,13.0/255,0.9))
	paint.image("Upgrades_Tips_tip",Vector2(-14,tip_size.y-20))
	paint.label(tech.title,Rect2(20,8,240,22),18,Color.WHITE,"left","top",1,0,"tech_title")
	paint.image("Upgrades_Tips_Star",Vector2(270,10))
	paint.label(str(int(tech.price)),Rect2(295,8,25,22),18,Color.WHITE,"left","top",1,0,"tech_price","numbers")
	paint.label(tech.description,Rect2(20,33,280,text_height+1),18,Color("f5cb06"),"left","top",0,0,"tech_description")
	paint.pop()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer=event.position/zoom
		hovered = ""; shown = ""
		for hit: Dictionary in hits:
			if hit.rect.has_point(event.position / zoom):
				hovered = hit.action + str(hit.args)
				if hit.action == "upgrade": shown = hit.args.id
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" else CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		pointer=event.position/zoom
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
