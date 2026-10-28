extends RefCounted
## Optional level hooks; the simulator retains ownership of all combat scheduling.

func reset(_sim) -> void: pass
func wave_started(_sim, _group: Dictionary) -> void: pass
# Called in lane order, before the corresponding tip event.
func wave_notification(_sim, _entry: Dictionary) -> void: pass
func step(_sim) -> void: pass
func can_finish(_sim) -> bool: return false

static func create(id: String, catalog: Dictionary) -> RefCounted:
	var path: String = catalog.get("controllers", {}).get(id, "")
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var script = load(path)
	if not script is Script or not script.can_instantiate(): return null
	var base = script.get_base_script()
	while base != null:
		if base.resource_path == "res://scripts/battle/dove_level_controller.gd": return script.new()
		base = base.get_base_script()
	return null
