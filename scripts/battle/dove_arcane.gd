extends RefCounted
## Frozen arcane wizard attack arbitration, ray modifiers and teleport aura.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Ranger = preload("res://scripts/battle/dove_ranger.gd")

static func animation_error(template: Dictionary, animations: Dictionary) -> String:
	for index in [0,2]:
		var name := Anim.key(template.render.sprites[1], template.attacks.list[index].animation)
		if not animations.has(name): return "arcane cast requires animation " + name
	return ""

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers = {"disintegrate": 0, "teleport": 0}; tower.layers = {}
	tower.arcane = {"last": sim.tick, "timestamps": [sim.tick, 0, 0], "casting": {}, "resume": 0}

static func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	if int(tower.powers[power]) == 1: tower.arcane.timestamps[1 if power == "disintegrate" else 2] = sim.tick

static func _target(sim, tower: Dictionary, index: int) -> Dictionary:
	var template: Dictionary = sim.tower_template(tower)
	var candidates = Ranger.candidates(sim, tower.pos + sim.vec(template.tower.range_offset), template.attacks.range, template.attacks.list[index])
	if index == 2:
		candidates = candidates.filter(func(e): return e.node + 1 >= int(template.attacks.list[2].min_nodes) and int(e.get("teleport_count", 0)) < int(sim.templates.mod_teleport_arcane.max_times_applied))
	return {} if candidates.is_empty() else candidates[0]

static func step(sim, tower: Dictionary) -> void:
	var template: Dictionary = sim.tower_template(tower)
	var state: Dictionary = tower.arcane
	var cooldown_factor := float(tower.get("cooldown_factor", template.tower.cooldown_factor))
	var cast: Dictionary = state.casting
	if not cast.is_empty():
		var index = int(cast.index)
		var attack: Dictionary = template.attacks.list[index]
		if not cast.fired and sim.tick >= cast.at:
			cast.fired = true
			var enemy = _target(sim, tower, index)
			if not enemy.is_empty():
				state.timestamps[index] = state.last
				if index == 2:
					var aura: Dictionary = sim.templates[attack.aura].aura
					sim.auras.append({"template": attack.aura, "pos": sim._predict(enemy, attack.node_prediction), "source": tower.id, "level": tower.powers.teleport, "at": sim.tick, "next": sim.tick + sim.frames(aura.apply_delay), "victims": 0, "max": int(template.powers.teleport.max_count_base) + int(template.powers.teleport.max_count_inc) * int(tower.powers.teleport)})
					sim.event.emit("sound", {"id": sim.templates[attack.aura].sound_events.insert})
				else:
					if index == 1:
						var power: Dictionary = template.powers.disintegrate
						var level = int(tower.powers.disintegrate)
						var dps: Dictionary = sim.templates.mod_ray_arcane.dps
						var base = float(dps.damage_min) if level == 1 else (float(dps.damage_max) if level == 3 else (float(dps.damage_min) + float(dps.damage_max)) * 0.5)
						var upper = float(power.upper_damage[level - 1])
						var cooldown = float(power.cooldown_base) + float(power.cooldown_inc) * level
						var base_time = float(template.attacks.min_cooldown) + 2.25 - level * 0.75
						if enemy.hp < upper:
							var effective = base_time if enemy.hp < base else base_time + (enemy.hp - base) / (upper - base) * (cooldown - base_time)
							state.timestamps[index] -= sim.frames(cooldown - effective)
					var from: Vector2 = tower.pos + sim.vec(attack.bullet_start_offset)
					sim._projectile(attack.bullet, enemy.id, from, enemy.pos, float(sim.templates[attack.bullet].ray_duration), tower)
					sim.projectiles[-1].source = tower.id; sim.projectiles[-1].level = maxi(1, int(tower.powers.disintegrate))
		if sim.tick < cast.end: return
		state.casting = {}; state.resume = int(cast.order) + 1
	if tower.get("blocked", false): return
	var order = [1, 0, 2]
	for position in range(int(state.resume), 3):
		var index: int = order[position]
		var attack: Dictionary = template.attacks.list[index]
		var cooldown = float(attack.cooldown)
		if index == 1:
			if tower.powers.disintegrate == 0: continue
			cooldown = float(template.powers.disintegrate.cooldown_base) + float(template.powers.disintegrate.cooldown_inc) * int(tower.powers.disintegrate)
		elif index == 2 and tower.powers.teleport == 0: continue
		if sim.tick / 30.0 - float(state.last) / 30.0 <= float(template.attacks.min_cooldown) * cooldown_factor: continue
		if sim.tick / 30.0 - float(state.timestamps[index]) / 30.0 <= cooldown * cooldown_factor: continue
		if index != 0 and not tower.get("can_do_magic", template.tower.can_do_magic): continue
		var enemy = _target(sim, tower, index)
		if enemy.is_empty(): state.timestamps[index] += 5; continue
		state.last = sim.tick
		var up: bool = enemy.pos.y > tower.pos.y + float(template.render.sprites[2].offset.y)
		var animation = attack.animation + ("Up" if up else "Down") if attack.animation == "teleport" else ("shootingUp" if up else "shootingDown")
		tower.layers[2] = {"state": attack.animation, "at": sim.tick, "loop": false, "flip": false, "idle": "idle"}
		tower.layers[3] = {"state": animation, "at": sim.tick, "loop": false, "flip": enemy.pos.x < tower.pos.x, "idle": "idleUp" if up else "idleDown"}
		if index == 2: tower.layers[4] = {"state": "fx_tower_arcane_wizard_teleport", "at": sim.tick, "loop": false, "flip": false, "visible": true}
		var fire_at: int = sim.tick
		while fire_at / 30.0 < sim.tick / 30.0 + float(attack.shoot_time): fire_at += 1
		var end_at: int = sim.tick
		var length := Anim.duration(sim.animations, Anim.key(template.render.sprites[1], attack.animation))
		while (end_at / 30.0 - sim.tick / 30.0) * 30.0 < length: end_at += 1
		state.casting = {"index": index, "order": position, "at": fire_at, "end": end_at, "fired": false}
		return
	state.resume = 0

static func projectile(sim, p: Dictionary, bullet: Dictionary) -> void:
	var target: Dictionary = sim.unit_by_id(p.target)
	if target.is_empty() or target.hp <= 0: p.done = true; return
	p.to = target.pos + sim.vec(sim.templates[target.template].unit.hit_offset)
	p.pos = p.from; p.rotation = (p.to - p.from).angle()
	p.sprite_scale = Vector2(p.from.distance_to(p.to) / float(sim.templates[p.template].image_width), 1)
	if not p.get("applied", false):
		p.applied = true
		for name: String in bullet.get("mods", [bullet.mod] if bullet.has("mod") else []):
			sim.modifiers.apply(sim, name, target, int(p.get("level", 1)), str(p.get("source", "")), -1, float(p.get("damage_factor",1.0)))
	if sim.tick - p.at >= p.duration: p.done = true

static func apply(sim, template: String, target: Dictionary, level: int, source: String, damage_factor: float = 1.0) -> bool:
	var t: Dictionary = sim.templates[template]
	var role = sim.behaviors.role(template)
	if not sim.modifiers.flags_match(sim, target, t.modifier): return false
	for existing: Dictionary in sim.modifiers.active:
		if existing.target == target.id and existing.template == template and existing.level >= level and not t.modifier.get("allows_duplicates", false): return false
	var item = {"template": template, "target": target.id, "level": level, "source": source, "born": sim.tick, "at": sim.tick, "state": "", "prefix": "", "scale": Vector2.ONE, "phase": "loop", "visible": true, "special": role}
	if role == "arcane_damage":
		var raw: float = sim.rng.randi_range(int(t.dps.damage_min), int(t.dps.damage_max)) * damage_factor
		var cycles = roundi(float(t.modifier.duration) / float(t.dps.damage_every))
		var extra = maxf(0, raw - target.hp)
		var damage = floorf((raw - extra) / cycles)
		item.merge({"next": sim.tick + 1, "damage_ts": sim.tick / 30.0, "cycles": cycles, "done": 0, "damage": damage, "first": raw - extra - damage * cycles, "extra": extra})
	elif role == "disintegrate": item.next = sim.tick + sim.frames(t.modifier.duration)
	elif role == "teleport":
		if int(target.get("teleport_count", 0)) >= int(t.max_times_applied): return false
		target.teleport_count = int(target.get("teleport_count", 0)) + 1
		sim.damage(target, (float(t.damage_base) + float(t.damage_inc) * level) * damage_factor, int(t.damage_type))
		target.stun_count = int(target.get("stun_count", 0)) + 1
		item.phase = "start"; item.next = sim.tick + sim.frames(t.delay_start)
		unit_effect(sim, t.fx_start, target)
	sim.modifiers.active.append(item)
	return true

static func modifier_step(sim, item: Dictionary, target: Dictionary, t: Dictionary) -> bool:
	if not item.has("special"): return false
	if sim.tick < item.next: return true
	match item.special:
		"arcane_damage":
			if item.done < item.cycles:
				# Keep the source subtraction/addition order. Rounding each pulse
				# to an integer interval loses boundary frames in Lua's ray script.
				var every: float = sim.frames(t.dps.damage_every) / 30.0
				if sim.tick / 30.0 - float(item.damage_ts) < every: return true
				sim.damage(target, float(item.damage) + (float(item.first) if int(item.done) == 0 else 0), int(t.dps.damage_type))
				item.done += 1; item.damage_ts += every; item.next = sim.tick + 1
			else:
				sim.damage(target, item.extra, int(t.dps.damage_type)); sim.modifiers.active.erase(item)
		"disintegrate":
			var vis: Dictionary = target.get("vis", sim.templates[target.template].vis)
			var resistant: bool = (int(vis.flags) & 32) != 0 or (int(vis.bans) & 524288) != 0
			var damage = float(t.boss_damage_base) + target.max_hp * float(t.boss_damage_hp_percent) if resistant else target.hp
			sim.damage(target, damage, 1); sim.modifiers.active.erase(item)
			if not resistant:
				unit_effect(sim, sim.templates[target.template].unit.disintegrate_fx, target)
				target.hidden = true
		"teleport":
			if item.phase == "start":
				sim._unblock(target); target.hidden = true
				item.phase = "hold"; item.next = sim.tick + sim.frames(t.hold_time)
			elif item.phase == "hold":
				var offset = sim.rng.randi_range(int(t.nodes_offset_min) + int(t.nodes_offset_inc) * int(item.level), int(t.nodes_offset_max) + int(t.nodes_offset_inc) * int(item.level))
				target.node = clampi(int(target.node) + offset, int(t.nodeslimit) - 1, sim.data.paths.paths[target.path][target.subpath].size() - int(t.nodeslimit) - 1)
				target.progress = float(target.node); target.pos = sim.vec(sim.data.paths.paths[target.path][target.subpath][target.node])
				unit_effect(sim, t.fx_end, target)
				item.phase = "end"; item.next = sim.tick + sim.frames(t.delay_end)
			else:
				target.hidden = false; target.stun_count = maxi(0, int(target.stun_count) - 1)
				sim.modifiers.active.erase(item)
	return true

static func unit_effect(sim, name: String, target: Dictionary) -> void:
	var sprite: Dictionary = sim.templates[name].render.sprites[0]
	var unit: Dictionary = sim.templates[target.template].unit
	var size := clampi(int(unit.size) - 1, 0, 2)
	var extra := {}
	if sprite.has("size_names"): extra.state = sprite.size_names[size]
	if sprite.has("size_scales"): extra.sprite_scale = sim.vec(sprite.size_scales[size])
	sim.add_effect(name, target.pos + sim.vec(unit.mod_offset), extra)

static func step_auras(sim) -> void:
	for aura: Dictionary in sim.auras.duplicate():
		var spec: Dictionary = sim.templates[aura.template].aura
		if sim.tick - aura.at > sim.frames(spec.duration): sim.auras.erase(aura); continue
		if sim.tick < aura.next or (aura.has("first") and sim.tick - aura.first > sim.frames(spec.apply_duration)): continue
		aura.next = sim.tick + sim.frames(spec.cycle_time)
		if not aura.has("first"): aura.first = sim.tick
		var candidates: Array = []
		sim._sync_enemy_cells()
		var cells: Array = sim.enemy_cells.keys()
		cells.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
		for cell: Vector2i in cells:
			for id: int in sim.enemy_cells[cell]:
				var enemy: Dictionary = sim.unit_by_id(id)
				if enemy.hp > 0 and sim.distance(aura.pos, enemy.pos) <= float(spec.radius) and sim.modifiers.flags_match(sim, enemy, spec): candidates.append(enemy)
		for enemy: Dictionary in candidates:
			if aura.victims >= aura.max: break
			sim.modifiers.apply(sim, spec.mod, enemy, aura.level, str(aura.source)); aura.victims += 1
