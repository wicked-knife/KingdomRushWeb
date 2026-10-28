extends RefCounted
## boss_scripts.eb_juggernaut. Scene-specific death effects belong to controller.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")

static func initialize(sim, enemy: Dictionary) -> void:
	enemy.boss = {"missile_at": sim.tick, "bomb_at": sim.tick, "spawn_level": 0, "casting": {}, "death_handled": false}
	sim.event.emit("music", {"id": sim.templates[enemy.template].sound_events.insert})

static func step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	var state: Dictionary = enemy.boss
	var cast: Dictionary = state.casting
	# The source shoot wait is unconditional: a lethal hit does not cancel a shot
	# that has already entered its windup.
	if not cast.is_empty():
		var attack: Dictionary = template.timed_attacks.list[int(cast.index)]
		if not cast.fired and sim.tick >= cast.at:
			cast.fired = true
			var from: Vector2 = enemy.pos + Vector2(float(attack.bullet_start_offset.x) * (-1 if enemy.flip else 1), float(attack.bullet_start_offset.y))
			if int(cast.index) == 0:
				sim._projectile(attack.bullet, cast.target, from, from + sim.vec(attack.launch_vector), 1)
			else:
				var payload_level = mini(7, int(state.spawn_level))
				state.spawn_level += 1 # The source also advances when no valid landing point is found.
				var destination: Dictionary = sim.Behaviors.Spawner.random_position(sim, 20, 1)
				if not destination.is_empty():
					var to: Vector2 = destination.pos
					var b: Dictionary = sim.templates[attack.bullet].bullet
					sim._projectile(attack.bullet, 0, from, to, float(b.flight_time_base) + from.distance_to(to) * float(b.flight_time_factor))
					sim.projectiles[-1].payload_level = payload_level
			if not sim.projectiles.is_empty(): sim.projectiles[-1].owner = enemy.id
		if sim.tick < cast.end: return true
		state["missile_at" if int(cast.index) == 0 else "bomb_at"] = sim.tick
		state.casting = {}
	if enemy.hp <= 0:
		if not state.death_handled:
			state.death_handled = true; sim._state(enemy, "death", true)
			sim.controller.enemy_died(sim, enemy)
			sim.event.emit("sound", {"id": template.sound_events.death})
		return true
	if int(enemy.get("stun_count", 0)) > 0: return true
	if sim.tick < int(enemy.get("melee_end", 0)):
		return enemy.pending.is_empty()
	for index in range(2):
		var attack: Dictionary = template.timed_attacks.list[index]
		var key = "missile_at" if index == 0 else "bomb_at"
		if sim.tick - int(state[key]) < sim.frames(attack.cooldown): continue
		var target = 0
		if index == 0:
			var candidates = Targets.soldiers(sim, enemy.pos, attack)
			if candidates.is_empty(): state[key] = sim.tick - sim.frames(attack.cooldown) + 15; continue
			target = candidates[0].id
		state.casting = {"index": index, "at": sim.tick + sim.frames(attack.shoot_time), "end": sim.tick + Anim.duration(sim.animations, Anim.key(template.render.sprites[0], attack.animation)), "target": target, "fired": false}
		sim._state(enemy, attack.animation, true)
		return true
	return false
