extends RefCounted
## Read-only unit presentation shared by input picking and the HUD. Selection
## never takes ownership of a live entity and expires on death/removal.

static func pick(units: Array, templates: Dictionary, point: Vector2) -> int:
	var candidates := units.filter(func(u): return u.hp > 0 and not u.get("hidden", false) and templates[u.template].get("ui", {}).get("can_select", false))
	candidates.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for unit: Dictionary in candidates:
		var area: Dictionary = templates[unit.template].ui.click_rect
		if Rect2(unit.pos + Vector2(area.pos.x, area.pos.y), Vector2(area.size.x, area.size.y)).has_point(point): return unit.id
	return 0

static func snapshot(unit: Dictionary, templates: Dictionary, strings: Dictionary) -> Dictionary:
	if unit.is_empty() or unit.hp <= 0: return {}
	var t: Dictionary = templates[unit.template]
	var info: Dictionary = t.get("info", {})
	var name_key: String = str(info.get("i18n_key", str(unit.template).to_upper())) + "_NAME"
	var attack: Dictionary = t.get("melee", {}).get("attacks", [{}])[0]
	return {"id": unit.id, "name": unit.get("display_name", strings.get(name_key, name_key)), "portrait": unit.get("portrait", info.get("portrait", "")),
		"hp": unit.hp, "hp_max": unit.max_hp, "damage_min": attack.get("damage_min", 0), "damage_max": attack.get("damage_max", 0),
		"cooldown": attack.get("cooldown", 0), "armor": unit.get("armor", t.health.armor), "magic_armor": unit.get("magic_armor", t.health.magic_armor),
		"enemy": t.has("enemy"), "lives": t.get("enemy", {}).get("lives_cost", 0),
		"respawn": t.health.dead_lifetime, "speed": t.motion.max_speed}
