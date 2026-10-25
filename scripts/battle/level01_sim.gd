extends RefCounted
## Deterministic 30 Hz campaign state. All player actions go through command().
signal event(kind: String, payload: Dictionary)

const STEP := 1.0 / 30.0
const TYPES := ["archer", "barrack", "mage", "engineer"]
const SpriteAnimation = preload("res://scripts/battle/dove_animation.gd")
const Projectile = preload("res://scripts/battle/dove_projectile.gd")
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

func _init(definition: Dictionary = {}, seed_value: int = 1, allow_developer: bool = false) -> void:
	developer_enabled = allow_developer and OS.is_debug_build()
	data = definition if not definition.is_empty() else JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/definition.json"))
	templates = data.templates
	animations = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/animations.json")).animations
	reset(seed_value)

func reset(seed_value: int = 1) -> void:
	rng.seed = seed_value
	tick = 0; gold = int(data.waves.cash); lives = int(data.waves.lives)
	wave = 0; next_wave_tick = -1; wave_end_tick = -1; result = ""
	paused = false; speed = 1; accumulator = 0; next_id = 1; kills = 0; leaks = 0
	developer_used = false
	towers.clear(); enemies.clear(); soldiers.clear(); projectiles.clear(); effects.clear(); decals.clear(); spawn_queue.clear(); spawn_log.clear()
	notices = ["TUTORIAL_1", "TUTORIAL_2", "TUTORIAL_3"]
	unlocked = {"reinforcements": false, "fire": false}
	cooldowns = {"reinforcements": 0, "fire": 0}
	for index in range(data.layout.entities_list.size()):
		var e: Dictionary = data.layout.entities_list[index]
		if str(e.template).begins_with("tower_holder"):
			towers.append({"id": str(e["tower.holder_id"]), "pos": vec(e.pos), "rally": vec(e["tower.default_rally_pos"]), "type": "", "ready": 0, "attack_at": 0, "shot_at": -1000, "shot_up": false, "pending": {}, "slots": [0, 0, 0]})
		elif templates.has(e.template) and templates[e.template].has("delayed_play"):
			var d: Dictionary = templates[e.template].delayed_play
			decals.append({"id": index, "template": e.template, "pos": vec(e.pos), "clicks": 0, "clicked_at": -1000, "removed": false,
				"state": d.idle_animation, "state_at": 0, "next_play": frames(rng.randf_range(d.min_delay, d.max_delay)),
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
			gold -= price; tower.type = type; tower.built_at = tick; tower.ready = tick + frames(float(templates["tower_build_" + type].build_duration)); tower.attack_at = tower.ready
			event.emit("sound", {"id": "GUITowerBuilding"}); return true
		"sell":
			var tower := tower_by_id(str(args.get("id", "")))
			if tower.is_empty() or tower.type == "" or tower.ready > tick: return false
			var t: Dictionary = templates["tower_" + tower.type + "_1"].tower
			gold += int(floor(t.price * t.refund_factor))
			for s: Dictionary in soldiers:
				if s.home == tower.id: _retire(s)
			add_effect("fx_tower_sell_dust", tower.pos)
			tower.type = ""; tower.pending = {}; tower.slots = [0, 0, 0]
			tower.erase("door_state"); tower.erase("layers")
			event.emit("sound", {"id": "GUITowerSell"}); return true
		"rally":
			var tower := tower_by_id(str(args.get("id", "")))
			var point: Vector2 = args.get("pos", Vector2(-999, -999))
			if tower.is_empty() or tower.type != "barrack" or tower.ready > tick: return false
			if distance(tower.pos, point) > templates.tower_barrack_1.barrack.rally_range or not valid_ground(point): return false
			tower.rally = point
			for s: Dictionary in soldiers:
				if s.home == tower.id and s.hp > 0:
					_unblock(s); s.dest = _formation(point, s.slot); s.rallying = true; s.pending = {}
			event.emit("sound", {"id": "BarrackTaunt"}); return true
		"decal_click":
			for decal: Dictionary in decals:
				if decal.id != int(args.get("id", -1)) or decal.removed: continue
				var d: Dictionary = templates[decal.template].delayed_play
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
			if not unlocked.get(power, false) or cooldowns.get(power, 0) > 0 or not valid_ground(point): return false
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

func valid_ground(point: Vector2) -> bool:
	if point.x < 0 or point.x > 1024 or point.y < 40 or point.y > 735: return false
	var terrain: Dictionary = data.terrain
	var x := ceili((point.x - float(terrain.ox)) / 16.0) - 1
	var y := ceili((point.y - float(terrain.oy)) / 16.0) - 1
	if x < 0 or x >= terrain.grid.size() or y < 0 or y >= terrain.grid[x].size(): return false
	var flags := int(terrain.grid[x][y])
	return (flags & 1) != 0 and (flags & 256) == 0

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
		for power: String in cooldowns: cooldowns[power] = maxi(0, cooldowns[power] - remaining * 30)
		event.emit("reward", {"gold": reward})
	wave += 1; next_wave_tick = -1
	var group: Dictionary = data.waves.groups[wave - 1]
	var end_tick := tick
	for w: Dictionary in group.waves:
		var spawn_tick := tick + int(w.delay)
		for i in range(w.spawns.size()):
			var spawn: Dictionary = w.spawns[i]
			for j in range(int(spawn.max)):
				spawn_tick += int(spawn.interval)
				spawn_queue.append({"tick": spawn_tick, "type": spawn.creep, "subpath": int(spawn.path) - 1 if int(spawn.fixed_sub_path) == 1 else -1})
			if i + 1 < w.spawns.size(): spawn_tick += int(spawn.interval_next)
		end_tick = maxi(end_tick, spawn_tick)
		if w.has("notification"): notices.append(w.notification)
		if w.has("notification_second_level"): event.emit("tip", {"id": w.notification_second_level})
	spawn_queue.sort_custom(func(a, b): return a.tick < b.tick)
	wave_end_tick = end_tick
	event.emit("wave", {"number": wave})
	event.emit("sound", {"id": "GUINextWaveIncoming"})

func step() -> void:
	if paused or not notices.is_empty() or result != "": return
	tick += 1
	for power: String in cooldowns: cooldowns[power] = maxi(0, cooldowns[power] - 1)
	while not spawn_queue.is_empty() and spawn_queue[0].tick <= tick:
		var spawn: Dictionary = spawn_queue.pop_front()
		_spawn_enemy(spawn.type, spawn.subpath)
	if wave > 0 and spawn_queue.is_empty() and next_wave_tick < 0 and wave < 7:
		next_wave_tick = wave_end_tick + int(data.waves.groups[wave].interval)
		event.emit("sound", {"id": "GUINextWaveReady"})
	if next_wave_tick >= 0 and tick >= next_wave_tick: _start_wave(false)
	if not notices.is_empty(): return
	_decals_step()
	for tower: Dictionary in towers: _tower_step(tower)
	for soldier: Dictionary in soldiers: _soldier_step(soldier)
	for enemy: Dictionary in enemies: _enemy_step(enemy)
	for bullet: Dictionary in projectiles: _bullet_step(bullet)
	projectiles = projectiles.filter(func(p): return not p.done)
	enemies = enemies.filter(func(e): return e.hp > 0 or tick - e.dead_at < frames(templates[e.template].health.dead_lifetime))
	soldiers = soldiers.filter(func(s): return s.hp > 0 or tick - s.dead_at < 60)
	effects = effects.filter(func(e): return tick - e.at < e.duration)
	if lives <= 0: _finish("defeat")
	elif wave == 7 and spawn_queue.is_empty() and enemies.all(func(e): return e.hp <= 0): _finish("victory")

func _finish(value: String) -> void:
	if result != "": return
	result = value; event.emit("finished", {"result": result})
	event.emit("sound", {"id": "GUIWinStars" if result == "victory" else "GUILooseLife"})

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

func _spawn_enemy(type: String, subpath: int = -1) -> Dictionary:
	var t: Dictionary = templates[type]
	if subpath < 0: subpath = rng.randi_range(0, 2)
	var hp := floori(float(t.health.hp_max) * float(data.rules.enemy_hp_factor))
	var e := {"id": next_id, "template": type, "hp": float(hp), "max_hp": float(hp), "pos": vec(data.paths.paths[0][subpath][0]), "subpath": subpath, "node": 0, "progress": 0.0, "blocker": 0, "blockers": [], "attack_at": tick, "pending": {}, "state": "walkingDown", "state_at": tick, "dead_at": -1, "flip": false, "last_dir": Vector2.ZERO}
	next_id += 1; enemies.append(e)
	spawn_log.append({"tick": tick, "type": type, "subpath": subpath, "wave": wave})
	return e

func _tower_step(tower: Dictionary) -> void:
	if tower.type == "" or tower.ready > tick: return
	var t: Dictionary = templates["tower_" + tower.type + "_1"]
	if tower.ready == tick:
		event.emit("sound", {"id": t.sound_events.insert})
		add_effect("fx_tower_buy_dust", tower.pos)
	if tower.type == "barrack":
		_barrack_step(tower, t)
		return
	var attack: Dictionary = t.attacks.list[0]
	if not tower.pending.is_empty() and tick >= tower.pending.at:
		var target := unit_by_id(tower.pending.target)
		if tower.type == "engineer" or (not target.is_empty() and target.hp > 0):
			var offset := vec(tower.pending.offset)
			var bullet: Dictionary = templates[attack.bullet].bullet
			var flight := float(bullet.get("flight_time", 1))
			var aim: Vector2 = tower.pending.aim
			if not target.is_empty() and target.hp > 0:
				if not bullet.has("flight_time"): flight = distance(tower.pos, target.pos) / float(bullet.get("max_speed", 300))
				if tower.type == "engineer": aim = _predict(target, flight)
				else:
					aim = target.pos + vec(templates[target.template].unit.hit_offset)
					if bullet.get("predict_target_pos", false) and target.blocker == 0: aim += target.last_dir * 30.0 * flight
			_projectile(attack.bullet, target.get("id", 0), tower.pos + offset, aim, flight)
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
	tower.shot_at = tick; tower.shot_up = target.pos.y > tower.pos.y + float(offset.y)
	tower.attack_at = tick + frames(attack.cooldown)
	if not tower.has("layers"): tower.layers = {}
	for sid in range(1, t.render.sprites.size() + 1):
		var sprite: Dictionary = t.render.sprites[sid - 1]
		if not sprite.get("animated", false): continue
		if tower.type == "archer" and sid != shooter + 3: continue
		var state := "shoot"
		if sprite.has("angles"): state = "shootingUp" if tower.shot_up else "shootingDown"
		var idle := "idleUp" if tower.shot_up else "idleDown"
		tower.layers[sid] = {"state": state, "at": tick, "loop": false, "flip": target.pos.x < tower.pos.x + float(offset.x), "idle": idle if sprite.has("angles") else "idle"}

func _target(point: Vector2, radius: float, unblocked: bool = false) -> Dictionary:
	var best := {}; var progress := -1.0
	for e: Dictionary in enemies:
		if e.hp <= 0 or (unblocked and e.blockers.size() >= 3): continue
		if distance(point, e.pos) <= radius and e.progress > progress:
			best = e; progress = e.progress
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
		var d: Dictionary = templates[decal.template].delayed_play
		if decal.state == d.play_animation:
			var sprite: Dictionary = templates[decal.template].render.sprites[0]
			if tick - decal.state_at >= SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, d.play_animation)):
				decal.state = d.idle_animation; decal.state_at = tick
				decal.next_play = tick + frames(rng.randf_range(d.min_delay, d.max_delay))
		elif tick >= decal.next_play:
			decal.state = d.play_animation; decal.state_at = tick
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
	var points: Array = data.paths.paths[0][e.subpath]
	var remaining := seconds * float(templates[e.template].motion.max_speed) * float(data.rules.enemy_speed_factor)
	var point: Vector2 = e.pos
	for node in range(int(e.node) + 1, points.size()):
		var dest := vec(points[node]); var length := point.distance_to(dest)
		if length >= remaining: return point.move_toward(dest, remaining)
		remaining -= length; point = dest
	return point

func _soldier(type: String, home: String, slot: int, point: Vector2, rally: Vector2) -> Dictionary:
	var t: Dictionary = templates[type]
	var s := {"id": next_id, "template": type, "home": home, "slot": slot, "pos": point, "dest": _formation(rally, slot), "hp": float(t.health.hp_max), "max_hp": float(t.health.hp_max), "target": 0, "attack_at": tick, "pending": {}, "state": "idle", "state_at": tick, "dead_at": -1, "last_hit": tick, "regen_at": tick, "born_at": tick, "expires": -1, "flip": false, "variant": rng.randi_range(1, 3)}
	s.rallying = true
	var names: Array = data.ui.unit_names.get(type, [])
	if not names.is_empty(): s.display_name = names[rng.randi_range(0, names.size() - 1)]
	if type == "re_farmer": s.portrait = "info_portraits_soldiers_%04d" % int(t.info.portrait_idxs[s.variant - 1])
	next_id += 1; soldiers.append(s); return s

func _formation(point: Vector2, slot: int) -> Vector2:
	var angle := slot * TAU / 3.0 - PI / 2.0
	return point + Vector2(cos(angle), sin(angle) * 0.7) * float(templates.tower_barrack_1.barrack.rally_radius)

func _soldier_step(s: Dictionary) -> void:
	if s.hp <= 0: return
	if s.expires >= 0 and tick >= s.expires: _retire(s); return
	var t: Dictionary = templates[s.template]
	# y_soldier_new_rally moves directly and suppresses interception until arrival.
	if s.rallying:
		s.flip = s.dest.x < s.pos.x
		s.pos = s.pos.move_toward(s.dest, t.motion.max_speed * STEP)
		_state(s, "running")
		if s.pos.is_equal_approx(s.dest): s.rallying = false; _state(s, "idle")
		return
	var target := unit_by_id(s.target)
	if target.is_empty() or target.hp <= 0 or not s.id in target.blockers:
		s.target = 0; s.pending = {}
		target = _target(s.dest, float(t.melee.range), true)
		if not target.is_empty() and distance(s.pos, target.pos) < float(t.melee.range):
			s.target = target.id; target.blockers.append(s.id); target.blocker = target.blockers[0]
	if not target.is_empty() and s.target != 0:
		var delta: Vector2 = target.pos - s.pos
		s.flip = delta.x < 0
		if distance(s.pos, target.pos) > 20:
			s.pos = s.pos.move_toward(target.pos + Vector2(-16 if delta.x > 0 else 16, 0), t.motion.max_speed * STEP)
			_state(s, "running")
		else:
			_melee(s, target, t)
	else:
		if s.pos.distance_to(s.dest) > 2:
			s.flip = s.dest.x < s.pos.x
			s.pos = s.pos.move_toward(s.dest, t.motion.max_speed * STEP); _state(s, "running")
		else:
			_state(s, "idle")
			if tick - s.last_hit >= frames(float(t.regen.last_hit_standoff_time)) and tick >= s.regen_at:
				s.hp = minf(s.max_hp, s.hp + s.max_hp * float(data.rules.soldier_regen_factor)); s.regen_at = tick + frames(t.regen.cooldown)

func _enemy_step(e: Dictionary) -> void:
	if e.hp <= 0: return
	var t: Dictionary = templates[e.template]
	if e.blocker != 0:
		var s := unit_by_id(e.blocker)
		if s.is_empty() or s.hp <= 0 or s.target != e.id: e.blocker = 0; e.pending = {}
		else:
			e.flip = s.pos.x < e.pos.x
			if distance(e.pos, s.pos) <= 24: _melee(e, s, t)
			else: _state(e, "idle")
			return
	var points: Array = data.paths.paths[0][e.subpath]
	var remaining := float(t.motion.max_speed) * float(data.rules.enemy_speed_factor) * STEP
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
	if not attacker.pending.is_empty() and tick >= attacker.pending.at:
		if target.hp > 0: damage(target, float(rng.randi_range(int(attack.damage_min), int(attack.damage_max))), int(attack.damage_type))
		attacker.pending = {}
	if tick >= attacker.attack_at:
		attacker.attack_at = tick + frames(attack.cooldown)
		attacker.pending = {"at": tick + frames(attack.hit_time)}
		_state(attacker, "attack", true)
		if attack.has("sound"): event.emit("sound", {"id": attack.sound})
	elif tick - attacker.state_at > frames(attack.cooldown) - 1: _state(attacker, "idle")

func _state(unit: Dictionary, state: String, restart: bool = false) -> void:
	if unit.state != state or restart: unit.state = state; unit.state_at = tick

func _unblock(unit: Dictionary) -> void:
	if unit.has("target") and unit.target != 0:
		var enemy := unit_by_id(unit.target)
		if not enemy.is_empty():
			enemy.blockers.erase(unit.id); enemy.blocker = 0 if enemy.blockers.is_empty() else enemy.blockers[0]; enemy.pending = {}
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
	var armor: float = t.health.magic_armor if type == 4 else (t.health.armor if type == 2 or type == 8 else 0.0)
	# Frozen Dove all/utils.lua U.calc_protection, including its explosion curve.
	if type == 8: armor *= 0.2 * armor + 0.4
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
	projectiles.append(b)
	var sounds: Dictionary = templates[type].get("sound_events", {})
	if sounds.has("insert"): event.emit("sound", {"id": sounds.insert})

func _bullet_step(p: Dictionary) -> void:
	var b: Dictionary = templates[p.template].bullet
	var target := unit_by_id(p.target)
	var ratio := clampf(float(tick - p.at) / p.duration, 0, 1)
	if p.template == "bolt_1" or p.template == "power_fireball":
		if p.template == "bolt_1" and not target.is_empty() and target.hp > 0: p.to = target.pos + vec(templates[target.template].unit.hit_offset)
		p.pos = p.from.lerp(p.to, ratio)
		p.rotation = (p.to - p.from).angle()
	else:
		p.merge(Projectile.sample(p, b, (tick - p.at) / 30.0), true)
	if ratio < 1: return
	p.done = true
	if float(b.damage_radius) > 0:
		for e: Dictionary in enemies:
			if e.hp > 0 and distance(p.to, e.pos) <= float(b.damage_radius):
				var amount: float = rng.randi_range(int(b.damage_min), int(b.damage_max))
				if p.template == "bomb":
					var delta: Vector2 = e.pos - p.to
					var angle := delta.angle()
					var ellipse_radius := Vector2(cos(angle), 0.7 * sin(angle)).length() * float(b.damage_radius)
					amount = lerpf(float(b.damage_max), float(b.damage_min), clampf(delta.length() / ellipse_radius, 0, 1))
				damage(e, amount, int(b.damage_type))
		add_effect(str(b.get("hit_fx", "")), p.to)
		add_effect(str(b.get("hit_decal", "")), p.to)
	elif not target.is_empty() and target.hp > 0:
		var hit: Vector2 = target.pos + vec(templates[target.template].unit.hit_offset)
		if p.template == "bolt_1" or p.to.distance_to(hit) < float(b.get("hit_distance", 22)) * 1.2:
			damage(target, rng.randi_range(int(b.damage_min), int(b.damage_max)), int(b.damage_type))
			add_effect(str(b.get("hit_fx", "")), hit)
			add_effect(str(b.get("hit_blood_fx", "")), hit, {"rotation": p.rotation})
	var sounds: Dictionary = templates[p.template].get("sound_events", {})
	if sounds.has("hit"): event.emit("sound", {"id": sounds.hit})
