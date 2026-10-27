extends RefCounted
## Deterministic 30 Hz campaign state. All player actions go through command().
signal event(kind: String, payload: Dictionary)

const STEP := 1.0 / 30.0
const TYPES := ["archer", "barrack", "mage", "engineer"]
const UPGRADES := {"tower_archer_1": "tower_archer_2", "tower_barrack_1": "tower_barrack_2", "tower_mage_1": "tower_mage_2", "tower_engineer_1": "tower_engineer_2",
	"tower_archer_2": "tower_archer_3", "tower_barrack_2": "tower_barrack_3", "tower_mage_2": "tower_mage_3", "tower_engineer_2": "tower_engineer_3"}
const SpriteAnimation = preload("res://scripts/battle/dove_animation.gd")
const Projectile = preload("res://scripts/battle/dove_projectile.gd")
const Ranger = preload("res://scripts/battle/dove_ranger.gd")
const Modifiers = preload("res://scripts/battle/dove_modifiers.gd")
var modifiers := Modifiers.new()
# Frozen Dove path_db:path_width and game_gui POWER_1 / POWER_2 rules.
const PATH_WIDTH := 42.0
const FIRE_PATH_WIDTH_FACTOR := 1.4285714285714286
const RALLY_TERRAINS := 1 | 2048 # LAND | ICE; cell_is_only excludes all other bits.
const FIRE_EXCLUDED_TERRAINS := 4 | 1024 # CLIFF | FAERIE.
const NF_RALLY := 1
const NF_POWER_1 := 128
var data: Dictionary
var templates: Dictionary
var animations: Dictionary
var towers: Array = []
var enemies: Array = []
var soldiers: Array = []
var projectiles: Array = []
var effects: Array = []
var decals: Array = []
var spawn_log: Array = []
var spawn_queue: Array = []
var notices: Array = []
var unlocked := {"reinforcements": false, "fire": false}
var cooldowns := {"reinforcements": 0, "fire": 0}
var rng := RandomNumberGenerator.new()
var tick := 0
var gold := 270
var lives := 20
var wave := 0
var next_wave_tick := -1
var wave_end_tick := -1
var result := ""
var paused := false
var speed := 1
var accumulator := 0.0
var next_id := 1
var kills := 0
var leaks := 0
var developer_enabled := false
var developer_used := false
var seen_enemies := {}
var alerts: Array[String] = []
var enemy_cells := {}
var cell_for_enemy := {}
var spatial_tick := -1

func _init(definition: Dictionary = {}, seed_value: int = 1, allow_developer: bool = false) -> void:
	developer_enabled = allow_developer and OS.is_debug_build()
	data = definition.duplicate(true) if not definition.is_empty() else JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/definition.json"))
	templates = data.templates
	animations = JSON.parse_string(FileAccess.get_file_as_string(data.get("level", {}).get("root", "res://data/level01/") + "animations.json")).animations
	reset(seed_value)

func reset(seed_value: int = 1) -> void:
	modifiers.clear(self)
	rng.seed = seed_value
	tick = 0; gold = int(data.waves.cash); lives = int(data.waves.lives)
	wave = 0; next_wave_tick = -1; wave_end_tick = -1; result = ""
	paused = false; speed = 1; accumulator = 0; next_id = 1; kills = 0; leaks = 0
	developer_used = false
	towers.clear(); enemies.clear(); soldiers.clear(); projectiles.clear(); effects.clear(); decals.clear(); spawn_queue.clear(); spawn_log.clear()
	var first: bool = int(data.get("level", {}).get("id", 1)) == 1
	notices = ["TUTORIAL_1", "TUTORIAL_2", "TUTORIAL_3"] if first else []
	# Dove enables the non-tutorial powers from the first next-wave-sent event,
	# not while the battlefield is still in its pre-wave setup state.
	unlocked = {"reinforcements": false, "fire": false}
	seen_enemies.clear(); alerts.clear()
	for id: String in data.get("seen_notifications", []): seen_enemies[id] = true
	enemy_cells.clear(); cell_for_enemy.clear(); spatial_tick = -1
	cooldowns = {"reinforcements": 0, "fire": 0}
	if not first:
		for entry: Dictionary in data.waves.groups[0].waves:
			if entry.has("notification") and data.ui.notifications.has(entry.notification): notices.append(entry.notification)
	for index in range(data.layout.entities_list.size()):
		var e: Dictionary = data.layout.entities_list[index]
		if str(e.template).begins_with("tower_holder"):
			towers.append(_holder({"id": str(e["tower.holder_id"]), "pos": vec(e.pos), "rally": vec(e["tower.default_rally_pos"]), "holder": e.template}))
		elif templates.has(e.template) and (templates[e.template].has("delayed_play") or templates[e.template].template_name == "decal_fish"):
			var fish: bool = templates[e.template].template_name == "decal_fish"
			var d: Dictionary = templates[e.template].get("delayed_play", {"min_delay": 5, "max_delay": 10})
			decals.append({"id": index, "template": e.template, "pos": vec(e.pos), "clicks": 0, "clicked_at": -1000, "removed": false,
				"state": d.get("idle_animation", ""), "hidden": not d.has("idle_animation"), "fish": fish, "state_at": 0, "next_play": frames(rng.randf_range(d.min_delay, d.max_delay)),
				"flip": rng.randf() < float(d.get("flip_chance", 0)), "alternate": rng.randf() < float(d.get("required_clicks_fx_alt_chance", 0))})

static func vec(v: Dictionary) -> Vector2:
	return Vector2(v.x, v.y)

static func frames(seconds: float) -> int:
	return maxi(1, roundi(seconds * 30.0))

static func distance(a: Vector2, b: Vector2) -> float:
	var delta := a - b
	return Vector2(delta.x, delta.y / 0.7).length()

func tower_by_id(id: String) -> Dictionary:
	for tower: Dictionary in towers:
		if tower.id == id: return tower
	return {}

func unit_by_id(id: int) -> Dictionary:
	for u: Dictionary in enemies + soldiers:
		if u.id == id: return u
	return {}

func _holder(tower: Dictionary) -> Dictionary:
	return {"id": tower.id, "pos": tower.pos, "rally": tower.rally, "holder": tower.holder,
		"template": tower.holder, "spent": 0, "type": "", "ready": 0, "attack_at": 0,
		"shot_at": -1000, "shot_up": false, "pending": {}, "slots": [0, 0, 0]}

func tower_template(tower: Dictionary) -> Dictionary:
	return templates[tower.template]

func upgrade_target(tower: Dictionary) -> String:
	var target: String = data.get("upgrade_targets", {}).get(tower.template, UPGRADES.get(tower.template, ""))
	return target if templates.has(target) else ""

func _tower_period(tower: Dictionary) -> int:
	return frames(tower_template(tower).attacks.list[0].cooldown) + (1 if tower.type == "mage" else 0)

func _melee_period(template: Dictionary) -> int:
	return frames(template.melee.attacks[0].cooldown) + (1 if template.template_name in ["soldier_militia", "soldier_footmen", "soldier_knight"] else 0)

func tower_locked(template_name: String) -> bool:
	return template_name in data.layout.level_mode_overrides[0].get("locked_towers", [])

func sell_refund(tower: Dictionary) -> int:
	if tower.type == "": return 0
	return int(tower.spent) if wave == 0 else roundi(float(tower.spent) * float(tower_template(tower).tower.refund_factor))

func power_price(tower: Dictionary, power: String) -> int:
	if tower.is_empty() or not tower.get("powers", {}).has(power): return -1
	var spec: Dictionary = tower_template(tower).powers[power]
	return -1 if int(tower.powers[power]) >= int(spec.max_level) else int(spec.price_base if int(tower.powers[power]) == 0 else spec.price_inc)

func command(kind: String, args: Dictionary = {}) -> bool:
	if kind == "pause":
		if result != "": return false
		paused = not paused; return true
	if kind == "speed":
		speed = 2 if speed == 1 else 1; return true
	if result != "": return false
	if kind.begins_with("dev_"):
		if not developer_enabled: return false
		match kind:
			"dev_add_gold": gold += 10000
			"dev_add_lives": lives += 100
			"dev_skip_wave":
				if wave == 0 or not notices.is_empty(): return false
				developer_used = true
				_skip_wave()
			_: return false
		developer_used = true
		return true
	if kind == "confirm":
		if notices.is_empty(): return false
		var notice: String = notices.pop_front()
		if notice == "POWER_REINFORCEMENT": unlocked.reinforcements = true
		if notice == "POWER_FIREBALL": unlocked.fire = true
		event.emit("notice_confirmed", {"notice": notice}); return true
	if paused or not notices.is_empty(): return false
	match kind:
		"build":
			var tower := tower_by_id(str(args.get("id", "")))
			var type: String = str(args.get("type", ""))
			if tower.is_empty() or tower.type != "" or type not in TYPES: return false
			var price := int(templates["tower_" + type + "_1"].tower.price)
			if gold < price: return false
			tower.template = "tower_" + type + "_1"; tower.spent = price
			gold -= price; tower.type = type; tower.built_at = tick; tower.ready = tick + frames(float(templates["tower_build_" + type].build_duration)); tower.attack_at = tower.ready
			event.emit("sound", {"id": "GUITowerBuilding"}); return true
		"upgrade":
			var tower := tower_by_id(str(args.get("id", "")))
			var target := str(args.get("upgrade_to", ""))
			if tower.is_empty() or tower.ready > tick or target == "" or target != upgrade_target(tower) or tower_locked(target): return false
			var t: Dictionary = templates[target]
			var price := int(t.tower.price)
			if gold < price: return false
			var upgraded := _holder(tower)
			upgraded.merge({"type": tower.type, "template": target, "spent": int(tower.spent) + price,
				"ready": tick, "inserted": true}, true)
			if tower.type == "barrack": _upgrade_garrison(tower, upgraded)
			else: upgraded.attack_at = tick + _tower_period(upgraded)
			if target == "tower_ranger": Ranger.initialize(self, upgraded)
			gold -= price
			towers[towers.find(tower)] = upgraded
			add_effect("fx_tower_buy_dust", tower.pos + Vector2(0, 10))
			event.emit("sound", {"id": t.sound_events.insert}); return true
		"upgrade_power":
			var tower := tower_by_id(str(args.get("id", "")))
			var power := str(args.get("power", ""))
			var price := power_price(tower, power)
			if tower.is_empty() or tower.ready > tick or price < 0 or gold < price: return false
			gold -= price; tower.spent += price; tower.powers[power] += 1
			if power == "thorn" and int(tower.powers.thorn) == 1:
				tower.ranger.aura = true; tower.ranger.thorn_ts = float(tick)
				tower.layers[5] = {"state":"idle","at":tick,"loop":true,"flip":false,"visible":true}
			for item: Dictionary in data.ui.tower_menus.get("ranger", []):
				if item.get("action_arg", "") == power:
					for sound: String in item.get("sounds", []): event.emit("sound", {"id":sound})
			return true
		"sell":
			var tower := tower_by_id(str(args.get("id", "")))
			if tower.is_empty() or tower.type == "" or tower.ready > tick: return false
			gold += sell_refund(tower)
			for s: Dictionary in soldiers:
				if s.home == tower.id: _retire(s)
			add_effect("fx_tower_sell_dust", tower.pos)
			towers[towers.find(tower)] = _holder(tower)
			event.emit("sound", {"id": "GUITowerSell"}); return true
		"rally":
			var tower := tower_by_id(str(args.get("id", "")))
			var point: Vector2 = args.get("pos", Vector2(-999, -999))
			if tower.is_empty() or tower.type != "barrack" or tower.ready > tick: return false
			point = resolve_rally_point(tower, point)
			if not point.is_finite(): return false
			tower.rally = point
			for s: Dictionary in soldiers:
				if s.home == tower.id and s.hp > 0:
					_unblock(s); s.dest = _formation(point, s.slot, tower); s.rally_center = point; s.rallying = true; s.pending = {}
			event.emit("sound", {"id": "BarrackTaunt"}); return true
		"decal_click":
			for decal: Dictionary in decals:
				if decal.id != int(args.get("id", -1)) or decal.removed: continue
				var d: Dictionary = templates[decal.template].get("delayed_play", {})
				if not d.has("required_clicks"): return false
				decal.clicks += 1; decal.clicked_at = tick
				if decal.clicks >= int(d.required_clicks):
					decal.removed = true
					add_effect(d.required_clicks_fx_alt if decal.alternate else d.required_clicks_fx, decal.pos)
					event.emit("sound", {"id": d.clicked_sound_alt if decal.alternate else d.clicked_sound})
				else: event.emit("sound", {"id": d.click_sound})
				return true
			return false
		"wave":
			if not can_send_wave(): return false
			_start_wave(true); return true
		"cast":
			var power: String = str(args.get("power", ""))
			var point: Vector2 = args.get("pos", Vector2(-999, -999))
			if wave == 0 or not unlocked.get(power, false) or cooldowns.get(power, 0) > 0 or not valid_power_point(power, point): return false
			if power == "reinforcements":
				cooldowns[power] = frames(templates.power_reinforcements_control.cooldown)
				for slot in range(2):
					var s := _soldier("re_farmer", "", slot, point + Vector2(-10 + slot * 20, 0), point)
					s.expires = tick + frames(templates.power_reinforcements_control.duration)
				event.emit("sound", {"id": "ReinforcementTaunt"})
			else:
				cooldowns[power] = frames(templates.power_fireball_control.cooldown)
				for i in range(int(templates.power_fireball_control.fireball_count)):
					var spread := float(templates.power_fireball_control.max_spread)
					var aim := point + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread) * 0.7)
					_projectile("power_fireball", 0, aim + Vector2(-190, 400), aim, 0.9 + i * 0.2)
			return true
	return false

func _upgrade_garrison(old: Dictionary, upgraded: Dictionary) -> void:
	# tower_utils.upgrade_tower creates fresh, full-health entities, then the new
	# soldier coroutine follows nav_rally.new (which releases its inherited block).
	var type: String = tower_template(upgraded).barrack.soldier_type
	for s: Dictionary in soldiers.duplicate():
		if s.home != old.id: continue
		if s.hp > 0:
			var replacement := _soldier(type, old.id, s.slot, s.pos, old.rally)
			var started: int = s.get("attack_started_at", int(s.attack_at) - _melee_period(templates[s.template]))
			for key in ["dest", "flip", "state", "state_at", "target"]: replacement[key] = s[key]
			replacement.attack_started_at = started
			replacement.attack_at = started + _melee_period(templates[type])
			replacement.rally_pending = true
			replacement.dest = _formation(old.rally, s.slot, upgraded)
			upgraded.slots[s.slot] = replacement.id
			for enemy: Dictionary in enemies:
				var index: int = enemy.blockers.find(s.id)
				if index >= 0: enemy.blockers[index] = replacement.id
				if enemy.blocker == s.id: enemy.blocker = replacement.id
		else: _unblock(s)
		soldiers.erase(s)

func _terrain_flags(point: Vector2) -> int:
	var terrain: Dictionary = data.terrain
	# grid_db:get_coords clamps ceil-based, one-indexed cells to the grid edges.
	var x := clampi(ceili((point.x - float(terrain.ox)) / 16.0) - 1, 0, terrain.grid.size() - 1)
	var y := clampi(ceili((point.y - float(terrain.oy)) / 16.0) - 1, 0, terrain.grid[x].size() - 1)
	return int(terrain.grid[x][y])

func _valid_node_nearby(point: Vector2, width_factor: float, flags: int) -> bool:
	var radius_squared := pow(PATH_WIDTH * width_factor, 2)
	var active: Array = data.paths.get("active", [])
	for pi in range(data.paths.paths.size()):
		if pi < active.size() and active[pi] == false: continue
		# Dove searches the main subpath's nodes, using Euclidean distance (not
		# the combat ellipse or a distance to the interpolated road segments).
		var nodes: Array = data.paths.paths[pi][0]
		for ni in range(nodes.size()):
			if point.distance_squared_to(vec(nodes[ni])) >= radius_squared: continue
			var valid := true
			for invalid in data.layout.get("invalid_path_ranges", []):
				if int(invalid.path_id) == pi + 1 and ni + 1 >= int(invalid.get("from", 1)) and ni + 1 <= int(invalid.get("to", nodes.size())) and (flags & ~int(invalid.get("flags", 0xffffffff))) == 0:
					valid = false; break
			if valid: return true
	return false

func valid_ground(point: Vector2, terrains: int = RALLY_TERRAINS) -> bool:
	return point.is_finite() and (_terrain_flags(point) & ~terrains) == 0 and _valid_node_nearby(point, 1.0, NF_RALLY)

func _inside_rally_range(center: Vector2, point: Vector2, radius: float) -> bool:
	# U.is_inside_ellipse uses the range-offset center and this source Y factor.
	var delta := point - center
	var y: float = delta.y * 1.42857142857
	return delta.x * delta.x + y * y <= radius * radius

func _valid_rally_point(barrack: Dictionary, center: Vector2, point: Vector2) -> bool:
	return _inside_rally_range(center, point, float(barrack.rally_range)) and (barrack.get("rally_anywhere", false) or valid_ground(point, int(barrack.rally_terrains)))

func resolve_rally_point(tower: Dictionary, point: Vector2) -> Vector2:
	if not point.is_finite() or tower.is_empty() or tower.type != "barrack": return Vector2.INF
	var template := tower_template(tower)
	var barrack: Dictionary = template.barrack
	var center: Vector2 = tower.pos + vec(template.tower.range_offset)
	if _valid_rally_point(barrack, center, point): return point
	var direction := point - center
	# PickView:on_down first caps the Euclidean direction at rally_range, then
	# scans 99% down to 1%. Each candidate must pass the ellipse AND road filter.
	if not _inside_rally_range(center, point, float(barrack.rally_range)): direction = direction.normalized() * float(barrack.rally_range)
	for i in range(99, 0, -1):
		var candidate := center + direction * (i / 100.0)
		if _valid_rally_point(barrack, center, candidate): return candidate
	return Vector2.INF

func valid_power_point(power: String, point: Vector2) -> bool:
	if not point.is_finite(): return false
	if power == "reinforcements": return valid_ground(point)
	if power != "fire": return false
	var terrain := _terrain_flags(point)
	# The first four levels have no fn_can_power override. Fire additionally
	# accepts water, and uses a wider path radius than troop deployment.
	return (terrain & FIRE_EXCLUDED_TERRAINS) == 0 and ((terrain & 2) != 0 or _valid_node_nearby(point, FIRE_PATH_WIDTH_FACTOR, NF_POWER_1))

func can_send_wave() -> bool:
	return wave < data.waves.groups.size() and spawn_queue.is_empty() and (wave == 0 or next_wave_tick >= 0)

func advance(delta: float) -> void:
	if paused or not notices.is_empty() or result != "": return
	accumulator += delta * speed
	while accumulator + 0.0000001 >= STEP:
		accumulator -= STEP
		step()
		if result != "" or not notices.is_empty():
			accumulator = 0; break

func _start_wave(manual: bool) -> void:
	if manual and wave > 0:
		var remaining := maxi(0, roundi(float(next_wave_tick - tick) / 30.0))
		var reward := ceili(remaining * float(data.rules.early_wave_reward_per_second))
		gold += reward
		var cooling_powers: Array[String] = []
		for power: String in cooldowns:
			# Capture the pre-bonus state: a power that becomes ready still gets its FX.
			if unlocked.get(power, false) and cooldowns[power] > 0: cooling_powers.append(power)
			cooldowns[power] = maxi(0, cooldowns[power] - remaining * 30)
		event.emit("reward", {"gold": reward, "seconds": remaining, "powers": cooling_powers})
	wave += 1; next_wave_tick = -1
	if wave == 1 and int(data.get("level", {}).get("id", 1)) != 1:
		unlocked.reinforcements = true
		unlocked.fire = true
	var group: Dictionary = data.waves.groups[wave - 1]
	var end_tick := tick
	for w: Dictionary in group.waves:
		var spawn_tick := tick + int(w.delay)
		for i in range(w.spawns.size()):
			var spawn: Dictionary = w.spawns[i]
			for j in range(int(spawn.max)):
				spawn_tick += int(spawn.interval)
				var type: String = spawn.creep
				if spawn.get("max_same", 0) > 0 and spawn.has("creep_aux") and (j / int(spawn.max_same)) % 2 == 1: type = spawn.creep_aux
				spawn_queue.append({"tick": spawn_tick, "type": type, "path": int(w.path_index) - 1, "subpath": int(spawn.path) - 1 if int(spawn.fixed_sub_path) == 1 else -1, "order": spawn_queue.size()})
			if int(spawn.max) == 0: spawn_tick += int(spawn.interval)
			if i + 1 < w.spawns.size(): spawn_tick += int(spawn.interval_next)
		end_tick = maxi(end_tick, spawn_tick)
		if w.has("notification") and data.ui.notifications.has(w.notification) and (wave > 1 or int(data.get("level", {}).get("id", 1)) == 1): notices.append(w.notification)
		if w.has("notification_second_level"): event.emit("tip", {"id": w.notification_second_level})
	spawn_queue.sort_custom(func(a, b): return a.tick < b.tick if a.tick != b.tick else a.order < b.order)
	wave_end_tick = end_tick
	event.emit("wave", {"number": wave})
	event.emit("sound", {"id": "GUINextWaveIncoming"})

func step() -> void:
	if paused or not notices.is_empty() or result != "": return
	tick += 1
	modifiers.step(self)
	for power: String in cooldowns: cooldowns[power] = maxi(0, cooldowns[power] - 1)
	while not spawn_queue.is_empty() and spawn_queue[0].tick <= tick:
		var spawn: Dictionary = spawn_queue.pop_front()
		_spawn_enemy(spawn.type, spawn.subpath, spawn.path)
	if wave > 0 and spawn_queue.is_empty() and next_wave_tick < 0 and wave < data.waves.groups.size():
		next_wave_tick = wave_end_tick + int(data.waves.groups[wave].interval)
		event.emit("sound", {"id": "GUINextWaveReady"})
	if next_wave_tick >= 0 and tick >= next_wave_tick: _start_wave(false)
	if not notices.is_empty(): return
	_decals_step()
	_sync_enemy_cells()
	for tower: Dictionary in towers: _tower_step(tower)
	for soldier: Dictionary in soldiers: _soldier_step(soldier)
	for enemy: Dictionary in enemies: _enemy_step(enemy)
	for bullet: Dictionary in projectiles: _bullet_step(bullet)
	projectiles = projectiles.filter(func(p): return not p.done)
	enemies = enemies.filter(func(e): return e.hp > 0 or tick - e.dead_at < frames(templates[e.template].health.dead_lifetime))
	soldiers = soldiers.filter(func(s): return s.hp > 0 or tick - s.dead_at < 60)
	effects = effects.filter(func(e): return tick - e.at < e.duration)
	if lives <= 0: _finish("defeat")
	elif wave == data.waves.groups.size() and spawn_queue.is_empty() and enemies.all(func(e): return e.hp <= 0): _finish("victory")

func _finish(value: String) -> void:
	if result != "": return
	result = value; event.emit("finished", {"result": result})
	if result == "defeat": event.emit("sound", {"id": "GUILooseLife"})

func _skip_wave() -> void:
	spawn_queue.clear()
	for enemy: Dictionary in enemies:
		if enemy.hp > 0: damage(enemy, enemy.hp, 1)
	for soldier: Dictionary in soldiers: _unblock(soldier)
	for tower: Dictionary in towers: tower.pending = {}
	projectiles.clear()
	next_wave_tick = -1; wave_end_tick = tick
	if wave == data.waves.groups.size(): _finish("victory")
	else: _start_wave(false)

func _spawn_enemy(type: String, subpath: int = -1, path: int = 0) -> Dictionary:
	var t: Dictionary = templates[type]
	if subpath < 0: subpath = rng.randi_range(0, data.paths.paths[path].size() - 1)
	var hp := floori(float(t.health.hp_max) * float(data.rules.enemy_hp_factor))
	var e := {"id": next_id, "template": type, "hp": float(hp), "max_hp": float(hp), "pos": vec(data.paths.paths[path][subpath][0]), "path": path, "subpath": subpath, "node": 0, "progress": 0.0, "blocker": 0, "blockers": [], "attack_at": tick, "pending": {}, "state": "walkingDown", "state_at": tick, "dead_at": -1, "flip": false, "last_dir": Vector2.ZERO, "heal_at": tick, "casting": {}}
	next_id += 1; enemies.append(e)
	spawn_log.append({"tick": tick, "type": type, "path": path, "subpath": subpath, "wave": wave})
	if data.ui.notifications.has(type) and not seen_enemies.has(type):
		seen_enemies[type] = true; alerts.append(type)
	return e

func _tower_step(tower: Dictionary) -> void:
	if tower.type == "" or tower.ready > tick: return
	if tower.template == "tower_ranger": Ranger.step(self, tower); return
	var t: Dictionary = tower_template(tower)
	if tower.ready == tick and not tower.get("inserted", false):
		tower.inserted = true
		event.emit("sound", {"id": t.sound_events.insert})
		add_effect("fx_tower_buy_dust", tower.pos)
	if tower.type == "barrack":
		_barrack_step(tower, t)
		return
	var attack: Dictionary = t.attacks.list[0]
	if not tower.pending.is_empty() and tick >= tower.pending.at:
		var target := unit_by_id(tower.pending.target)
		if tower.type in ["engineer", "mage"] or (not target.is_empty() and target.hp > 0):
			var offset := vec(tower.pending.offset)
			var bullet: Dictionary = templates[attack.bullet].bullet
			var flight := float(bullet.get("flight_time", 1))
			var aim: Vector2 = tower.pending.aim
			var target_id: int = target.get("id", 0)
			if tower.type == "mage":
				if not target.is_empty() and distance(tower.pos + vec(t.tower.range_offset), target.pos) <= float(t.attacks.range) * 1.1:
					aim = target.pos + vec(templates[target.template].unit.hit_offset)
				else: target_id = 0
			elif not target.is_empty() and target.hp > 0:
				if not bullet.has("flight_time"): flight = distance(tower.pos, target.pos) / float(bullet.get("max_speed", 300))
				if tower.type == "engineer": aim = _predict(target, flight)
				else:
					aim = target.pos + vec(templates[target.template].unit.hit_offset)
					if bullet.get("predict_target_pos", false) and target.blocker == 0: aim += target.last_dir * 30.0 * flight
			_projectile(attack.bullet, target_id, tower.pos + offset, aim, flight)
		tower.pending = {}
	if tick < tower.attack_at or not tower.pending.is_empty(): return
	var target := _target(tower.pos + vec(t.tower.range_offset), float(t.attacks.range))
	if target.is_empty(): return
	var offsets = attack.bullet_start_offset
	var shooter := 0
	if offsets is Array:
		tower.shot_count = int(tower.get("shot_count", 0)) + 1
		shooter = int(tower.shot_count) % offsets.size() if tower.type == "archer" else (0 if target.pos.y > tower.pos.y + float(offsets[0].y) else mini(1, offsets.size() - 1))
	var offset: Dictionary = offsets[shooter] if offsets is Array else offsets
	tower.pending = {"at": tick + frames(attack.shoot_time), "target": target.id, "offset": offset, "aim": _predict(target, float(templates[attack.bullet].bullet.get("flight_time", 1)))}
	if tower.type == "mage": tower.pending.aim = target.pos
	tower.shot_at = tick; tower.shot_up = target.pos.y > tower.pos.y + float(offset.y)
	tower.attack_at = tick + _tower_period(tower)
	if not tower.has("layers"): tower.layers = {}
	for sid in range(1, t.render.sprites.size() + 1):
		var sprite: Dictionary = t.render.sprites[sid - 1]
		if not sprite.get("animated", false): continue
		if tower.type == "archer" and sid != shooter + 3: continue
		var state := "shoot"
		if sprite.has("angles"): state = "shootingUp" if tower.shot_up else "shootingDown"
		var idle := "idleUp" if tower.shot_up else "idleDown"
		tower.layers[sid] = {"state": state, "at": tick, "loop": false, "flip": tower.type == "archer" and target.pos.x < tower.pos.x + float(offset.x), "idle": idle if sprite.has("angles") else "idle"}

func _target(point: Vector2, radius: float, unblocked: bool = false) -> Dictionary:
	var best := {}; var remaining := INF
	for e: Dictionary in enemies:
		if e.hp <= 0 or (unblocked and e.blockers.size() >= 3): continue
		var nodes_left: float = data.paths.paths[e.get("path", 0)][e.subpath].size() - e.progress
		if distance(point, e.pos) <= radius and nodes_left < remaining:
			best = e; remaining = nodes_left
	return best

func _barrack_step(tower: Dictionary, template: Dictionary) -> void:
	var b: Dictionary = template.barrack
	var door: Dictionary = template.render.sprites[2]
	if not tower.has("door_state"):
		tower.door_state = "closed"; tower.door_at = tick
		tower.layers = {3: {"state": "close", "at": tick - SpriteAnimation.duration(animations, SpriteAnimation.key(door, "close")), "loop": false}}
	var missing: Array[int] = []
	for slot in range(int(b.max_soldiers)):
		if int(tower.slots[slot]) <= 0 and -int(tower.slots[slot]) <= tick: missing.append(slot)
	match tower.door_state:
		"closed":
			if not missing.is_empty():
				tower.door_state = "opening"; tower.door_at = tick
				tower.layers[3] = {"state": "open", "at": tick, "loop": false}
				event.emit("sound", {"id": "GUITowerOpenDoor"})
		"opening":
			if tick - tower.door_at >= SpriteAnimation.duration(animations, SpriteAnimation.key(door, "open")):
				tower.door_state = "open"; tower.door_at = tick
		"closing":
			if tick - tower.door_at >= SpriteAnimation.duration(animations, SpriteAnimation.key(door, "close")): tower.door_state = "closed"
	if tower.door_state == "open":
		for slot in missing:
			var s := _soldier(b.soldier_type, tower.id, slot, tower.pos + vec(b.respawn_offset), tower.rally)
			tower.slots[slot] = s.id
		if tick - tower.door_at > frames(b.door_hold_time):
			tower.door_state = "closing"; tower.door_at = tick
			tower.layers[3] = {"state": "close", "at": tick, "loop": false}

func _decals_step() -> void:
	for decal: Dictionary in decals:
		if decal.removed: continue
		var d: Dictionary = templates[decal.template].get("delayed_play", {"min_delay": 5, "max_delay": 10, "play_animation": "jump"})
		if not decal.hidden and decal.state == d.play_animation:
			var sprite: Dictionary = templates[decal.template].render.sprites[0]
			if tick - decal.state_at >= SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, d.play_animation)):
				decal.state = d.get("idle_animation", ""); decal.hidden = not d.has("idle_animation"); decal.state_at = tick
				decal.next_play = tick + frames(rng.randf_range(d.min_delay, d.max_delay))
		elif tick >= decal.next_play:
			decal.state = d.play_animation; decal.state_at = tick; decal.hidden = false
			if rng.randf() < float(d.get("flip_chance", 0)): decal.flip = not decal.flip

func add_effect(template_name: String, point: Vector2, extra: Dictionary = {}) -> void:
	if not templates.has(template_name): return
	var lifetime := 1
	var template: Dictionary = templates[template_name]
	for sprite: Dictionary in template.get("render", {}).get("sprites", []):
		lifetime = maxi(lifetime, SpriteAnimation.duration(animations, SpriteAnimation.key(sprite)))
	for property: Dictionary in template.get("tween", {}).get("props", []):
		if property.has("keys"): lifetime = maxi(lifetime, frames(float(property.keys[-1][0])))
	var effect := {"template": template_name, "pos": point, "at": tick, "duration": lifetime}
	effect.merge(extra, true); effects.append(effect)

func _predict(e: Dictionary, seconds: float) -> Vector2:
	if e.blocker != 0: return e.pos
	var points: Array = data.paths.paths[e.get("path", 0)][e.subpath]
	var remaining := seconds * float(templates[e.template].motion.max_speed) * float(data.rules.enemy_speed_factor) * modifiers.speed(e.id, self)
	if int(e.get("stun_count",0)) > 0: return e.pos
	var point: Vector2 = e.pos
	for node in range(int(e.node) + 1, points.size()):
		var dest := vec(points[node]); var length := point.distance_to(dest)
		if length >= remaining: return point.move_toward(dest, remaining)
		remaining -= length; point = dest
	return point

func _soldier(type: String, home: String, slot: int, point: Vector2, rally: Vector2) -> Dictionary:
	var t: Dictionary = templates[type]
	var s := {"id": next_id, "template": type, "home": home, "slot": slot, "pos": point, "dest": _formation(rally, slot, tower_by_id(home)), "hp": float(t.health.hp_max), "max_hp": float(t.health.hp_max), "target": 0, "attack_at": tick, "pending": {}, "state": "idle", "state_at": tick, "dead_at": -1, "last_hit": tick, "regen_at": tick, "born_at": tick, "expires": -1, "flip": false, "variant": rng.randi_range(1, 3)}
	s.rally_center = rally
	s.attack_started_at = 0
	s.attack_at = maxi(tick, _melee_period(t))
	s.rallying = true
	var names: Array = data.ui.unit_names.get(type, [])
	if not names.is_empty(): s.display_name = names[rng.randi_range(0, names.size() - 1)]
	if type == "re_farmer": s.portrait = "info_portraits_soldiers_%04d" % int(t.info.portrait_idxs[s.variant - 1])
	next_id += 1; soldiers.append(s); return s

func _formation(point: Vector2, slot: int, tower: Dictionary = {}) -> Vector2:
	var angle := slot * TAU / 3.0 - PI / 2.0
	var radius: float = tower_template(tower).barrack.rally_radius if not tower.is_empty() and tower.type == "barrack" else 25.0
	return point + Vector2(cos(angle), sin(angle) * 0.7) * radius

func _soldier_target(s: Dictionary, only_free: bool = false) -> Dictionary:
	# Dove searches around nav_rally.center, not the soldier's formation slot.
	var target := {}
	var remaining := INF
	for e: Dictionary in enemies:
		if e.hp <= 0 or (only_free and not e.blockers.is_empty()): continue
		if templates[e.template].enemy.has("max_blockers") and not e.blockers.is_empty(): continue
		var nodes_left: float = data.paths.paths[e.path][e.subpath].size() - e.progress
		if distance(s.rally_center, e.pos) <= float(templates[s.template].melee.range) and nodes_left < remaining:
			target = e; remaining = nodes_left
	return target

func melee_slot(s: Dictionary, e: Dictionary) -> Vector2:
	# U.melee_slot_position: ranks repeat in threes and use the enemy's path heading.
	var rank: int = e.blockers.find(s.id) % 3
	var offset := Vector2.ZERO if rank == 0 else Vector2(-3, -6 if rank == 1 else 6)
	var forward: Vector2 = e.last_dir
	if forward == Vector2.ZERO:
		var route: Array = data.paths.paths[e.path][e.subpath]
		forward = vec(route[mini(e.node + 1, route.size() - 1)]) - e.pos
	var slot := vec(templates[e.template].enemy.melee_slot) + offset + vec(templates[s.template].soldier.melee_slot_offset)
	slot.x *= 1 if forward.x > 0 else -1
	return e.pos + slot

func _soldier_move(s: Dictionary, point: Vector2, speed_value: float) -> bool:
	if not s.pos.is_equal_approx(point):
		s.flip = point.x < s.pos.x
		s.pos = s.pos.move_toward(point, speed_value * STEP)
	if s.pos.is_equal_approx(point):
		s.pos = point
		if s.state == "running": _state(s, "idle")
		return false
	_state(s, "running")
	return true

func _soldier_step(s: Dictionary) -> void:
	if s.hp <= 0: return
	if s.expires >= 0 and tick >= s.expires: _retire(s); return
	var t: Dictionary = templates[s.template]
	if s.get("rally_pending", false):
		_unblock(s); s.rally_pending = false; s.rallying = true
	# y_soldier_new_rally moves directly and suppresses interception until arrival.
	if s.rallying:
		if not _soldier_move(s, s.dest, t.motion.max_speed): s.rallying = false; _state(s, "idle")
		return
	var target := unit_by_id(s.target)
	if target.is_empty() or target.hp <= 0 or not s.id in target.blockers:
		_unblock(s)
		target = _soldier_target(s)
	elif target.blockers.find(s.id) > 0 and s.pending.is_empty():
		var alternate := _soldier_target(s, true)
		if not alternate.is_empty(): _unblock(s); target = alternate
	if not target.is_empty() and s.target == 0:
		s.target = target.id; target.blockers.append(s.id); target.blocker = target.blockers[0]
	if not target.is_empty() and s.target != 0:
		if _soldier_move(s, melee_slot(s, target), t.motion.max_speed): return
		s.flip = target.pos.x < s.pos.x
		_melee(s, target, t)
	else:
		if not _soldier_move(s, s.dest, t.motion.max_speed):
			_state(s, "idle")
			if tick - s.last_hit >= frames(float(t.regen.last_hit_standoff_time)) and tick >= s.regen_at:
				s.hp = minf(s.max_hp, s.hp + s.max_hp * float(data.rules.soldier_regen_factor)); s.regen_at = tick + frames(t.regen.cooldown)

func _enemy_step(e: Dictionary) -> void:
	if e.hp <= 0: return
	if int(e.get("stun_count",0)) > 0: e.last_dir = Vector2.ZERO; return
	var t: Dictionary = templates[e.template]
	if t.has("timed_attacks") and _healer_step(e, t): return
	if e.blocker != 0:
		var s := unit_by_id(e.blocker)
		if s.is_empty() or s.hp <= 0 or s.target != e.id: e.blocker = 0; e.pending = {}
		else:
			e.flip = s.pos.x < e.pos.x
			if s.pos.is_equal_approx(melee_slot(s, e)): _melee(e, s, t)
			else: _state(e, "idle")
			return
	var points: Array = data.paths.paths[e.get("path", 0)][e.subpath]
	var remaining := float(t.motion.max_speed) * float(data.rules.enemy_speed_factor) * STEP * modifiers.speed(e.id, self)
	var previous: Vector2 = e.pos
	while remaining > 0 and e.node + 1 < points.size():
		var dest := vec(points[e.node + 1]); var length: float = e.pos.distance_to(dest)
		if length > remaining:
			e.pos = e.pos.move_toward(dest, remaining); remaining = 0
		else:
			e.pos = dest; remaining -= length; e.node += 1
	e.progress = float(e.node) + 1.0 - e.pos.distance_to(vec(points[mini(e.node + 1, points.size() - 1)])) / 8.0
	var direction: Vector2 = e.pos - previous
	e.last_dir = direction
	e.flip = direction.x < 0
	_state(e, "walkingRightLeft" if absf(direction.x) > absf(direction.y) * 1.4 else ("walkingUp" if direction.y > 0 else "walkingDown"))
	# all/systems/enemy.lua removes at the original path end node.
	if e.node >= points.size() - 1:
		lives = maxi(0, lives - int(t.enemy.lives_cost)); leaks += 1
		gold += int(t.enemy.gold * float(data.rules.enemy_gold_factor))
		e.hp = 0.0; e.dead_at = tick - 300; _unblock(e)
		event.emit("sound", {"id": "GUILooseLife"})

func _melee(attacker: Dictionary, target: Dictionary, template: Dictionary) -> void:
	var attack: Dictionary = template.melee.attacks[0]
	# Arriving during the attack cooldown must stop the walk animation immediately.
	if attacker.state == "running": _state(attacker, "idle")
	if not attacker.pending.is_empty() and attacker.pending.has("dodge_at") and tick >= attacker.pending.dodge_at and not attacker.pending.has("dodged"):
		var dodge: Dictionary = templates[target.template].get("dodge", {})
		attacker.pending.dodged = rng.randf() <= float(dodge.get("chance", 0))
	if not attacker.pending.is_empty() and tick >= attacker.pending.at:
		if target.hp > 0 and not attacker.pending.get("dodged", false): damage(target, float(rng.randi_range(int(attack.damage_min), int(attack.damage_max))), int(attack.damage_type))
		attacker.pending = {}
	if tick >= attacker.attack_at:
		attacker.attack_started_at = tick
		attacker.attack_at = tick + _melee_period(template)
		attacker.pending = {"at": tick + frames(attack.hit_time)}
		if templates[target.template].has("dodge") and attack.has("dodge_time"):
			attacker.pending.dodge_at = tick + frames(attack.dodge_time)
		_state(attacker, "attack", true)
		if attack.has("sound"): event.emit("sound", {"id": attack.sound})
	elif tick - attacker.state_at > frames(attack.cooldown) - 1: _state(attacker, "idle")

func _healing_targets(source: Dictionary, attack: Dictionary) -> Array:
	_sync_enemy_cells()
	var targets: Array = []
	var cells: Array = enemy_cells.keys()
	cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	# seek.filter_on visits source spatial cells in row/column order; it does not
	# prioritize nearest or most wounded enemies. Preserve swap-removal ordering.
	for cell: Vector2i in cells:
		for id: int in enemy_cells[cell]:
			var e := unit_by_id(id)
			var flags: Dictionary = templates[e.template].get("vis", {})
			if e.hp > 0 and e.hp < e.max_hp and distance(source.pos, e.pos) <= float(attack.max_range) and (int(flags.get("bans", 0)) & int(attack.vis_flags)) == 0 and (int(flags.get("flags", 0)) & int(attack.vis_bans)) == 0:
				targets.append(e)
	return targets

func _sync_enemy_cells() -> void:
	if spatial_tick == tick: return
	spatial_tick = tick
	var active := {}
	for e: Dictionary in enemies:
		active[e.id] = true
		var origin := vec(data.constants.get("spatial_origin", {"x": -400, "y": -250}))
		var cell_size := float(data.constants.get("spatial_cell_size", 50))
		var cell := Vector2i(floori((e.pos.x - origin.x) / cell_size), floori((e.pos.y - origin.y) / cell_size))
		if cell_for_enemy.has(e.id) and cell_for_enemy[e.id] == cell: continue
		_remove_enemy_cell(e.id)
		if not enemy_cells.has(cell): enemy_cells[cell] = []
		enemy_cells[cell].append(e.id); cell_for_enemy[e.id] = cell
	for id: int in cell_for_enemy.keys():
		if not active.has(id): _remove_enemy_cell(id)

func _remove_enemy_cell(id: int) -> void:
	if not cell_for_enemy.has(id): return
	var cell: Vector2i = cell_for_enemy[id]
	var ids: Array = enemy_cells[cell]
	var index := ids.find(id)
	ids[index] = ids[-1]; ids.pop_back()
	if ids.is_empty(): enemy_cells.erase(cell)
	cell_for_enemy.erase(id)

func _healer_step(e: Dictionary, template: Dictionary) -> bool:
	var attack: Dictionary = template.timed_attacks.list[0]
	if not e.casting.is_empty():
		if not e.casting.applied and tick >= e.casting.hit_at:
			e.casting.applied = true
			var targets := _healing_targets(e, attack)
			var modifier: Dictionary = templates[attack.mod]
			for target: Dictionary in targets.slice(0, int(attack.max_count)):
				var amount := float(rng.randi_range(int(modifier.hps.heal_min), int(modifier.hps.heal_max)))
				target.hp = minf(target.max_hp, target.hp + amount)
				add_effect(attack.mod, target.pos, {"target": target.id, "duration": frames(modifier.modifier.duration), "state": modifier.render.sprites[0].size_names[int(templates[target.template].unit.size) - 1]})
				event.emit("healed", {"source": e.id, "target": target.id, "amount": amount})
		if tick < e.casting.ends_at: return true
		e.casting = {}
	if tick - int(e.heal_at) <= frames(attack.cooldown): return false
	if _healing_targets(e, attack).is_empty():
		e.heal_at = tick - frames(attack.cooldown) + frames(0.5) - 1; return false
	e.heal_at = tick
	e.pending = {}
	e.last_dir = Vector2.ZERO
	_state(e, attack.animation, true)
	e.casting = {"hit_at": tick + frames(attack.cast_time), "ends_at": tick + SpriteAnimation.duration(animations, SpriteAnimation.key(template.render.sprites[0], attack.animation)), "applied": false}
	event.emit("sound", {"id": attack.sound})
	return true

func _state(unit: Dictionary, state: String, restart: bool = false) -> void:
	if unit.state != state or restart: unit.state = state; unit.state_at = tick

func _unblock(unit: Dictionary) -> void:
	if unit.has("target") and unit.target != 0:
		var enemy := unit_by_id(unit.target)
		if not enemy.is_empty():
			var old_blocker: int = enemy.blocker
			enemy.blockers.erase(unit.id)
			if enemy.blockers.size() > 1: enemy.blockers.push_front(enemy.blockers.pop_back())
			enemy.blocker = 0 if enemy.blockers.is_empty() else enemy.blockers[0]
			if enemy.blocker != old_blocker: enemy.pending = {}
		unit.target = 0
		unit.pending = {}
	if unit.has("blockers"):
		for id: int in unit.blockers:
			var soldier := unit_by_id(id)
			if not soldier.is_empty():
				soldier.target = 0; soldier.pending = {}
		unit.blocker = 0; unit.blockers.clear()

func _retire(s: Dictionary) -> void:
	s.hp = 0; s.dead_at = tick; _unblock(s); _state(s, "death", true)

func damage(unit: Dictionary, amount: float, type: int) -> float:
	if unit.is_empty() or unit.hp <= 0: return 0
	var t: Dictionary = templates[unit.template]
	var armor := 0.0
	if (type & 65536) != 0: armor = float(t.health.get("poison_armor",0))
	elif (type & 1) != 0: armor = 0.0
	elif (type & 2) != 0: armor = float(t.health.armor)
	elif (type & 4) != 0: armor = float(t.health.magic_armor)
	elif (type & 8) != 0: armor = float(t.health.armor)
	# Frozen Dove all/utils.lua U.calc_protection, including its explosion curve.
	if (type & 8) != 0 and (type & (65536 | 1 | 2 | 4)) == 0: armor *= 0.2 * armor + 0.4
	var actual := amount * (1.0 - armor)
	unit.hp = maxf(0, unit.hp - actual)
	if unit.has("last_hit"): unit.last_hit = tick
	if unit.hp <= 0:
		unit.dead_at = tick; _unblock(unit); _state(unit, "death", true); unit.pending = {}
		if t.has("enemy"):
			gold += int(t.enemy.gold * float(data.rules.enemy_gold_factor)); kills += 1
			if t.sound_events.has("death"): event.emit("sound", {"id": t.sound_events.death})
		elif unit.home != "":
			var tower := tower_by_id(unit.home)
			if not tower.is_empty(): tower.slots[unit.slot] = -(tick + frames(float(t.health.dead_lifetime)))
	return actual

func _projectile(type: String, target: int, from: Vector2, to: Vector2, flight: float) -> void:
	var bullet: Dictionary = templates[type].bullet
	var duration := frames(flight)
	var b := {"template": type, "target": target, "from": from, "to": to, "pos": from, "at": tick, "duration": duration, "done": false,
		"velocity": Projectile.launch(from, to, duration / 30.0, bullet), "initial_rotation": rng.randf_range(-PI / 2, PI / 2) if bullet.has("rotation_speed") else 0.0,
		"rotation": 0.0, "hidden": float(bullet.get("hide_radius", 0)) > 0}
	if templates[type].get("behavior", "") == "scripts.bolt.update":
		b.speed = float(bullet.min_speed); b.last_step = tick; b.target_invalid = false
	projectiles.append(b)
	var sounds: Dictionary = templates[type].get("sound_events", {})
	if sounds.has("insert"): event.emit("sound", {"id": sounds.insert})

func _bullet_step(p: Dictionary) -> void:
	var b: Dictionary = templates[p.template].bullet
	var target := unit_by_id(p.target)
	var behavior: String = templates[p.template].get("behavior", "")
	var ratio := clampf(float(tick - p.at) / p.duration, 0, 1)
	if behavior == "scripts.bolt.update":
		if not _bolt_step(p, b, target): return
		if p.target_invalid: target = {}
	elif p.template == "power_fireball":
		p.pos = p.from.lerp(p.to, ratio)
		p.rotation = (p.to - p.from).angle()
	else:
		p.merge(Projectile.sample(p, b, (tick - p.at) / 30.0), true)
	if behavior != "scripts.bolt.update" and ratio < 1: return
	p.done = true
	if float(b.damage_radius) > 0:
		for e: Dictionary in enemies:
			if e.hp > 0 and distance(p.to, e.pos) <= float(b.damage_radius):
				var amount: float = rng.randi_range(int(b.damage_min), int(b.damage_max))
				if behavior == "scripts.bomb.update":
					var delta: Vector2 = e.pos - p.to
					var angle := delta.angle()
					var ellipse_radius := Vector2(cos(angle), 0.7 * sin(angle)).length() * float(b.damage_radius)
					amount = lerpf(float(b.damage_max), float(b.damage_min), clampf(delta.length() / ellipse_radius, 0, 1))
				damage(e, amount, int(b.damage_type))
		var water: bool = behavior == "scripts.bomb.update" and (_terrain_flags(p.to) & 2) != 0 and templates.has(b.get("hit_fx_water", ""))
		add_effect(str(b.get("hit_fx_water", "")) if water else str(b.get("hit_fx", "")), p.to)
		if not water: add_effect(str(b.get("hit_decal", "")), p.to)
	elif not target.is_empty() and target.hp > 0:
		var hit: Vector2 = target.pos + vec(templates[target.template].unit.hit_offset)
		if behavior == "scripts.bolt.update" or p.to.distance_to(hit) < float(b.get("hit_distance", 22)) * 1.2:
			damage(target, rng.randi_range(int(b.damage_min), int(b.damage_max)), int(b.damage_type))
			if int(p.get("poison_level",0)) > 0 and target.hp > 0:
				modifiers.apply(self,"mod_ranger_poison",target,int(p.poison_level),str(p.source))
			if behavior != "scripts.bolt.update": add_effect(str(b.get("hit_fx", "")), hit)
			add_effect(str(b.get("hit_blood_fx", "")), hit, {"rotation": p.rotation})
	if behavior == "scripts.bolt.update": add_effect(str(b.get("hit_fx", "")), p.to)
	var sounds: Dictionary = templates[p.template].get("sound_events", {})
	var water_impact: bool = behavior == "scripts.bomb.update" and (_terrain_flags(p.to) & 2) != 0 and templates.has(b.get("hit_fx_water", ""))
	if water_impact and sounds.has("hit_water"): event.emit("sound", {"id": sounds.hit_water})
	elif sounds.has("hit"): event.emit("sound", {"id": sounds.hit})

func _bolt_step(p: Dictionary, bullet: Dictionary, target: Dictionary) -> bool:
	# all/scripts.lua bolt.update: test arrival before yielding, then accelerate
	# with the source's quantized speed and stop tracking abrupt target movement.
	if p.pos.distance_to(p.to) <= float(p.speed) * STEP:
		p.pos = p.to; return true
	if tick <= int(p.last_step): return false
	p.last_step = tick
	if not p.target_invalid and not target.is_empty():
		var hit: Vector2 = target.pos + vec(templates[target.template].unit.hit_offset)
		var delta: Vector2 = hit - p.to
		if maxf(absf(delta.x), absf(delta.y)) > float(bullet.max_track_distance): p.target_invalid = true
		elif target.hp > 0: p.to = hit
	p.speed = clampf(float(p.speed) + 30.0 * ceilf(float(p.speed) / 30.0 * float(bullet.acceleration_factor)), float(bullet.min_speed), float(bullet.max_speed))
	p.pos += p.pos.direction_to(p.to) * float(p.speed) * STEP
	p.rotation = (p.to - p.pos).angle()
	if p.pos.distance_to(p.to) <= float(p.speed) * STEP:
		p.pos = p.to; return true
	return false
