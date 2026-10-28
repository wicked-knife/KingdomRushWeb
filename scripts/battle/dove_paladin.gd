extends RefCounted
## soldier_barrack timed actions, chance-ordered melee and power inheritance.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")

static func initialize(tower: Dictionary) -> void:
	tower.powers = {"healing": 0, "shield": 0, "holystrike": 0}

static func inherit(sim, soldier: Dictionary, tower: Dictionary) -> void:
	soldier.powers = tower.powers.duplicate()
	var health: Dictionary = sim.templates[soldier.template].health
	soldier.armor = float(health.armor) + float(health.armor_inc) * int(tower.powers.shield)
	soldier.magic_armor = float(health.magic_armor) + float(health.magic_armor_inc) * int(tower.powers.shield)

static func upgraded(sim, tower: Dictionary) -> void:
	for soldier: Dictionary in sim.soldiers:
		if soldier.home == tower.id and soldier.hp > 0: inherit(sim, soldier, tower)

static func step(sim, soldier: Dictionary, template: Dictionary) -> bool:
	var action: Dictionary = template.timed_actions.list[0]
	var cast: Dictionary = soldier.get("healing_cast", {})
	if soldier.get("rally_pending", false) or int(soldier.get("stun_count", 0)) > 0:
		soldier.healing_cast = {}; return false
	# Timed actions are reached after a running melee coroutine returns.
	if not soldier.pending.is_empty() or sim.tick < int(soldier.get("melee_end", 0)): return false
	if not cast.is_empty():
		if not cast.hit and sim.tick >= cast.at:
			cast.hit = true
			soldier.healing_at = cast.started
			var hps: Dictionary = sim.templates[action.mod].hps
			var level = int(soldier.powers.healing)
			var value = sim.rng.randi_range(int(hps.heal_min_inc) * level, int(hps.heal_max_inc) * level)
			soldier.hp = minf(soldier.max_hp * float(hps.overflow_factor), soldier.hp + value)
			for modifier: Dictionary in sim.modifiers.active.duplicate():
				if modifier.target == soldier.id and sim.templates[modifier.template].modifier.get("type", "") in sim.templates[action.mod].modifier.ban_types:
					sim.modifiers._release(sim, modifier); sim.modifiers.active.erase(modifier)
		if sim.tick < cast.end: return true
		soldier.healing_cast = {}
	if int(soldier.powers.healing) > 0 and sim.tick - int(soldier.get("healing_at", 0)) >= sim.frames(action.cooldown) and soldier.hp < soldier.max_hp * float(action.min_health_factor):
		soldier.healing_cast = {"started": sim.tick, "at": sim.tick + sim.frames(action.cast_time), "end": sim.tick + Anim.duration(sim.animations, Anim.key(template.render.sprites[0], action.animation)), "hit": false}
		soldier.pending = {}; sim._state(soldier, action.animation, true)
		sim.event.emit("sound", {"id": action.sound})
		return true
	return false

static func melee(sim, soldier: Dictionary, target: Dictionary, template: Dictionary) -> void:
	var pending: Dictionary = soldier.pending
	if not pending.is_empty() and sim.tick >= pending.at:
		var a: Dictionary = template.melee.attacks[int(pending.attack)]
		var level = int(soldier.get("powers", {}).get("holystrike", 0))
		if a.type == "area":
			var point: Vector2 = soldier.pos + Vector2(float(a.hit_offset.x) * (-1 if soldier.flip else 1), float(a.hit_offset.y))
			sim.add_effect(a.hit_decal, point)
			for enemy: Dictionary in sim.enemies:
				if Targets.matches(sim, enemy, a, true) and sim.distance(point, enemy.pos) <= float(a.damage_radius):
					sim.damage(enemy, sim.rng.randi_range(int(a.damage_min) + int(a.damage_min_inc) * level, int(a.damage_max) + int(a.damage_max_inc) * level) * sim.attack_factor(soldier), int(a.damage_type))
					if enemy.hp > 0: sim.modifiers.apply(sim, a.mod, enemy, level, str(soldier.id))
		elif not target.is_empty() and target.hp > 0:
			var dodge: Dictionary = sim.templates[target.template].get("dodge", {})
			var dodged: bool = not dodge.is_empty() and int(target.get("stun_count", 0)) == 0 and sim.rng.randf() <= float(dodge.chance)
			if not dodged: sim.damage(target, sim.rng.randi_range(int(a.damage_min), int(a.damage_max)) * sim.attack_factor(soldier), int(a.damage_type))
		soldier.pending = {}
	if sim.tick < int(soldier.get("melee_end", 0)): return
	if target.is_empty() or target.hp <= 0: return
	if sim.tick >= soldier.attack_at:
		var index = 0
		var holy: Dictionary = template.melee.attacks[2] if template.melee.attacks.size() > 2 else {}
		var level = int(soldier.get("powers", {}).get("holystrike", 0))
		if level > 0 and Targets.matches(sim, target, holy) and sim.rng.randf() < float(holy.chance) + float(holy.chance_inc) * level: index = 2
		elif sim.rng.randf() < float(template.melee.attacks[1].chance): index = 1
		else:
			# soldier_pick_melee_attack also rolls the guaranteed fallback.
			sim.rng.randf()
		var a: Dictionary = template.melee.attacks[index]
		soldier.attack_at = sim.tick + sim.frames(template.melee.cooldown)
		soldier.pending = {"at": sim.tick + sim.frames(a.hit_time), "attack": index}
		soldier.melee_target = target.id
		soldier.melee_end = sim.tick + Anim.duration(sim.animations, Anim.key(template.render.sprites[0], a.animation))
		sim._state(soldier, a.animation, true)
		if a.has("sound"): sim.event.emit("sound", {"id": a.sound})
