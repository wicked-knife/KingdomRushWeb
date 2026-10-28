extends RefCounted
## script_utils: additive increases and multiplicative reductions, per instance.

static func value(entity: Dictionary, template: Dictionary, received: bool = false) -> float:
	var key := "received_damage_factor" if received else "damage_factor"
	var component := "health" if received else ("tower" if template.has("tower") else "unit")
	return float(entity.get(key, template.get(component, {}).get("damage_factor", 1.0)))

static func change(entity: Dictionary, template: Dictionary, factor: float, received: bool = false, remove: bool = false) -> void:
	if is_equal_approx(factor, 1.0): return
	var key := "received_damage_factor" if received else "damage_factor"
	var state_key := key + "_state"
	if not entity.has(state_key): entity[state_key] = {"base": value(entity, template, received), "add": 0.0, "mul": 1.0}
	var state: Dictionary = entity[state_key]
	if factor >= 1.0: state.add += (factor - 1.0) * (-1.0 if remove else 1.0)
	else: state.mul = float(state.mul) / factor if remove else float(state.mul) * factor
	entity[key] = (float(state.base) + float(state.add)) * float(state.mul)

static func tower_buff(sim, tower: Dictionary, amount: float) -> void:
	tower.damage_factor = value(tower, sim.templates[tower.template]) + amount
	for soldier: Dictionary in sim.soldiers:
		if soldier.home == tower.id:
			change(soldier, sim.templates[soldier.template], 1.0 + absf(amount), false, amount < 0)

static func inherit(sim, soldier: Dictionary, tower: Dictionary) -> void:
	change(soldier, sim.templates[soldier.template], value(tower, sim.templates[tower.template]))
