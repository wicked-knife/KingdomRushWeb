extends RefCounted
## Presentation-only Dove markers and MousePointer; never advances the simulation RNG.
var view: Control
var time := 0.0
var mode := ""
var mode_at := 0.0
var inside := true
var focused := true
var rally_fx := {}

func _init(owner_view: Control) -> void:
	view = owner_view

func reset() -> void:
	mode = ""; rally_fx.clear()
	sync_cursor()

func advance(delta: float) -> void:
	time += delta
	if not rally_fx.is_empty() and time - rally_fx.at >= 1.5: rally_fx.clear()
	sync_cursor()

func active() -> bool:
	return view.is_visible_in_tree() and inside and focused and view.targeting != "" and not view.sim.paused and view.sim.notices.is_empty() and view.sim.result == "" and not view.developer.opened

func sync_cursor() -> void:
	if mode != view.targeting:
		mode = view.targeting; mode_at = time
	var wanted := cursor_mode()
	if Input.mouse_mode != wanted: Input.mouse_mode = wanted

func cursor_mode() -> int:
	return Input.MOUSE_MODE_HIDDEN if active() else Input.MOUSE_MODE_VISIBLE

func pointer_frame() -> String:
	var elapsed := time - mode_at
	if view.targeting == "rally": return "pointer_set_rally_%04d" % (1 + int(elapsed * 30) % 10)
	if view.targeting == "fire": return "pointer_fireball_%04d" % (1 + int(elapsed * 30) % 32)
	return "pointer_point_orange_%04d" % (1 + int(elapsed * 30) % 10)

func draw_pointer() -> void:
	if not active(): return
	view._art(view.target_pointer_frame(), view.pointer)
	if view.invalid_point_time > 0 or view.targeting == "rally": return
	view._art("pointer_user_power_0001" if view.targeting == "fire" else "pointer_user_power_0002", view.pointer, Vector2(0.5, 0))

func rallied(point: Vector2) -> void:
	rally_fx = {"pos": point, "at": time}

func draw_rally_feedback() -> void:
	if rally_fx.is_empty() or not view.sim.notices.is_empty() or view.sim.result != "": return
	var age: float = time - rally_fx.at
	view._art("rally_feedback_%04d" % mini(30, 1 + int(age * 30)), view.world(rally_fx.pos), Vector2(0.5, 0.5), 1, Color(1, 1, 1, pow(1 - age / 1.5, 2)))

func _marker(key: String, point: Vector2, offset: Vector2 = Vector2.ZERO) -> void:
	var spec: Dictionary = view.sim.data.ui.selection_markers[key]
	var frame: String = spec.name
	if view.sim.animations.has(frame):
		var animation: Dictionary = view.sim.animations[frame]
		frame = "%s_%04d" % [animation.prefix, animation.frames[int(time * 30) % animation.frames.size()]]
	view.draw_list.append({"scale": Vector2.ONE, "frame": frame, "pos": point + offset, "sort_y": point.y,
		"anchor": view.Simulation.vec(spec.anchor), "z": int(spec.z), "order": view.draw_list.size(),
		"flip": false, "rotation": 0.0, "tint": Color.WHITE})

func _unit_marker(unit: Dictionary) -> void:
	if unit.is_empty() or unit.hp <= 0 or unit.get("hidden", false): return
	var template: Dictionary = view.sim.templates[unit.template]
	var key: String = "soldier_small" if template.has("soldier") else {1:"small", 2:"med", 3:"big"}.get(int(template.unit.size), "small")
	_marker(key, unit.pos, view.Simulation.vec(template.unit.marker_offset))

func queue_markers() -> void:
	if view.selected_unit != 0: _unit_marker(view.sim.unit_by_id(view.selected_unit))
	var tower: Dictionary = view.sim.tower_by_id(view.selected)
	if tower.is_empty() or not view.sim.tower_template(tower).has("barrack"): return
	_marker("rally", tower.rally)
	for soldier: Dictionary in view.sim.soldiers:
		if soldier.home == tower.id: _unit_marker(soldier)
