extends RefCounted
## Frozen visibility bit tests. Candidate ordering remains owned by each attack.
static func matches(sim, unit: Dictionary, rule: Dictionary, damage: bool = false) -> bool:
	if unit.has("path") and not sim._path_node_valid(int(unit.path), int(unit.node), 0): return false
	var vis: Dictionary = unit.get("vis", sim.templates[unit.template].get("vis", {}))
	var flags = int(rule.get("damage_flags" if damage else "vis_flags", 0))
	var bans = int(rule.get("damage_bans" if damage else "vis_bans", 0))
	return unit.hp > 0 and (int(vis.get("bans", 0)) & flags) == 0 and (int(vis.get("flags", 0)) & bans) == 0

static func soldiers(sim, point: Vector2, rule: Dictionary) -> Array:
	var found: Array = []
	for s: Dictionary in sim.soldiers:
		var distance: float = sim.distance(point, s.pos)
		if matches(sim, s, rule) and distance >= float(rule.get("min_range", 0)) and distance <= float(rule.get("max_range", 1e99)): found.append(s)
	found.sort_custom(func(a, b): return point.distance_squared_to(a.pos) < point.distance_squared_to(b.pos))
	return found
