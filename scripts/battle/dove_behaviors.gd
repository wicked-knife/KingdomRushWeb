extends RefCounted
## Explicit source IDs, including verified aliases, select existing implementations.
const Ranger = preload("res://scripts/battle/dove_ranger.gd")
const Elf = preload("res://scripts/battle/dove_elf.gd")
const Spider = preload("res://scripts/battle/dove_spider.gd")
const Arcane = preload("res://scripts/battle/dove_arcane.gd")
const Paladin = preload("res://scripts/battle/dove_paladin.gd")
const Ranged = preload("res://scripts/battle/dove_enemy_ranged.gd")
const Spawner = preload("res://scripts/battle/dove_spawner.gd")
const Juggernaut = preload("res://scripts/battle/dove_juggernaut.gd")
const Upgrades = preload("res://scripts/battle/dove_upgrades.gd")
const ROLES := ["ground", "healer", "spider", "soldier", "reinforcement", "archer", "mage", "engineer", "barrack", "mercenary", "ranger", "building", "arrow", "bolt", "bomb", "fireball", "arrow_missile", "thorn_aura", "spawner", "dps", "track_modifier", "heal_modifier", "thorn_modifier", "fire_control", "passive", "juggernaut", "arcane", "ray", "arcane_damage", "disintegrate", "teleport", "mod_aura", "enemy_missile", "enemy_bomb", "tower_decal", "instant_damage", "damage_aura"]
var catalog: Dictionary
var bindings: Dictionary

func _init(definition: Dictionary, content_catalog: Dictionary) -> void:
	catalog = content_catalog
	bindings = definition.get("behaviors", {})

static func canonical(source_id: String, content_catalog: Dictionary) -> String:
	return content_catalog.get("behavior_aliases", {}).get(source_id, source_id)

static func validate(definition: Dictionary, content_catalog: Dictionary) -> String:
	var tech_error := Upgrades.validate(definition)
	if not tech_error.is_empty(): return tech_error
	var content: String = definition.get("level", {}).get("root", "unknown")
	var templates: Dictionary = definition.get("templates", {})
	for name: String in definition.get("callbacks", {}):
		for event: String in definition.callbacks[name]:
			var callback: String = definition.callbacks[name][event]
			if callback not in content_catalog.get("callbacks", []): return "%s: %s.main_script.%s -> unsupported callback '%s'" % [content, name, event, callback]
	var callback_error := validate_callbacks(templates, content_catalog, content + ": templates")
	if not callback_error.is_empty(): return callback_error
	for name: String in definition.get("behaviors", {}):
		var source_id: String = definition.behaviors[name]
		var implementation: String = content_catalog.get("behaviors", {}).get(canonical(source_id, content_catalog), "")
		if not templates.has(name) or implementation not in ROLES: return "%s: %s -> unsupported Dove behavior '%s'" % [content, name, source_id]
	for name: String in templates:
		var template: Dictionary = templates[name]
		var actor: bool = template.has("enemy") or template.has("soldier") or template.has("bullet") or template.has("modifier") or template.has("aura") or template.has("spawner") or template.has("fireball_count") or (template.has("tower") and not str(template.tower.get("type", "")).begins_with("holder"))
		if not actor: continue
		var source_id: String = definition.get("behaviors", {}).get(name, "")
		var role: String = content_catalog.get("behaviors", {}).get(canonical(source_id, content_catalog), "")
		if source_id.is_empty() or role not in ROLES: return "%s: %s -> unsupported Dove behavior '%s'" % [content, name, source_id]
		if template.has("bullet") and canonical(template.get("behavior", ""), content_catalog) != canonical(source_id, content_catalog): return "%s: %s -> projectile behavior differs from source binding" % [content, name]
	for owner: String in definition.get("dependencies", {}):
		for child: String in definition.dependencies[owner]:
			if not templates.has(child): return "%s: %s -> missing template %s" % [content, owner, child]
	return ""

static func validate_callbacks(node: Variant, content_catalog: Dictionary, path: String) -> String:
	if node is Dictionary:
		for key: String in node:
			if key.begins_with("fn_") and node[key] not in content_catalog.get("callbacks", []): return "%s.%s -> unsupported callback '%s'" % [path, key, node[key]]
			var error := validate_callbacks(node[key], content_catalog, path + "." + key)
			if not error.is_empty(): return error
	elif node is Array:
		for index in node.size():
			var error := validate_callbacks(node[index], content_catalog, path + "[%d]" % index)
			if not error.is_empty(): return error
	return ""

func role(template: String) -> String:
	return catalog.behaviors.get(canonical(bindings.get(template, ""), catalog), "")

func projectile_role(template: Dictionary) -> String:
	return catalog.behaviors.get(canonical(template.get("behavior", ""), catalog), "")

func upgrade_tower(sim, old: Dictionary, upgraded: Dictionary) -> void:
	var behavior := role(upgraded.template)
	if behavior == "mercenary": Elf.initialize(upgraded)
	elif old.type == "barrack": sim._upgrade_garrison(old, upgraded)
	else: upgraded.attack_at = sim.tick + sim._tower_period(upgraded)
	if behavior == "ranger": Ranger.initialize(sim, upgraded)
	if behavior == "arcane": Arcane.initialize(sim, upgraded)
	var t: Dictionary = sim.templates[upgraded.template]
	if t.get("powers", {}).has("holystrike"):
		Paladin.initialize(upgraded); Paladin.upgraded(sim, upgraded)

func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	match role(tower.template):
		"ranger": Ranger.power_upgraded(sim, tower, power)
		"mercenary": Elf.power_upgraded(sim, tower)
		"arcane": Arcane.power_upgraded(sim, tower, power)
		"barrack":
			if tower.has("powers"): Paladin.upgraded(sim, tower)

func recruit_price(sim, tower: Dictionary, type: String) -> int:
	return Elf.price(sim, tower, type) if role(tower.get("template", "")) == "mercenary" else -1

func hire(sim, tower: Dictionary) -> void:
	if role(tower.template) == "mercenary": Elf.hire(sim, tower)

func tower_step(sim, tower: Dictionary) -> bool:
	if role(tower.template) == "arcane": Arcane.step(sim, tower); return true
	if role(tower.template) != "ranger": return false
	Ranger.step(sim, tower)
	return true

func soldier_inserted(sim, soldier: Dictionary, tower: Dictionary) -> void:
	sim.DamageFactors.inherit(sim, soldier, tower)
	if tower.get("powers", {}).has("holystrike"): Paladin.inherit(sim, soldier, tower)
	if role(tower.template) == "mercenary":
		Elf.inherit(soldier, tower); sim.event.emit("sound", {"id":"ElfTaunt"})

func soldier_step(sim, soldier: Dictionary, template: Dictionary) -> bool:
	if template.has("timed_actions") and soldier.has("powers"): return Paladin.step(sim, soldier, template)
	return role(soldier.template) == "soldier" and template.has("ranged") and Elf.ranged(sim, soldier, template)

func enemy_inserted(sim, enemy: Dictionary) -> void:
	if role(enemy.template) == "spider": Spider.initialize(sim, enemy)
	if role(enemy.template) == "juggernaut": Juggernaut.initialize(sim, enemy)

func enemy_step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	match role(enemy.template):
		"juggernaut": return Juggernaut.step(sim, enemy, template)
		"spider": Spider.lay(sim, enemy)
		"healer": return sim._healer_step(enemy, template)
	return Ranged.step(sim, enemy, template) if template.has("ranged") else false

func step_spawners(sim) -> void:
	Spider.step(sim)
	Spawner.step(sim)
	Arcane.step_auras(sim)
