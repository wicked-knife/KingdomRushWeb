extends RefCounted
## Transient debug UI; all mutations are validated by the simulation commands.
var view: Control
var opened := false
var previous_pause := false

func _init(battle: Control) -> void: view = battle

func toggle() -> void:
	if not view.sim.developer_enabled or view.sim.result != "": return
	if opened: close()
	else:
		previous_pause = view.sim.paused; view.sim.paused = true; opened = true
		view.selected = ""; view.selected_unit = 0; view.targeting = ""
	view.hits.clear(); view.queue_redraw()

func close() -> void:
	if not opened: return
	opened = false
	view.sim.paused = previous_pause if view.sim.result == "" else false
	view.hits.clear(); view.queue_redraw()

func execute(command: String) -> bool:
	if not opened: return false
	var accepted: bool = view.sim.command(command)
	if accepted and command == "dev_skip_wave": close()
	return accepted

func hud() -> void:
	var paint: RefCounted = view.interface.paint
	if view.sim.developer_enabled and view.sim.result == "":
		paint.push(Vector2(view.view_width - 294, 2), 0.6)
		paint.button("options_button_bg_0001", Vector2.ZERO, "DEV · F8", "developer", {}, true, "options", "numbers_bold")
		paint.pop()
	if view.sim.developer_used:
		paint.label("调试", Rect2(315, 8, 86, 32), 18, Color("ffdf70"), "center", "middle", 1, 1, "debug_badge", "body_bold")

func draw() -> void:
	view._dim()
	var ui: RefCounted = view.interface
	var paint: RefCounted = ui.paint
	var dimensions: Vector2 = paint.image_size("options_bg_notxt")
	ui._panel("developer", dimensions, 1.15, 0.15)
	paint.image("options_bg_notxt")
	paint.label("开发者菜单", Rect2(140, 28, 235, 38), 26, Color.WHITE, "center", "middle", 1, 2, "dev_title", "h_popup")
	paint.label("本局成绩正常保存", Rect2(100, 78, dimensions.x - 200, 28), 16, Color("e9e9b2"), "center", "middle", 1)
	var button: Vector2 = paint.image_size("options_button_bg_0001")
	var x := (dimensions.x - button.x) / 2
	paint.button("options_button_bg_0001", Vector2(x, 118), "+10000 金币", "dev_add_gold", {}, true, "options", "numbers_bold")
	paint.button("options_button_bg_0001", Vector2(x, 182), "+100 生命", "dev_add_lives", {}, true, "options", "numbers_bold")
	var can_skip: bool = view.sim.wave > 0 and view.sim.notices.is_empty() and view.sim.result == ""
	paint.button("options_button_bg_0001", Vector2(x, 246), "跳过此波", "dev_skip_wave", {}, can_skip)
	paint.label("请先开始战斗并确认教学" if not can_skip else "清场并进入下一波", Rect2(75, 303, dimensions.x - 150, 24), 14, Color("e9e9b2"), "center", "middle", 1)
	paint.button("options_button_bg_0001", Vector2(x, 338), "关闭", "developer")
	ui._end_panel()
