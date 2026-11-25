extends RefCounted
## eb_veznan, mod_veznan_tower, veznan_portal, veznan_souls_aura, veznan_soul and decal_s12_shoutbox.
## Owned per simulator instance; no cross-battle mutable state.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")

var portals: Array = []
var tower_locks: Array = []
var souls_auras: Array = []
var souls: Array = []
var soul_particles: Array = []
var shoutboxes: Array = []
var white_circles: Array = []

func reset(sim) -> void:
	portals.clear()
	tower_locks.clear()
	souls_auras.clear()
	souls.clear()
	soul_particles.clear()
	shoutboxes.clear()
	white_circles.clear()
	for e: Dictionary in sim.data.layout.entities_list:
		if e.template != "veznan_portal": continue
		var out_nodes: Array = e.get("out_nodes", [101])
		portals.append({
			"portal_idx": int(e.get("portal_idx", 1)),
			"pos": sim.vec(e.pos),
			"pi": int(e.get("pi", sim.templates.veznan_portal.get("pi", 1))),
			"out_node": int(out_nodes[0]) - 1,
			"phase": "idle",
			"state": "idle",
			"at": sim.tick,
			"spawn_signal": false,
			"queue": [],
			"next_at": 0,
			"end_at": 0,
		})

func spawn_in_castle(sim) -> Dictionary:
	var t: Dictionary = sim.templates.eb_veznan
	var hp: float = _resolve_veznan_hp(sim, t)
	var pos: Vector2 = sim.vec(t.pos_castle)
	var e := {
		"id": sim.next_id,
		"template": "eb_veznan",
		"hp": hp,
		"max_hp": hp,
		"pos": pos,
		"path": 0,
		"subpath": 0,
		"node": 0,
		"progress": 0.0,
		"blocker": 0,
		"blockers": [],
		"attack_at": sim.tick,
		"pending": {},
		"state": "idleDown",
		"state_at": sim.tick,
		"dead_at": -1,
		"flip": false,
		"last_dir": Vector2.ZERO,
		"heal_at": sim.tick,
		"casting": {},
		"ignore_damage": true,
		"health_bar_hidden": true,
		"can_select": true,
		"source_corpse": true,
		"playback_loop": true,
		"vis": t.vis.duplicate(true),
		"boss": {"death_handled": false},
	}
	sim.next_id += 1
	sim.enemies.append(e)
	initialize(sim, e)
	return e

static func _resolve_veznan_hp(sim, t: Dictionary) -> float:
	var raw: Variant = t.health.hp_max
	if raw is Array:
		var idx := clampi(int(sim.data.level.get("difficulty", 2)) - 1, 0, raw.size() - 1)
		return float(raw[idx])
	return float(floori(float(raw) * float(sim.data.rules.enemy_hp_factor)))

static func initialize(sim, e: Dictionary) -> void:
	var t: Dictionary = sim.templates[e.template]
	if not e.has("boss"): e.boss = {"death_handled": false}
	var taunts: Dictionary = t.taunts
	e.veznan = {
		"phase": "wait_welcome",
		"phase_signal": "",
		"initial_hp": float(e.max_hp),
		"at": sim.tick,
		"wait_until": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, 1.0),
		"welcome_idx": 0,
		"last_wave": 0,
		"last_lives": sim.lives,
		"taunt_ts": sim.tick,
		"taunt_cooldown": sim.rng.randf_range(float(taunts.delay_min), float(taunts.delay_max)),
		"ba": {"disabled": true, "cooldown": float(t.timed_attacks.list[0].cooldown), "count": 0, "ts": sim.tick, "animation": str(t.timed_attacks.list[0].animation)},
		"pa": {"disabled": true, "cooldown": float(t.timed_attacks.list[1].cooldown), "max_count": 0, "count": 0, "portals": [0, 0, 0], "ts": sim.tick, "animation": str(t.timed_attacks.list[1].animation)},
		"sda": {"disabled": false, "ts": sim.tick},
		"action": {},
		"melee_job": {},
		"melee_ts": [0, 0],
		"demon_mode": false,
		"death_step": "",
		"death_at": 0,
		"souls_aura_ref": null,
	}

static func anim_duration(sim, e: Dictionary, state_name: String) -> int:
	var t: Dictionary = sim.templates[e.template]
	var sprite: Dictionary = t.render.sprites[0].duplicate()
	if e.get("prefix", "") != "": sprite.prefix = e.prefix
	return Anim.duration(sim.animations, Anim.key(sprite, state_name))

static func _play(sim, e: Dictionary, state_name: String, loop: bool, restart: bool = true) -> void:
	e.playback_loop = loop
	sim._state(e, state_name, restart)

static func lethal(sim, e: Dictionary, amount: float, type: int) -> bool:
	if not e.has("veznan"): return false
	var v: Dictionary = e.veznan
	if v.phase != "battle" and v.phase != "demon": return false
	if sim.predict_damage(e, amount, type) >= e.hp:
		v.phase_signal = "lethal"
		return true
	return false

func _show_taunt(sim, e: Dictionary, set_name: String, idx: int = -1) -> int:
	var t: Dictionary = sim.templates[e.template]
	var taunts: Dictionary = t.taunts
	var sets: Dictionary = taunts.sets
	if not sets.has(set_name): return 0
	var s: Dictionary = sets[set_name]
	var chosen := idx
	if chosen <= 0:
		var start_idx := int(s.get("start_idx", 1))
		var end_idx := int(s.get("end_idx", start_idx))
		chosen = sim.rng.randi_range(start_idx, end_idx)
	var key := str(s.format) % chosen
	var text_value: String = sim.data.ui.strings.get(key, key)
	var duration := float(taunts.get("duration", 4.0))
	var pos: Vector2 = sim.vec(s.get("pos", taunts.pos)) + sim.vec(s.get("offset", taunts.get("offset", {"x": 0, "y": 0})))
	shoutboxes.append({
		"template": str(s.get("decal_name", taunts.decal_name)),
		"key": key,
		"text": text_value,
		"pos": pos,
		"at": sim.tick,
		"duration": duration,
		"end_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, duration),
	})
	sim.event.emit("veznan_taunt", {"set": set_name, "index": chosen, "key": key, "text": text_value})
	return sim.source_unconditional_wait_ticks(sim.tick, duration)

func _ready_magic(sim, e: Dictionary, state_dict: Dictionary, cooldown_override: float = -1.0) -> bool:
	if state_dict.get("disabled", false): return false
	if int(e.get("silence_count", 0)) > 0: return false
	var cd := cooldown_override if cooldown_override >= 0.0 else float(state_dict.cooldown)
	return float(sim.tick - int(state_dict.ts)) / 30.0 > cd

func _eligible_towers(sim) -> Array:
	var out: Array = []
	for tower: Dictionary in sim.towers:
		if tower.type == "" or tower.ready > sim.tick: continue
		if not sim.tower_template(tower).tower.get("can_be_mod", false): continue
		if tower_locks.any(func(lock): return lock.tower == tower.id): continue
		out.append(tower)
	return out

func _soul_drain_targets(sim, e: Dictionary, sda: Dictionary) -> Array:
	var out: Array = []
	for s: Dictionary in sim.soldiers:
		if s.hp <= 0: continue
		if "elemental" in str(s.template).to_lower(): continue
		if not Targets.matches(sim, s, sda): continue
		if sim.distance(e.pos, s.pos) <= float(sda.range):
			out.append(s)
	return out

func _spawn_soul_to_veznan(sim, e: Dictionary, target: Dictionary, sda: Dictionary) -> float:
	var mo: Vector2 = sim.vec(sim.templates[target.template].unit.get("mod_offset", {"x": 0, "y": 0}))
	var from: Vector2 = target.pos + mo
	var hand_sign: float = -1.0 if e.flip else 1.0
	var hand: Vector2 = e.pos + Vector2(float(sda.soul_hand_offset.x) * hand_sign, float(sda.soul_hand_offset.y))
	var delta: Vector2 = hand - from
	var dist: float = delta.length()
	var speed: float = maxf(1.0, float(sda.soul_speed))
	var duration: float = dist / speed
	souls.append({
		"template": str(sda.soul_effect),
		"pos": from,
		"angle": delta.angle(),
		"angle_var": 0.0,
		"inc": 0.0,
		"min_angle": 0.0,
		"max_angle": 0.0,
		"speed": speed,
		"soul_phase": 1.0,
		"at": sim.tick,
		"end_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, duration),
		"emit_acc": 0.0,
	})
	return duration

func lock_tower(sim, tower: Dictionary, source_id: int) -> void:
	var t: Dictionary = sim.templates.mod_veznan_tower
	var start_len := Anim.duration(sim.animations, Anim.key(t.render.sprites[0], "start"))
	tower_locks.append({
		"tower": tower.id,
		"source": source_id,
		"phase": "start",
		"state": "start",
		"at": sim.tick,
		"end_at": sim.tick + start_len,
		"clicks": 0,
		"clicked": false,
		"blocked_inc": false,
		"hold_until": 0,
	})

func tower_click(_sim, id: String) -> bool:
	var consumed := false
	for lock: Dictionary in tower_locks:
		if lock.tower == id and lock.phase == "preHold":
			lock.clicked = true
			consumed = true
	return consumed

func step_tower_locks(sim) -> void:
	var t: Dictionary = sim.templates.get("mod_veznan_tower", {})
	if t.is_empty(): return
	for lock: Dictionary in tower_locks.duplicate():
		var tower: Dictionary = sim.tower_by_id(lock.tower)
		if tower.is_empty():
			tower_locks.erase(lock)
			continue
		if lock.phase == "start":
			if sim.tick >= lock.end_at:
				lock.phase = "preHold"
				lock.state = "preHold"
				lock.at = sim.tick
				lock.hold_until = sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(t.click_time))
				tower.block_count = int(tower.get("block_count", 0)) + 1
				tower.blocked = true
				lock.blocked_inc = true
		elif lock.phase == "preHold":
			if lock.clicked:
				lock.clicked = false
				lock.clicks += 1
				sim.event.emit("sound", {"id": str(t.sound_click)})
				if lock.clicks >= int(t.required_clicks):
					_begin_lock_remove(sim, lock, t)
					continue
			if sim.tick >= lock.hold_until:
				lock.phase = "hold"
				lock.state = "hold"
				lock.at = sim.tick
				lock.hold_until = sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(t.duration))
				sim.event.emit("sound", {"id": str(t.sound_blocked)})
		elif lock.phase == "hold":
			if sim.tick >= lock.hold_until:
				_begin_lock_remove(sim, lock, t)
		elif lock.phase == "remove":
			if sim.tick >= lock.end_at:
				if lock.blocked_inc:
					tower.block_count = maxi(0, int(tower.get("block_count", 1)) - 1)
					tower.blocked = tower.block_count > 0
				tower_locks.erase(lock)

func _begin_lock_remove(sim, lock: Dictionary, t: Dictionary) -> void:
	lock.phase = "remove"
	lock.state = "remove"
	lock.at = sim.tick
	lock.end_at = sim.tick + Anim.duration(sim.animations, Anim.key(t.render.sprites[0], "remove"))
	sim.event.emit("sound", {"id": str(t.sound_released)})

func step_portals(sim) -> void:
	var t: Dictionary = sim.templates.get("veznan_portal", {})
	if t.is_empty(): return
	var start_len := Anim.duration(sim.animations, Anim.key(t.render.sprites[0], "start"))
	var active_len := Anim.duration(sim.animations, Anim.key(t.render.sprites[0], "active"))
	var end_len := Anim.duration(sim.animations, Anim.key(t.render.sprites[0], "end"))
	for p: Dictionary in portals:
		if p.phase == "idle":
			if p.spawn_signal:
				p.phase = "start"
				p.state = "start"
				p.at = sim.tick
				p.end_at = sim.tick + start_len
		elif p.phase == "start":
			if sim.tick >= p.end_at:
				var groups: Array = t.spawn_groups[clampi(int(p.portal_idx) - 1, 0, t.spawn_groups.size() - 1)]
				var roll: float = sim.rng.randf()
				var chosen: Array = groups[-1][1]
				for entry: Array in groups:
					if roll <= float(entry[0]):
						chosen = entry[1]
						break
				p.queue.clear()
				for row: Array in chosen:
					var lo := int(row[0])
					var hi := int(row[1])
					var count: int = lo if lo == hi else int(sim.rng.randi_range(lo, hi))
					for _i in count:
						p.queue.append(str(row[2]))
				p.phase = "active"
				p.state = "active"
				p.at = sim.tick
				p.next_at = sim.tick
		elif p.phase == "active":
			if not p.queue.is_empty() and sim.tick >= p.next_at:
				var enemy_type: String = p.queue.pop_front()
				var spawned: Dictionary = sim._spawn_enemy(enemy_type, sim.rng.randi_range(0, 2), int(p.pi) - 1, "veznan_portal")
				spawned.pos = p.pos
				spawned.node = int(p.out_node)
				spawned.progress = float(spawned.node)
				if t.has("fx_out"):
					var fx_t: Dictionary = sim.templates.get(str(t.fx_out), {})
					var size_names: Array = fx_t.get("render", {}).get("sprites", [{}])[0].get("size_names", [])
					var unit_size := int(sim.templates[enemy_type].get("unit", {}).get("size", 1))
					var fx_state := str(size_names[clampi(unit_size - 1, 0, size_names.size() - 1)]) if not size_names.is_empty() else ""
					sim.add_effect(str(t.fx_out), p.pos, {"state": fx_state})
				p.next_at = sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(t.spawn_interval))
			elif p.queue.is_empty() and sim.tick >= p.next_at and (sim.tick - p.at) >= active_len:
				p.phase = "end"
				p.state = "end"
				p.at = sim.tick
				p.end_at = sim.tick + end_len
		elif p.phase == "end":
			if sim.tick >= p.end_at:
				p.phase = "idle"
				p.state = "idle"
				p.at = sim.tick
				p.spawn_signal = false

func step_souls(sim) -> void:
	for box: Dictionary in shoutboxes.duplicate():
		if sim.tick >= box.end_at:
			shoutboxes.erase(box)
	for a: Dictionary in souls_auras.duplicate():
		if a.interrupt or a.emitted >= a.count:
			souls_auras.erase(a)
			continue
		if sim.tick >= a.next_at:
			a.emitted += 1
			var soul_t: Dictionary = sim.templates[a.entity]
			var angle: float = sim.rng.randf_range(float(a.angles[0]), float(a.angles[1]))
			var speed: float = sim.rng.randf_range(float(soul_t.speed[0]), float(soul_t.speed[1]))
			var angle_var_step := float(soul_t.angle_variation)
			var inc := angle_var_step if sim.rng.randf() > 0.5 else -angle_var_step
			var phase := maxf(0.05, 1.0 - float(a.emitted) / float(a.count))
			souls.append({
				"template": a.entity,
				"pos": a.pos,
				"angle": angle,
				"angle_var": 0.0,
				"inc": inc,
				"min_angle": float(soul_t.min_angle),
				"max_angle": float(soul_t.max_angle),
				"speed": speed,
				"soul_phase": phase,
				"at": sim.tick,
				"end_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(soul_t.duration)),
				"emit_acc": 0.0,
			})
			if a.delay_frames >= 2:
				a.delay_frames -= 1
			a.next_at = sim.tick + a.delay_frames
	var ps_t: Dictionary = sim.templates.get("ps_veznan_soul", {}).get("particle_system", {})
	for s: Dictionary in souls.duplicate():
		if sim.tick >= s.end_at:
			souls.erase(s)
			continue
		var a_cur: float = float(s.angle) + float(s.angle_var)
		s.pos += Vector2.from_angle(a_cur) * float(s.speed) * sim.STEP
		s.rotation = a_cur
		s.angle_var = float(s.angle_var) + float(s.inc)
		if s.angle_var >= float(s.max_angle): s.inc = -absf(float(s.inc))
		elif s.angle_var <= float(s.min_angle): s.inc = absf(float(s.inc))
		if not ps_t.is_empty():
			s.emit_acc = float(s.emit_acc) + float(ps_t.emission_rate) * sim.STEP
			while s.emit_acc >= 1.0:
				s.emit_acc -= 1.0
				var life: float = float(sim.rng.randf_range(float(ps_t.particle_lifetime[0]), float(ps_t.particle_lifetime[1]))) * float(s.soul_phase)
				var life_ticks: int = maxi(1, roundi(life * 30.0))
				var spread: Vector2 = sim.vec(ps_t.get("emission_spread", {"x": 0, "y": 0}))
				var sv: Array = ps_t.get("scale_var", [1.0, 1.0])
				soul_particles.append({
					"frame": str(ps_t.name),
					"pos": s.pos + Vector2(sim.rng.randf_range(-spread.x, spread.x), sim.rng.randf_range(-spread.y, spread.y)),
					"at": sim.tick,
					"duration": life_ticks,
					"rotation": sim.rng.randf_range(-PI, PI),
					"base_scale": sim.rng.randf_range(float(sv[0]), float(sv[1])),
					"scales_x": ps_t.get("scales_x", [1.0, 0.3]),
					"scales_y": ps_t.get("scales_y", [1.0, 0.3]),
					"alphas": ps_t.get("alphas", [255, 0]),
				})
	for p: Dictionary in soul_particles.duplicate():
		if sim.tick - int(p.at) >= int(p.duration):
			soul_particles.erase(p)

func _kill_all_enemies(sim, veznan_id: int) -> void:
	for other: Dictionary in sim.enemies:
		if other.id == veznan_id or other.hp <= 0: continue
		var ot: Dictionary = sim.templates[other.template]
		if int(ot.health.get("immune_to", 0)) == 4294967295: continue
		other.gold_override = 0
		sim.damage(other, other.hp, 1)
	for item: Dictionary in sim.spawners: item.interrupted = true
	for p: Dictionary in portals:
		p.queue.clear()
		p.spawn_signal = false
	sim.pending_entities.clear()

func _start_block_towers(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var ba_t: Dictionary = t.timed_attacks.list[0]
	var candidates := _eligible_towers(sim)
	if candidates.is_empty():
		v.ba.ts = sim.tick - sim.frames(float(v.ba.cooldown)) + sim.frames(0.5)
		return false
	var shuffled := candidates.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = sim.rng.randi_range(0, i)
		var tmp: Variant = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = tmp
	var picked: Array = shuffled.slice(0, maxi(0, int(v.ba.count)))
	if not picked.is_empty():
		e.flip = picked[0].pos.x < e.pos.x
	var anim_name := str(v.ba.animation)
	_play(sim, e, anim_name, false)
	var anim_end: int = int(sim.tick) + anim_duration(sim, e, anim_name)
	var dur_end: int = int(sim.tick) + int(sim.source_unconditional_wait_ticks(sim.tick, float(ba_t.attack_duration)))
	v.action = {
		"kind": "block_towers",
		"hit": false,
		"hit_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(ba_t.hit_time)),
		"end_at": maxi(anim_end, dur_end),
		"towers": picked.map(func(tw): return tw.id),
	}
	return true

func _start_portal(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var pa_t: Dictionary = t.timed_attacks.list[1]
	var anim_name := str(v.pa.animation)
	_play(sim, e, anim_name, false)
	var anim_end: int = int(sim.tick) + anim_duration(sim, e, anim_name)
	var dur_end: int = int(sim.tick) + int(sim.source_unconditional_wait_ticks(sim.tick, float(pa_t.attack_duration)))
	v.action = {
		"kind": "portal",
		"hit": false,
		"hit_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(pa_t.hit_time)),
		"end_at": maxi(anim_end, dur_end),
	}
	return true

func _start_soul_drain(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var sda: Dictionary = t.timed_attacks.list[2]
	if _soul_drain_targets(sim, e, sda).is_empty():
		v.sda.ts = sim.tick - sim.frames(float(sda.cooldown)) + sim.frames(0.2)
		return false
	_play(sim, e, str(sda.animation_start), false)
	v.action = {
		"kind": "soul_drain",
		"sub": "windup",
		"started": sim.tick,
		"kill_start_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(sda.kill_start_time)),
		"loop_start_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(sda.loop_start_time)),
		"kill_end_at": sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(sda.kill_end_time)),
		"hold_started": false,
		"last_arrival_at": sim.tick,
		"drained_ids": {},
		"end_at": 0,
	}
	return true

func _step_action(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var act: Dictionary = v.action
	if act.is_empty(): return false
	match str(act.kind):
		"taunt":
			if sim.tick >= int(act.end_at):
				v.action = {}
				if v.phase == "castle" or v.phase == "welcome":
					_play(sim, e, "idleDown", true)
				return false
			return true
		"block_towers":
			var ba_t: Dictionary = t.timed_attacks.list[0]
			if not act.hit and sim.tick >= int(act.hit_at):
				act.hit = true
				sim.event.emit("sound", {"id": str(ba_t.sound)})
				for id: String in act.towers:
					var tw: Dictionary = sim.tower_by_id(id)
					if not tw.is_empty(): lock_tower(sim, tw, e.id)
			if sim.tick >= int(act.end_at):
				v.ba.ts = sim.tick
				v.action = {}
				if v.phase == "castle": _play(sim, e, "idleDown", true)
				return false
			return true
		"portal":
			var pa_t: Dictionary = t.timed_attacks.list[1]
			if not act.hit and sim.tick >= int(act.hit_at):
				act.hit = true
				sim.event.emit("sound", {"id": str(pa_t.sound)})
				v.pa.count = int(v.pa.count) + 1
				var mask: Array = v.pa.portals
				for p: Dictionary in portals:
					var idx := int(p.portal_idx) - 1
					if idx >= 0 and idx < mask.size() and int(mask[idx]) == 1:
						p.spawn_signal = true
			if sim.tick >= int(act.end_at):
				v.pa.ts = sim.tick
				v.action = {}
				if v.phase == "castle": _play(sim, e, "idleDown", true)
				return false
			return true
		"soul_drain":
			var sda: Dictionary = t.timed_attacks.list[2]
			if int(e.get("stun_count", 0)) > 0 or v.phase_signal != "":
				v.sda.ts = sim.tick - sim.frames(float(sda.cooldown)) + sim.frames(0.2)
				v.action = {}
				return false
			if act.sub == "windup":
				if sim.tick >= int(act.kill_start_at):
					sim.event.emit("sound", {"id": str(sda.sound)})
					act.sub = "drain"
			if act.sub == "drain":
				if not act.hold_started and sim.tick >= int(act.loop_start_at):
					act.hold_started = true
					_play(sim, e, str(sda.animation_hold), true)
				for target: Dictionary in _soul_drain_targets(sim, e, sda):
					if act.drained_ids.has(target.id): continue
					act.drained_ids[target.id] = true
					var soul_dur := _spawn_soul_to_veznan(sim, e, target, sda)
					act.last_arrival_at = maxi(int(act.last_arrival_at), sim.tick + sim.source_unconditional_wait_ticks(sim.tick, soul_dur))
					sim.damage(target, float(target.max_hp) + 1.0, 8192 | 4096, e.id)
					e.hp = minf(e.max_hp, e.hp + e.max_hp * float(sda.heal_hp_factor))
				if sim.tick >= int(act.kill_end_at):
					act.sub = "wait_souls"
			if act.sub == "wait_souls":
				if sim.tick >= maxi(int(act.kill_end_at), int(act.last_arrival_at)):
					act.sub = "end"
					_play(sim, e, str(sda.animation_end), false)
					act.end_at = sim.tick + anim_duration(sim, e, str(sda.animation_end))
			if act.sub == "end":
				if sim.tick >= int(act.end_at):
					v.sda.ts = sim.tick
					v.action = {}
					if v.phase == "castle": _play(sim, e, "idleDown", true)
					return false
			return true
	return false

func _start_melee(sim, e: Dictionary, target: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var idx := 1 if v.demon_mode else 0
	var attack: Dictionary = t.melee.attacks[idx]
	if float(sim.tick - int(v.melee_ts[idx])) / 30.0 < float(attack.cooldown):
		_play(sim, e, "idle", true, false)
		return true
	if not Targets.matches(sim, target, attack):
		return false
	v.melee_ts[idx] = sim.tick
	e.flip = target.pos.x < e.pos.x
	var sign_x := -1.0 if e.flip else 1.0
	var point: Vector2 = e.pos + sim.vec(attack.get("hit_offset", {"x": 0, "y": 0})) * Vector2(sign_x, 1.0)
	var hit_ticks: Array = []
	if attack.has("hit_times"):
		for ht: float in attack.hit_times:
			hit_ticks.append(sim.tick + sim.frames(float(ht)))
	else:
		hit_ticks.append(sim.tick + sim.frames(float(attack.hit_time)))
	_play(sim, e, str(attack.animation), false)
	if attack.has("sound") and str(attack.sound) != "":
		sim.event.emit("sound", {"id": str(attack.sound)})
	v.melee_job = {
		"idx": idx,
		"point": point,
		"flip": e.flip,
		"hit_ticks": hit_ticks,
		"hit_cursor": 0,
		"fx_spawned": false,
		"end_at": sim.tick + anim_duration(sim, e, str(attack.animation)),
	}
	return true

func _step_melee(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	var job: Dictionary = v.melee_job
	if job.is_empty(): return false
	if int(e.get("stun_count", 0)) > 0 or v.phase_signal != "":
		v.melee_job = {}
		return false
	var attack: Dictionary = t.melee.attacks[int(job.idx)]
	var cursor: int = int(job.hit_cursor)
	while cursor < job.hit_ticks.size() and sim.tick >= int(job.hit_ticks[cursor]):
		cursor += 1
		job.hit_cursor = cursor
		if attack.has("sound_hit") and str(attack.sound_hit) != "":
			sim.event.emit("sound", {"id": str(attack.sound_hit)})
		var victims := Targets.soldiers(sim, job.point, {"max_range": attack.damage_radius, "vis_flags": attack.get("damage_flags", 0), "vis_bans": attack.get("damage_bans", 0)})
		for victim: Dictionary in victims.slice(0, int(attack.get("count", victims.size()))):
			var dmg: float = float(sim.rng.randi_range(int(attack.damage_min), int(attack.damage_max))) * float(sim.attack_factor(e))
			sim.damage(victim, dmg, int(attack.damage_type), e.id)
		if attack.has("hit_decal") and str(attack.hit_decal) != "":
			sim.add_effect(str(attack.hit_decal), job.point)
		if attack.has("hit_fx") and str(attack.hit_fx) != "" and (not attack.get("hit_fx_once", false) or not job.fx_spawned):
			job.fx_spawned = true
			var fx_sign := -1.0 if job.flip else 1.0
			var fx_off: Vector2 = sim.vec(attack.get("hit_fx_offset", {"x": 0, "y": 0})) * Vector2(fx_sign, 1.0)
			sim.add_effect(str(attack.hit_fx), e.pos + fx_off, {"flip": job.flip if attack.get("hit_fx_flip", false) else false})
	if sim.tick >= int(job.end_at):
		v.melee_job = {}
		_play(sim, e, "idle", true)
		return false
	return true

func step(sim, e: Dictionary, t: Dictionary) -> bool:
	var v: Dictionary = e.veznan
	if v.phase == "wait_welcome":
		if v.phase_signal == "welcome" or sim.tick >= int(v.wait_until):
			v.phase = "welcome"
			v.phase_signal = ""
			v.welcome_idx = 0
			var delays: Array = t.taunts.sets.welcome.delays
			v.wait_until = sim.tick + sim.source_unconditional_wait_ticks(sim.tick, float(delays[0]))
		return true

	if v.phase == "welcome":
		if _step_action(sim, e, t): return true
		var delays: Array = t.taunts.sets.welcome.delays
		if sim.wave >= 1:
			_play(sim, e, "laugh", true)
			var dur_ticks := _show_taunt(sim, e, "welcome", 5)
			v.action = {"kind": "taunt", "end_at": sim.tick + dur_ticks}
			v.phase = "castle"
			v.ba.ts = sim.tick
			v.pa.ts = sim.tick
			v.sda.ts = sim.tick
			v.taunt_ts = sim.tick
			v.last_lives = sim.lives
			v.last_wave = 0
			v.phase_signal = ""
			return true
		if int(v.welcome_idx) < delays.size() and sim.tick >= int(v.wait_until):
			v.welcome_idx = int(v.welcome_idx) + 1
			_play(sim, e, "laugh", true)
			var dur_ticks := _show_taunt(sim, e, "welcome", int(v.welcome_idx))
			v.action = {"kind": "taunt", "end_at": sim.tick + dur_ticks}
			if int(v.welcome_idx) < delays.size():
				v.wait_until = sim.tick + dur_ticks + sim.source_unconditional_wait_ticks(sim.tick + dur_ticks, float(delays[int(v.welcome_idx)]))
		return true

	if v.phase == "castle":
		if _step_action(sim, e, t): return true
		if v.phase_signal == "descend":
			v.phase = "pre_battle"
			v.phase_signal = ""
			v.pa.cooldown = float(t.battle.pa_cooldown)
			v.pa.max_count = int(t.battle.pa_max_count)
			v.pa.animation = str(t.battle.pa_animation)
			v.ba.animation = str(t.battle.ba_animation)
			v.pre_step = "wait24"
			v.pre_start = sim.tick
			v.wait_until = sim.tick + 24
			return true
		if sim.wave != int(v.last_wave):
			v.last_wave = sim.wave
			var ba_data: Variant = t.timed_attacks.list[0].data.get(str(sim.wave), null)
			v.ba.disabled = ba_data == null
			if not v.ba.disabled:
				v.ba.cooldown = float(ba_data[0])
				v.ba.count = int(ba_data[1])
			var pa_data: Variant = t.timed_attacks.list[1].data.get(str(sim.wave), null)
			v.pa.disabled = pa_data == null
			if not v.pa.disabled:
				v.pa.cooldown = float(pa_data[0])
				v.pa.max_count = int(pa_data[1])
				v.pa.portals = pa_data[2].duplicate()
				v.pa.count = 0
		if float(sim.tick - int(v.taunt_ts)) / 30.0 >= float(v.taunt_cooldown):
			var set_name := "damage" if int(v.last_lives) > sim.lives else "castle"
			v.last_lives = sim.lives
			v.taunt_ts = sim.tick
			v.taunt_cooldown = sim.rng.randf_range(float(t.taunts.delay_min), float(t.taunts.delay_max))
			_play(sim, e, "laugh", true)
			var dur_ticks := _show_taunt(sim, e, set_name)
			v.action = {"kind": "taunt", "end_at": sim.tick + dur_ticks}
			return true
		if _ready_magic(sim, e, v.ba):
			if _start_block_towers(sim, e, t): return true
		if _ready_magic(sim, e, v.pa) and int(v.pa.count) < int(v.pa.max_count):
			if _start_portal(sim, e, t): return true
		if _ready_magic(sim, e, v.sda, float(t.timed_attacks.list[2].cooldown)):
			if _start_soul_drain(sim, e, t): return true
		return true

	if v.phase == "pre_battle":
		if v.pre_step == "wait24":
			if sim.tick >= int(v.wait_until):
				_play(sim, e, "laugh", true)
				var dur_ticks := _show_taunt(sim, e, "pre_battle", 30)
				v.pre_step = "taunt"
				v.wait_until = maxi(sim.tick + dur_ticks, int(v.pre_start) + 115)
		elif v.pre_step == "taunt":
			if sim.tick >= int(v.wait_until):
				_play(sim, e, "walkAway", false)
				v.pre_step = "walk_away"
				v.wait_until = sim.tick + anim_duration(sim, e, "walkAway")
		elif v.pre_step == "walk_away":
			if sim.tick >= int(v.wait_until):
				e.path = 0; e.subpath = 0; e.node = 0; e.progress = 0.0
				e.pos = sim.vec(sim.data.paths.paths[0][0][0])
				v.pa.ts = sim.tick; v.ba.ts = sim.tick; v.sda.ts = sim.tick
				e.vis.bans = 0
				e.ignore_damage = false
				e.health_bar_hidden = false
				v.phase_signal = ""
				v.phase = "battle"
				_play(sim, e, "walkingDown", true)
		return true

	if v.phase == "battle":
		if _step_action(sim, e, t): return true
		if _step_melee(sim, e, t): return true
		if v.phase_signal == "lethal":
			_enter_demon_transform(sim, e, t)
			return true
		if int(e.get("stun_count", 0)) > 0:
			_play(sim, e, "idle", true, false)
			return true
		if _ready_magic(sim, e, v.ba):
			if _start_block_towers(sim, e, t): return true
		if _ready_magic(sim, e, v.pa) and int(v.pa.count) < int(v.pa.max_count):
			if _start_portal(sim, e, t): return true
		if _ready_magic(sim, e, v.sda, float(t.timed_attacks.list[2].cooldown)):
			if _start_soul_drain(sim, e, t): return true
		if e.blocker != 0:
			var s: Dictionary = sim.unit_by_id(e.blocker)
			if s.is_empty() or s.hp <= 0 or s.target != e.id:
				e.blocker = 0; e.pending = {}
			elif s.pos.is_equal_approx(sim.melee_slot(s, e)):
				return _start_melee(sim, e, s, t)
			else:
				_play(sim, e, "idle", true, false)
				return true
		return false

	if v.phase == "demon_transform":
		if sim.tick >= int(v.wait_until):
			var d: Dictionary = t.demon
			v.demon_mode = true
			e.max_hp = float(v.initial_hp) * 1.5
			e.hp = e.max_hp
			e.speed_override = float(d.speed)
			e.prefix = str(d.sprites_prefix)
			e.melee_slot_override = sim.vec(d.melee_slot)
			e.health_bar_offset = sim.vec(d.health_bar_offset)
			e.health_bar_scale = float(d.health_bar_scale)
			e.hit_offset_override = sim.vec(d.unit_hit_offset)
			e.mod_offset_override = sim.vec(d.unit_mod_offset)
			e.click_rect_override = d.ui_click_rect
			e.portrait = str(d.info_portrait)
			e.info_portrait = str(d.info_portrait)
			e.health_bar_hidden = false
			e.ignore_damage = false
			e.vis.bans = 0
			v.phase_signal = ""
			v.phase = "demon"
			_play(sim, e, "walkingDown", true)
		return true

	if v.phase == "demon":
		if _step_melee(sim, e, t): return true
		if v.phase_signal == "lethal":
			_enter_death(sim, e, t)
			return true
		if int(e.get("stun_count", 0)) > 0:
			_play(sim, e, "idle", true, false)
			return true
		if e.blocker != 0:
			var s: Dictionary = sim.unit_by_id(e.blocker)
			if s.is_empty() or s.hp <= 0 or s.target != e.id:
				e.blocker = 0; e.pending = {}
			elif s.pos.is_equal_approx(sim.melee_slot(s, e)):
				return _start_melee(sim, e, s, t)
			else:
				_play(sim, e, "idle", true, false)
				return true
		return false

	if v.phase == "death":
		if v.death_step == "death_wait_souls":
			if sim.tick >= int(v.wait_until):
				_kill_all_enemies(sim, e.id)
				var aura_t: Dictionary = sim.templates[str(t.souls_aura)].souls
				var aura := {
					"pos": e.pos + Vector2(0, 14),
					"entity": str(aura_t.entity),
					"angles": aura_t.angles,
					"count": int(aura_t.count),
					"delay_frames": int(aura_t.delay_frames),
					"emitted": 0,
					"next_at": sim.tick,
					"interrupt": false,
				}
				souls_auras.append(aura)
				v.souls_aura_ref = aura
				v.death_step = "death_anim_end"
				v.wait_until = int(v.death_at) + anim_duration(sim, e, "death")
		elif v.death_step == "death_anim_end":
			if sim.tick >= int(v.wait_until):
				_play(sim, e, "deathLoop", true)
				v.death_step = "death_loop"
				v.wait_until = sim.tick + 90
		elif v.death_step == "death_loop":
			if sim.tick >= int(v.wait_until):
				if v.souls_aura_ref != null:
					v.souls_aura_ref.interrupt = true
				_kill_all_enemies(sim, e.id)
				_play(sim, e, "deathEnd", true)
				white_circles.append({
					"template": str(t.white_circle),
					"pos": e.pos + Vector2(6, 12),
					"at": sim.tick,
				})
				v.death_step = "white_circle"
				v.wait_until = sim.tick + 65 + 60
		elif v.death_step == "white_circle":
			if sim.tick >= int(v.wait_until):
				v.phase = "death-end"
				e.boss.death_handled = true
				e.hp = 0.0
				e.dead_at = sim.tick - 600
				e.hidden = true
				sim.controller.enemy_died(sim, e)
		return true

	return true

func _enter_demon_transform(sim, e: Dictionary, t: Dictionary) -> void:
	var v: Dictionary = e.veznan
	v.phase = "demon_transform"
	v.phase_signal = ""
	v.action = {}
	v.melee_job = {}
	sim._unblock(e)
	e.health_bar_hidden = true
	e.ignore_damage = true
	e.vis.bans = -1
	for m: Dictionary in sim.modifiers.active.duplicate():
		if m.target == e.id:
			sim.modifiers._release(sim, m)
			sim.modifiers.active.erase(m)
	sim.event.emit("sound", {"id": str(t.demon.transform_sound)})
	_play(sim, e, "demonTransform", false)
	v.wait_until = sim.tick + anim_duration(sim, e, "demonTransform")

func _enter_death(sim, e: Dictionary, t: Dictionary) -> void:
	var v: Dictionary = e.veznan
	v.phase = "death"
	v.phase_signal = ""
	v.action = {}
	v.melee_job = {}
	v.death_at = sim.tick
	sim._unblock(e)
	e.health_bar_hidden = true
	e.ignore_damage = true
	e.can_select = false
	e.vis.bans = -1
	for m: Dictionary in sim.modifiers.active.duplicate():
		if m.target == e.id:
			sim.modifiers._release(sim, m)
			sim.modifiers.active.erase(m)
	_kill_all_enemies(sim, e.id)
	for tw: Dictionary in sim.towers:
		tw.blocked = true
	sim.event.emit("stop_audio", {})
	sim.event.emit("sound", {"id": str(t.sound_events.death)})
	sim.event.emit("hide_gui", {})
	_play(sim, e, "death", false)
	v.death_step = "death_wait_souls"
	v.wait_until = sim.tick + 110

func queue(view) -> void:
	var sim = view.sim
	for p: Dictionary in portals:
		view._queue_template("veznan_portal", p.pos, p.state, p.at, false, false, 1, false, "", {"playback_loop": p.phase == "active" or p.phase == "idle"})
	for lock: Dictionary in tower_locks:
		var tower: Dictionary = sim.tower_by_id(lock.tower)
		if tower.is_empty(): continue
		view._queue_template("mod_veznan_tower", tower.pos, lock.state, lock.at, false, false, 1, false, "", {
			"playback_loop": lock.phase == "preHold",
			"layers": {2: {"visible": lock.phase == "preHold", "state": "", "at": lock.at, "loop": true}},
		})
	for p: Dictionary in soul_particles:
		var ratio := clampf(float(sim.tick - int(p.at)) / float(p.duration), 0.0, 1.0)
		var sx := lerpf(float(p.scales_x[0]), float(p.scales_x[1]), ratio) * float(p.base_scale)
		var sy := lerpf(float(p.scales_y[0]), float(p.scales_y[1]), ratio) * float(p.base_scale)
		var alpha := lerpf(float(p.alphas[0]), float(p.alphas[1]), ratio) / 255.0
		view.draw_list.append({
			"scale": Vector2(sx, sy), "frame": p.frame, "pos": p.pos, "sort_y": p.pos.y,
			"anchor": Vector2(0.5, 0.5), "z": 3100, "draw_order": 1, "order": view.draw_list.size(),
			"flip": false, "rotation": float(p.rotation), "tint": Color(1, 1, 1, alpha),
		})
	for s: Dictionary in souls:
		view._queue_template(s.template, s.pos, "", s.at, false, false, 1, false, "", {"rotation": float(s.get("rotation", s.angle)), "playback_loop": true})
	for wc: Dictionary in white_circles:
		view._queue_template(wc.template, wc.pos, "", wc.at, false, false, 1, false, "", {"born_at": wc.at, "playback_loop": false})

func draw_shoutboxes(view) -> void:
	if shoutboxes.is_empty(): return
	var sim = view.sim
	var paint = view.interface.paint
	for box: Dictionary in shoutboxes:
		var t: Dictionary = sim.templates.get(box.template, {})
		if t.is_empty(): continue
		var elapsed := float(sim.tick - int(box.at)) / 30.0
		var dur := float(box.duration)
		var alpha := 1.0
		if elapsed < 0.25: alpha = clampf(elapsed / 0.25, 0.0, 1.0)
		elif elapsed > dur - 0.25: alpha = clampf((dur - elapsed) / 0.25, 0.0, 1.0)
		var phase := fmod(elapsed, 0.8)
		var sc := lerpf(1.01, 0.99, phase / 0.4) if phase <= 0.4 else lerpf(0.99, 1.01, (phase - 0.4) / 0.4)
		var screen_pos: Vector2 = view.world(box.pos)
		var frame_name := str(t.render.sprites[0].name)
		view._art(frame_name, screen_pos, Vector2(0.5, 0.5), 1.0, Color(1, 1, 1, alpha), false, 0.0, Vector2(sc, sc))
		var text_spec: Dictionary = t.texts.list[0]
		var offset: Vector2 = sim.vec(t.render.sprites[1].offset)
		var box_size: Vector2 = sim.vec(text_spec.size) * sc
		var top_left := screen_pos + Vector2(offset.x, -offset.y) * sc - box_size / 2.0
		var col: Array = text_spec.color
		paint.label(str(box.text), Rect2(top_left, box_size), int(text_spec.font_size), Color(col[0] / 255.0, col[1] / 255.0, col[2] / 255.0, alpha), "center", "middle", 4, 1, "veznan_taunt", "body")
