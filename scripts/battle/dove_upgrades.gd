extends RefCounted
## Explicit default-tree adapters. Values and target classifications come from Dove.
const PATH := "res://data/upgrades/definition.json"
const IDS := ["archer_salvage", "archer_eagle_eye", "archer_piercing", "archer_far_shots", "archer_precision", "archer_el_bloodletting_shoot", "barrack_survival", "barrack_better_armor", "barrack_improved_deployment", "barrack_survival_2", "barrack_barbed_armor", "barrack_el_enchanted_armor", "mage_spell_reach", "mage_arcane_shatter", "mage_hermetic_study", "mage_empowered_magic", "mage_slow_curse", "mage_brilliance", "engineer_concentrated_fire", "engineer_range_finder", "engineer_field_logistics", "engineer_industrialization", "engineer_efficiency", "engineer_gnomish_tinkering", "rain_blazing_skies", "rain_scorched_earth", "rain_bigger_and_meaner", "rain_blazing_earth", "rain_cataclysm", "rain_armaggedon", "reinforcement_level_1", "reinforcement_level_2", "reinforcement_level_3", "reinforcement_level_4", "reinforcement_level_5", "reinforcement_level_6"]
static var _definition := {}
var effective := {}
var reinforcement := "re_farmer"
var brilliance_base := {}
var mage_count := -1
var fire_controls: Array = []
var auras: Array = []
var reflected: Array = []

static func definition() -> Dictionary:
	if _definition.is_empty(): _definition = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _definition

static func levels(value: Dictionary) -> Dictionary:
	var result := {}
	for key: String in definition().classes: result[key] = int(value.get(key, 0))
	return result

static func slot_error(slot: Dictionary) -> String:
	var list_id: Variant = slot.get("upgrade_list_id", "1")
	if not list_id is String: return "存档科技方案 ID 必须为字符串。"
	if list_id != "1": return "当前存档的科技方案暂未支持，原科技数据已保留。"
	var bought: Variant = slot.get("upgrades", {})
	if not bought is Dictionary: return "存档科技数据无效，原文件已保留。"
	for key: String in definition().classes:
		var value: Variant = bought.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value) or int(value) < 0 or int(value) > 6: return "存档科技等级无效，原数据已保留。"
	return ""

static func spent(bought: Dictionary) -> int:
	var total := 0
	for u: Dictionary in definition().techs.values():
		if int(bought.get(u.class, 0)) >= int(u.level): total += int(u.price)
	return total

static func validate(data: Dictionary) -> String:
	var tree := definition()
	if tree.get("source", {}).get("commit") != data.get("source", {}).get("commit"): return "technology source differs from current Dove catalog"
	if tree.get("techs", {}).size() != IDS.size() or tree.get("dependencies", {}).size() != IDS.size(): return "technology registry is incomplete"
	for id: String in tree.techs:
		if id not in IDS: return "unsupported technology " + id
		for row: Dictionary in tree.dependencies[id]:
			if data.templates.has(row.owner):
				var dependency_error := _validate_dependency(data,row.template,"technology %s -> %s" % [id,row.owner],{})
				if not dependency_error.is_empty():return dependency_error
	if data.has("battle_upgrades"):
		var error := slot_error({"upgrade_list_id":data.battle_upgrades.get("list_id", "1"), "upgrades":data.battle_upgrades.get("levels", {})})
		if not error.is_empty(): return error
	return ""

static func _validate_dependency(data: Dictionary, name: String, chain: String, visited: Dictionary) -> String:
	if visited.has(name):return ""
	visited[name]=true
	if not data.templates.has(name):return chain + " -> missing template " + name
	for child: String in data.get("dependencies",{}).get(name,[]):
		var error := _validate_dependency(data,child,chain+" -> "+name,visited)
		if not error.is_empty():return error
	return ""

func get_tech(id: String) -> Dictionary:
	var u: Dictionary = definition().techs.get(id, {})
	return u if not u.is_empty() and int(effective.get(u.class, 0)) >= int(u.level) else {}

func group(name: String, templates: Dictionary) -> Array:
	return definition().groups.get(name, []).filter(func(id): return templates.has(id))

func apply(data: Dictionary) -> void:
	effective = levels(data.get("battle_upgrades", {}).get("levels", {}))
	var mode := int(data.level.get("mode", 1))
	var overrides: Array = data.layout.get("level_mode_overrides", [])
	var limit := int(data.layout.get("max_upgrade_level", definition().max_level))
	if mode > 0 and mode <= overrides.size(): limit = int(overrides[mode - 1].get("max_upgrade_level", limit))
	for key: String in effective: effective[key] = mini(int(effective[key]), limit)
	reinforcement = "re_farmer"; brilliance_base.clear(); mage_count = -1
	fire_controls.clear(); auras.clear(); reflected.clear()
	var templates: Dictionary = data.templates
	var ordered: Array = definition().techs.keys()
	ordered.sort_custom(func(a, b):
		var ua: Dictionary = definition().techs[a]; var ub: Dictionary = definition().techs[b]
		return a < b if ua.level == ub.level else ua.level < ub.level)
	for id: String in ordered:
		var u := get_tech(id)
		if u.is_empty(): continue
		assert(id in IDS, "Unsupported technology: " + id)
		match id:
			"archer_salvage": _scale(templates, "archer_towers", ["tower", "price"], u.cost_factor, "ceil")
			"archer_eagle_eye", "archer_far_shots": _scale(templates, "archer_towers", ["attacks", "range"], u.range_factor)
			"archer_piercing":
				for name: String in group("arrows", templates): templates[name].bullet.reduce_armor = float(templates[name].bullet.get("reduce_armor", 0)) + float(u.reduce_armor_factor)
			"archer_el_bloodletting_shoot": _mods(templates, "arrows", ["mod_blood_elves"], false)
			"barrack_survival", "barrack_survival_2": _scale(templates, "soldiers", ["health", "hp_max"], u.health_factor)
			"barrack_better_armor":
				for name: String in group("soldiers", templates): templates[name].health.armor += float(u.armor_increase)
			"barrack_improved_deployment":
				_scale(templates, "soldiers", ["health", "dead_lifetime"], u.cooldown_factor)
				_scale(templates, "towers_with_barrack", ["barrack", "rally_range"], u.rally_range_factor)
			"barrack_barbed_armor", "barrack_el_enchanted_armor":
				for t: Dictionary in templates.values():
					if not t.has("soldier") or not t.has("health"): continue
					if id == "barrack_barbed_armor": t.health.spiked_armor = float(t.health.get("spiked_armor", 0)) + float(u.spiked_armor_factor)
					elif not t.has("hero"):
						t.health.damage_factor = float(u.factor); t.health.magic_armor += float(u.magic_armor_inc)
			"mage_spell_reach": _scale(templates, "mage_towers", ["attacks", "range"], u.range_factor)
			"mage_hermetic_study": _scale(templates, "mage_towers", ["tower", "price"], u.cost_factor, "ceil")
			"mage_arcane_shatter":
				for name: String in group("bolts", templates):
					var b: Dictionary = templates[name].bullet
					_add_mods(b, [u.mod_normal if float(b.get("damage_max", 0)) >= 50 or b.get("template_name", "") == "ray_arcane" else u.mod_little], true)
			"mage_empowered_magic":
				_damage(templates, "mage_tower_bolts", u.damage_factor)
				if templates.has("mod_ray_arcane"): _multiply_damage(templates.mod_ray_arcane.dps, u.damage_factor)
			"mage_slow_curse": _mods(templates, "bolts", [u.mod], true)
			"engineer_concentrated_fire": _damage(templates, "engineer_bombs", u.damage_factor)
			"engineer_range_finder": _scale(templates, "engineer_towers", ["attacks", "range"], u.range_factor)
			"engineer_field_logistics": _scale(templates, "engineer_towers", ["tower", "price"], u.cost_factor, "floor")
			"engineer_industrialization":
				for name: String in group("engineer_advanced_tower", templates):
					for power: Dictionary in templates[name].get("powers", {}).values():
						for key in ["price_base", "price_inc"]:
							if power.has(key): power[key] = floorf(float(power[key]) * float(u.cost_factor))
			"rain_blazing_skies", "rain_bigger_and_meaner", "rain_cataclysm", "rain_armaggedon":
				var control: Dictionary = templates.power_fireball_control
				control.fireball_count += int(u.get("fireball_count_increase", 0))
				control.cataclysm_count = int(control.get("cataclysm_count", 0)) + int(u.get("cataclysm_count_increase", 0)) + (int(u.fireball_count_increase) if id == "rain_armaggedon" else 0)
				control.cooldown -= float(u.get("cooldown_reduction", 0))
				var b: Dictionary = templates.power_fireball.bullet
				b.damage_min += float(u.get("damage_increase", 0)); b.damage_max += float(u.get("damage_increase", 0))
				b.damage_radius *= float(u.get("range_factor", 1))
			"rain_scorched_earth": templates.power_fireball.scorch_earth = true
			"rain_blazing_earth":
				templates.power_fireball_control.cooldown -= float(u.cooldown_reduction)
				for name in ["power_scorched_earth", "power_scorched_water"]:
					var aura: Dictionary = templates[name].aura
					aura.damage_min += float(u.damage_min_increase); aura.damage_max += float(u.damage_max_increase); aura.duration += float(u.duration_increase)
			"reinforcement_level_1", "reinforcement_level_2", "reinforcement_level_3", "reinforcement_level_4", "reinforcement_level_5": reinforcement = u.template_name
			"reinforcement_level_6":
				templates.power_reinforcements_control.cooldown -= float(u.cooldown_dec)
				templates.power_reinforcements_control.duration += float(u.duration_inc)

func _scale(templates: Dictionary, category: String, path: Array, factor: float, rounding: String = "") -> void:
	for name: String in group(category, templates):
		var owner: Dictionary = templates[name]
		for key: String in path.slice(0, -1): owner = owner[key]
		var key: String = path[-1]
		var value := float(owner[key]) * factor
		owner[key] = ceilf(value) if rounding == "ceil" else (floorf(value) if rounding == "floor" else value)

func _multiply_damage(owner: Dictionary, factor: float) -> void:
	owner.damage_min *= factor; owner.damage_max *= factor

func _damage(templates: Dictionary, category: String, factor: float) -> void:
	for name: String in group(category, templates): _multiply_damage(templates[name].bullet, factor)

func _mods(templates: Dictionary, category: String, mods: Array, prepend: bool) -> void:
	for name: String in group(category, templates): _add_mods(templates[name].bullet, mods, prepend)

func _add_mods(b: Dictionary, mods: Array, prepend: bool) -> void:
	var old: Array = b.get("mods", [b.mod] if b.has("mod") else []).duplicate()
	b.mods = mods + old if prepend else old + mods
	b.erase("mod")

func refresh_mages(sim) -> void:
	var u := get_tech("mage_brilliance")
	if u.is_empty(): return
	var count := 0
	for tower: Dictionary in sim.towers:
		if tower.ready <= sim.tick and tower.template in definition().groups.mage_towers: count += 1
	if count == mage_count: return
	if count == 0 and mage_count == -1: mage_count = 0; return
	mage_count = count
	var factor: float = u.damage_factors[clampi(count, 1, u.damage_factors.size()) - 1]
	for name: String in group("mage_tower_bolts", sim.templates): _brilliance(name, sim.templates[name].bullet, factor)
	if sim.templates.has("mod_ray_arcane"): _brilliance("mod_ray_arcane", sim.templates.mod_ray_arcane.dps, factor)

func _brilliance(name: String, owner: Dictionary, factor: float) -> void:
	if not brilliance_base.has(name): brilliance_base[name] = [owner.damage_min, owner.damage_max]
	owner.damage_min = float(brilliance_base[name][0]) * factor; owner.damage_max = float(brilliance_base[name][1]) * factor

func cast_fire(sim, point: Vector2) -> void:
	var control: Dictionary = sim.templates.power_fireball_control
	var cast := {"pos": point, "index": 0, "next": sim.tick, "count": maxi(int(control.fireball_count), int(control.get("cataclysm_count", 0)))}
	fire_controls.append(cast)
	_fire_burst(sim, cast)

func _fire_burst(sim, cast: Dictionary) -> void:
	var control: Dictionary = sim.templates.power_fireball_control
	cast.index += 1; cast.next = sim.tick + sim.frames(0.33)
	if cast.index <= int(control.fireball_count):
		for attempt in range(5):
			var spread := int(control.max_spread)
			var point: Vector2 = cast.pos + Vector2(sim.rng.randi_range(-spread, spread), sim.rng.randi_range(-spread, spread))
			if (sim._terrain_flags(point + Vector2(0, 16)) & 4) != 0 or (sim._terrain_flags(point - Vector2(0, 16)) & 4) != 0: continue
			_fireball(sim, point); break
	if cast.index <= int(control.get("cataclysm_count", 0)):
		var enemies: Array = sim.enemies.filter(func(e): return e.hp > 0 and (int(e.get("vis", sim.templates[e.template].vis).bans) & 2) == 0)
		var point := Vector2.INF
		if not get_tech("rain_armaggedon").is_empty() and not enemies.is_empty():
			var enemy: Dictionary = enemies[sim.rng.randi_range(0, enemies.size() - 1)]
			var speed: float = sim.templates[enemy.template].motion.max_speed * sim.data.rules.enemy_speed_factor * sim.modifiers.speed(enemy.id, sim)
			var wait: float = 0.0 if not enemy.blockers.is_empty() or enemy.get("stun_count", 0) > 0 or enemy.last_dir == Vector2.ZERO else (768.0 - enemy.pos.y) / (float(enemy.last_dir.y) * 30.0 + 390.0)
			var route: Array = sim.data.paths.paths[enemy.path][enemy.subpath]
			var advance := ceili((wait * speed + enemy.pos.distance_to(sim.vec(route[enemy.node]))) / 6.0)
			point = sim.vec(route[clampi(int(enemy.node) + advance, 0, route.size() - 1)])
		else:
			point = random_fire_position(sim)
		if point.is_finite(): _fireball(sim, point)

func random_fire_position(sim) -> Vector2:
	# path_db:get_random_position(10, LAND | WATER): one active path/subpath,
	# up to five valid-node attempts, with ten valid nodes on either side.
	var active: Array = []
	for index in sim.data.paths.paths.size():
		if sim.data.paths.active[index]: active.append(index)
	if active.is_empty(): return Vector2.INF
	var path: int = active[sim.rng.randi_range(0, active.size() - 1)]
	var subpath: int = sim.rng.randi_range(0, 2)
	var valid: Array = []
	for index in sim.data.paths.paths[path][0].size():
		if sim._path_node_valid(path, index, 4294967295): valid.append(index)
	if valid.is_empty(): return Vector2.INF
	for attempt in range(5):
		var node: int = valid[sim.rng.randi_range(0, valid.size() - 1)]
		var point: Vector2 = sim.vec(sim.data.paths.paths[path][subpath][node])
		if sim._path_node_valid(path, node - 10, 4294967295) and sim._path_node_valid(path, node + 10, 4294967295) and (sim._terrain_flags(point) & 255 & ~3) == 0: return point
	return Vector2.INF

func _fireball(sim, point: Vector2) -> void:
	sim._projectile("power_fireball", 0, Vector2(point.x, 768), point, maxf(1.0 / 30.0, (768.0 - point.y) / 390.0))

func scorched(sim, point: Vector2) -> void:
	if not sim.templates.power_fireball.get("scorch_earth", false): return
	var name := "power_scorched_water" if (sim._terrain_flags(point) & 2) != 0 else "power_scorched_earth"
	var t: Dictionary = sim.templates[name]
	# Queued source entities begin their coroutine on the following update.
	var first: int = sim.tick + 1
	auras.append({"template": name, "pos": point, "at": sim.tick, "born_at": first, "next": maxi(first, sim.frames(t.aura.cycle_time)), "expires": first + roundi(float(t.aura.duration) * 30), "duration": float(t.aura.duration)})

func step(sim) -> void:
	var queued := reflected.duplicate(); reflected.clear()
	for hit: Dictionary in queued:
		var target: Dictionary = sim.unit_by_id(hit.target)
		if not target.is_empty() and target.hp > 0: sim.damage(target, hit.amount, 1, hit.source)
	for cast: Dictionary in fire_controls.duplicate():
		if sim.tick >= int(cast.next):
			if int(cast.index) >= int(cast.count): fire_controls.erase(cast)
			else: _fire_burst(sim, cast)
	for aura: Dictionary in auras.duplicate():
		if sim.tick >= int(aura.expires): auras.erase(aura); continue
		if sim.tick < int(aura.next): continue
		var rule: Dictionary = sim.templates[aura.template].aura
		aura.next = sim.tick + sim.frames(rule.cycle_time)
		for enemy: Dictionary in sim.enemies:
			if enemy.hp > 0 and sim.modifiers.flags_match(sim, enemy, rule) and sim.distance(aura.pos, enemy.pos) <= float(rule.radius):
				sim.damage(enemy, sim.rng.randi_range(int(rule.damage_min), int(rule.damage_max)), int(rule.damage_type))

func reinforcement_step(sim, soldier: Dictionary, t: Dictionary) -> bool:
	if not t.has("reinforcement") or not t.has("ranged"): return false
	if soldier.pending.get("reinforcement_ranged", false):
		if sim.tick < int(soldier.pending.at): return true
		var target: Dictionary = sim.unit_by_id(soldier.pending.target)
		var attack: Dictionary = t.ranged.attacks[0]
		if not target.is_empty() and target.hp > 0:
			var offset: Vector2 = sim.vec(attack.bullet_start_offset[0]); offset.x *= -1 if soldier.flip else 1
			var bullet: Dictionary = sim.templates[attack.bullet].bullet
			var aim: Vector2 = target.pos + sim.vec(sim.templates[target.template].unit.hit_offset)
			if bullet.get("predict_target_pos", false) and target.blocker == 0: aim += target.last_dir * 30.0 * float(bullet.flight_time)
			sim._projectile(attack.bullet, target.id, soldier.pos + offset, aim, float(bullet.flight_time), soldier)
		soldier.pending = {}; return true
	if sim.tick < int(soldier.ranged_until): return true
	if not soldier.pending.is_empty() or soldier.target != 0 or sim.tick < int(soldier.ranged_at): return false
	# Melee has priority, including acquisition of a free blocker slot this frame.
	if not sim._soldier_target(soldier).is_empty(): return false
	var attack: Dictionary = t.ranged.attacks[0]
	var target := {}
	var remaining := INF
	for enemy: Dictionary in sim.enemies:
		var distance: float = sim.distance(soldier.pos,enemy.pos)
		if enemy.hp<=0 or not sim.modifiers.flags_match(sim,enemy,attack) or distance<float(attack.min_range) or distance>float(attack.max_range):continue
		var nodes_left: float = sim.data.paths.paths[enemy.path][enemy.subpath].size()-enemy.progress
		if nodes_left<remaining:target=enemy;remaining=nodes_left
	if target.is_empty(): return false
	soldier.pending = {"reinforcement_ranged": true, "target": target.id, "at": sim.tick + sim.frames(attack.shoot_time)}
	soldier.ranged_at = sim.tick + sim.frames(attack.cooldown)
	soldier.ranged_until = sim.tick + sim.SpriteAnimation.duration(sim.animations, "%s_%d_ranged_attack" % [soldier.template, soldier.variant])
	soldier.flip = target.pos.x < soldier.pos.x; sim._state(soldier, "ranged_attack", true)
	return true
