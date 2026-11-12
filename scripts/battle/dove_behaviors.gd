extends RefCounted
## Explicit source IDs, including verified aliases, select existing implementations.
const Necromancer = preload("res://scripts/battle/dove_necromancer.gd")
const Tesla = preload("res://scripts/battle/dove_tesla.gd")
const Wasteland = preload("res://scripts/battle/dove_wasteland.gd")
const Sorcerer = preload("res://scripts/battle/dove_sorcerer.gd")
const Sunray = preload("res://scripts/battle/dove_sunray.gd")
const Jt = preload("res://scripts/battle/dove_jt.gd")
const Veznan = preload("res://scripts/battle/dove_veznan.gd")
const Ranger = preload("res://scripts/battle/dove_ranger.gd")
const Elf = preload("res://scripts/battle/dove_elf.gd")
const Spider = preload("res://scripts/battle/dove_spider.gd")
const Arcane = preload("res://scripts/battle/dove_arcane.gd")
const Paladin = preload("res://scripts/battle/dove_paladin.gd")
const Ranged = preload("res://scripts/battle/dove_enemy_ranged.gd")
const Spawner = preload("res://scripts/battle/dove_spawner.gd")
const Juggernaut = preload("res://scripts/battle/dove_juggernaut.gd")
const Upgrades = preload("res://scripts/battle/dove_upgrades.gd")
const Musketeer = preload("res://scripts/battle/dove_musketeer.gd")
const Bfg = preload("res://scripts/battle/dove_bfg.gd")
const Missile = preload("res://scripts/battle/dove_missile.gd")
const AdvancedBarrack = preload("res://scripts/battle/dove_advanced_barrack.gd")
const Sasquash = preload("res://scripts/battle/dove_sasquash.gd")
const Chieftain = preload("res://scripts/battle/dove_chieftain.gd")
const EnemyMelee = preload("res://scripts/battle/dove_enemy_melee.gd")
const ROLES := ["ground", "healer", "spider", "soldier", "reinforcement", "archer", "mage", "engineer", "barrack", "mercenary", "ranger", "building", "arrow", "bolt", "bomb", "fireball", "arrow_missile", "thorn_aura", "spawner", "dps", "track_modifier", "heal_modifier", "thorn_modifier", "fire_control", "passive", "juggernaut", "arcane", "ray", "arcane_damage", "disintegrate", "teleport", "mod_aura", "enemy_missile", "enemy_bomb", "tower_decal", "instant_damage", "damage_aura"]
var catalog: Dictionary
var bindings: Dictionary

func _init(definition: Dictionary, content_catalog: Dictionary) -> void:
	catalog = content_catalog
	bindings = definition.get("behaviors", {})

static func canonical(source_id: String, content_catalog: Dictionary) -> String:
	return content_catalog.get("behavior_aliases", {}).get(source_id, source_id)

static func validate(definition: Dictionary, content_catalog: Dictionary) -> String:
	var ui_error := preload("res://scripts/battle/dove_power_preview.gd").validate(definition)
	if not ui_error.is_empty(): return ui_error
	var tech_error := Upgrades.validate(definition)
	if not tech_error.is_empty(): return tech_error
	var content: String = definition.get("level", {}).get("root", "unknown")
	var templates: Dictionary = definition.get("templates", {})
	for owner:String in content_catalog.get("runtime_fields",{}):
		if not templates.has(owner):continue
		for row:Dictionary in content_catalog.runtime_fields[owner]:
			var value:Variant=templates[owner]
			for key:Variant in row.path:
				if value is Dictionary:value=value.get(key,null)
				elif value is Array and (key is int or key is float) and int(key)<value.size():value=value[int(key)]
				else:value=null
			if value!=row.value:return "%s: %s -> missing required runtime field %s"%[content,owner,str(row.path)]
	for owner: String in content_catalog.get("runtime_callbacks", {}):
		if not templates.has(owner): continue
		for callback_event: String in content_catalog.runtime_callbacks[owner]:
			var required_callback: String=content_catalog.runtime_callbacks[owner][callback_event]
			if definition.get("callbacks",{}).get(owner,{}).get(callback_event,"")!=required_callback:
				return "%s: %s.%s -> missing required runtime callback %s"%[content,owner,callback_event,required_callback]
	for owner: String in content_catalog.get("runtime_dependencies", {}):
		if not templates.has(owner): continue
		for child: String in content_catalog.runtime_dependencies[owner]:
			if not templates.has(child): return "%s: %s -> missing runtime dependency %s" % [content,owner,child]
	for entity: Dictionary in definition.get("layout", {}).get("entities_list", []):
		var required: bool = entity.has("tower.holder_id") or str(entity.template).begins_with("tunnel") or str(entity.template).begins_with("decal_tunnel_light") or str(entity.template).begins_with("ps_snow")
		if required and not templates.has(entity.template): return "%s: layout -> missing template %s" % [content,entity.template]
	for name: String in definition.get("callbacks", {}):
		for event: String in definition.callbacks[name]:
			var callback: String = definition.callbacks[name][event]
			if callback not in content_catalog.get("callbacks", []): return "%s: %s.main_script.%s -> unsupported callback '%s'" % [content, name, event, callback]
	var callback_error := validate_callbacks(templates, content_catalog, content + ": templates")
	if not callback_error.is_empty(): return callback_error
	for name: String in definition.get("behaviors", {}):
		var source_id: String = definition.behaviors[name]
		var implementation: String = content_catalog.get("behaviors", {}).get(canonical(source_id, content_catalog), "")
		if not templates.has(name) or not supported(implementation): return "%s: %s -> unsupported Dove behavior '%s'" % [content, name, source_id]
	for name: String in templates:
		var template: Dictionary = templates[name]
		var actor: bool = (template.has("entity") and template.has("cooldown_after")) or template.has("graveyard") or template.has("enemy") or template.has("soldier") or template.has("bullet") or template.has("modifier") or template.has("aura") or template.has("spawner") or template.has("fireball_count") or (template.has("tower") and not str(template.tower.get("type", "")).begins_with("holder"))
		if not actor: continue
		var source_id: String = definition.get("behaviors", {}).get(name, "")
		var role: String = content_catalog.get("behaviors", {}).get(canonical(source_id, content_catalog), "")
		if source_id.is_empty() or not supported(role): return "%s: %s -> unsupported Dove behavior '%s'" % [content, name, source_id]
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

static func supported(value: String) -> bool:
	if value in ["veznan","veznan_block","veznan_portal","veznan_soul","veznan_souls"]:return true
	return value in ROLES or value in ["enemy_bolt","necromancer","layout_spawner","tesla","tesla_ray","tesla_aura","graveyard","demon_mage","skeleton_aura","musketeer","shotgun","tunnel","unit_regen","hero_malik","fissure_aura","stun_modifier","bfg","missile","cluster","sasquash_holder","chieftain","sorcerer","sunray","jt","jt_spawn","jt_freeze","sheep","polymorph","armor_buff","speed_buff"]

func projectile_role(template: Dictionary) -> String:
	return catalog.behaviors.get(canonical(template.get("behavior", ""), catalog), "")

func upgrade_tower(sim, old: Dictionary, upgraded: Dictionary) -> void:
	var behavior := role(upgraded.template)
	if upgraded.template == "tower_barbarian": AdvancedBarrack.initialize(sim,upgraded)
	if behavior == "mercenary": Elf.initialize(upgraded)
	elif old.type == "barrack": sim._upgrade_garrison(old, upgraded)
	else: upgraded.attack_at = sim.tick + sim._tower_period(upgraded)
	if behavior == "ranger": Ranger.initialize(sim, upgraded)
	if behavior == "arcane": Arcane.initialize(sim, upgraded)
	if behavior == "musketeer": Musketeer.initialize(sim, upgraded)
	if behavior == "bfg": Bfg.initialize(sim,upgraded)
	if behavior == "tesla": Tesla.initialize(sim,upgraded)
	if behavior == "sorcerer": Sorcerer.initialize(sim,upgraded)
	if behavior == "sunray": Sunray.initialize(sim,upgraded)
	var t: Dictionary = sim.templates[upgraded.template]
	if t.get("powers", {}).has("holystrike"):
		Paladin.initialize(upgraded); Paladin.upgraded(sim, upgraded)

func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	match role(tower.template):
		"sorcerer": Sorcerer.upgraded(sim,tower,power)
		"sunray": Sunray.upgraded(sim,tower,power)
		"ranger": Ranger.power_upgraded(sim, tower, power)
		"mercenary": Elf.power_upgraded(sim, tower)
		"arcane": Arcane.power_upgraded(sim, tower, power)
		"musketeer": Musketeer.power_upgraded(sim, tower, power)
		"bfg": Bfg.power_upgraded(sim,tower,power)
		"barrack":
			if tower.template == "tower_barbarian": AdvancedBarrack.upgraded(sim,tower,power)
			elif tower.has("powers"): Paladin.upgraded(sim, tower)

func recruit_price(sim, tower: Dictionary, type: String) -> int:
	if tower.get("template","") == "tower_sasquash": return Sasquash.price(sim,tower,type)
	return Elf.price(sim, tower, type) if role(tower.get("template", "")) == "mercenary" else -1

func hire(sim, tower: Dictionary) -> void:
	if tower.template == "tower_sasquash": Sasquash.hire(sim,tower)
	elif role(tower.template) == "mercenary": Elf.hire(sim, tower)

func tower_step(sim, tower: Dictionary) -> bool:
	if role(tower.template)=="tesla": Tesla.step(sim,tower);return true
	if role(tower.template)=="sorcerer": Sorcerer.step(sim,tower);return true
	if role(tower.template)=="sunray": Sunray.step(sim,tower);return true
	if role(tower.template) == "sasquash_holder": Sasquash.frozen_step(sim,tower); return true
	if tower.template == "tower_sasquash": Sasquash.step(sim,tower); return true
	if role(tower.template) == "bfg": Bfg.step(sim,tower); return true
	if role(tower.template) == "musketeer": Musketeer.step(sim,tower); return true
	if role(tower.template) == "arcane": Arcane.step(sim, tower); return true
	if role(tower.template) != "ranger": return false
	Ranger.step(sim, tower)
	return true

func soldier_inserted(sim, soldier: Dictionary, tower: Dictionary) -> void:
	sim.DamageFactors.inherit(sim, soldier, tower)
	if tower.get("powers", {}).has("holystrike"): Paladin.inherit(sim, soldier, tower)
	if role(tower.template) == "mercenary" and tower.template != "tower_sasquash":
		Elf.inherit(soldier, tower); sim.event.emit("sound", {"id":"ElfTaunt"})

func soldier_step(sim, soldier: Dictionary, template: Dictionary) -> bool:
	if template.has("timed_actions") and soldier.has("powers"): return Paladin.step(sim, soldier, template)
	return role(soldier.template) == "soldier" and template.has("ranged") and Elf.ranged(sim, soldier, template)

func enemy_inserted(sim, enemy: Dictionary) -> void:
	if role(enemy.template)=="veznan":Veznan.initialize(sim,enemy)
	sim.snow.enemy_inserted(sim,enemy)
	if role(enemy.template)=="necromancer":Necromancer.initialize(sim,enemy)
	if enemy.template=="enemy_lava_elemental":enemy.mixed_melee_job={};enemy.source_corpse=true
	Wasteland.inserted(sim,enemy)
	if enemy.template in ["eb_jt","enemy_rocketeer","enemy_slayer","enemy_sheep_ground","enemy_sheep_fly"]:enemy.source_corpse=true
	if role(enemy.template)=="jt": Jt.initialize(sim,enemy)
	if role(enemy.template)=="sheep": enemy.sheep_clicks=0;enemy.click_pending=false
	if enemy.template in ["enemy_yeti","enemy_troll_axe_thrower"]: enemy.mixed_melee_job = {}
	if role(enemy.template) == "spider": Spider.initialize(sim, enemy)
	if role(enemy.template) == "juggernaut": Juggernaut.initialize(sim, enemy)
	if role(enemy.template) == "chieftain": Chieftain.initialize(sim,enemy)

func enemy_step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	if enemy.has("veznan"):return sim.veznan.step_enemy(sim,enemy,template)
	if Wasteland.enemy_step(sim,enemy,template):return true
	if enemy.has("necromancer"):return Necromancer.step(sim,enemy,template)
	if enemy.has("jt"):return Jt.step(sim,enemy,template)
	if role(enemy.template)=="sheep" and Sorcerer.sheep_step(sim,enemy):return true
	if enemy.has("mixed_melee_job"): return EnemyMelee.step(sim,enemy,template)
	match role(enemy.template):
		"juggernaut": return Juggernaut.step(sim, enemy, template)
		"spider": Spider.lay(sim, enemy)
		"healer": return sim._healer_step(enemy, template)
		"chieftain": return Chieftain.step(sim,enemy,template)
	return Ranged.step(sim, enemy, template) if template.has("ranged") else false

func step_spawners(sim) -> void:
	Jt.spawn_step(sim)
	Spider.step(sim)
	Spawner.step(sim)
	Spawner.step_layout(sim)
	Arcane.step_auras(sim)
	Tesla.auras(sim)
