extends RefCounted
## Explicit source IDs, including verified aliases, select existing implementations.
const Ranger = preload("res://scripts/battle/dove_ranger.gd")
const Elf = preload("res://scripts/battle/dove_elf.gd")
const Spider = preload("res://scripts/battle/dove_spider.gd")
const ROLES := ["ground", "healer", "spider", "soldier", "reinforcement", "archer", "mage", "engineer", "barrack", "mercenary", "ranger", "building", "arrow", "bolt", "bomb", "fireball", "arrow_missile", "thorn_aura", "spawner", "dps", "track_modifier", "heal_modifier", "thorn_modifier", "fire_control"]
var catalog: Dictionary
var bindings: Dictionary

func _init(definition: Dictionary, content_catalog: Dictionary) -> void:
	catalog = content_catalog
	bindings = definition.get("behaviors", {})

static func canonical(source_id: String, content_catalog: Dictionary) -> String:
	return content_catalog.get("behavior_aliases", {}).get(source_id, source_id)

static func validate(definition: Dictionary, content_catalog: Dictionary) -> String:
	var content: String = definition.get("level", {}).get("root", "unknown")
	var templates: Dictionary = definition.get("templates", {})
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

func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	match role(tower.template):
		"ranger": Ranger.power_upgraded(sim, tower, power)
		"mercenary": Elf.power_upgraded(sim, tower)

func recruit_price(sim, tower: Dictionary, type: String) -> int:
	return Elf.price(sim, tower, type) if role(tower.get("template", "")) == "mercenary" else -1

func hire(sim, tower: Dictionary) -> void:
	if role(tower.template) == "mercenary": Elf.hire(sim, tower)

func tower_step(sim, tower: Dictionary) -> bool:
	if role(tower.template) != "ranger": return false
	Ranger.step(sim, tower)
	return true

func soldier_inserted(sim, soldier: Dictionary, tower: Dictionary) -> void:
	if role(tower.template) == "mercenary":
		Elf.inherit(soldier, tower); sim.event.emit("sound", {"id":"ElfTaunt"})

func soldier_step(sim, soldier: Dictionary, template: Dictionary) -> bool:
	return role(soldier.template) == "soldier" and template.has("ranged") and Elf.ranged(sim, soldier, template)

func enemy_inserted(sim, enemy: Dictionary) -> void:
	if role(enemy.template) == "spider": Spider.initialize(sim, enemy)

func enemy_step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	match role(enemy.template):
		"spider": Spider.lay(sim, enemy)
		"healer": return sim._healer_step(enemy, template)
	return false

func step_spawners(sim) -> void:
	Spider.step(sim)
