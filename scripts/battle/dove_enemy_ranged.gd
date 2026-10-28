extends RefCounted
## enemy_mixed ranged branch, including hold_advance and melee precedence.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")

static func step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	if not template.has("ranged"): return false
	var attack: Dictionary = template.ranged.attacks[0]
	if int(enemy.get("silence_count", 0)) > 0: enemy.ranged_cast = {}; return false
	if enemy.get("ranged_cast", {}).is_empty():
		if enemy.blocker != 0: enemy.ranged_target = 0; return false
		var target: Dictionary = sim.unit_by_id(enemy.get("ranged_target", 0))
		if target.is_empty() or not Targets.matches(sim, target, attack) or sim.distance(enemy.pos, target.pos) <= float(attack.min_range) or sim.distance(enemy.pos, target.pos) > float(attack.max_range):
			var candidates = Targets.soldiers(sim, enemy.pos, attack)
			if candidates.is_empty(): enemy.ranged_target = 0; return false
			target = candidates[0]; enemy.ranged_target = target.id
		if sim.tick < int(enemy.get("ranged_at", 0)) + sim.frames(attack.cooldown):
			sim._state(enemy, "idle"); return bool(attack.get("hold_advance", false))
		# Source range_attacks rolls even for a guaranteed attack.
		enemy.ranged_at = sim.tick
		if sim.rng.randf() >= float(attack.chance): return true
		enemy.ranged_cast = {"target": target.id, "at": sim.tick + sim.frames(attack.shoot_time), "end": sim.tick + Anim.duration(sim.animations, Anim.key(template.render.sprites[0], "shoot")), "fired": false}
		enemy.flip = target.pos.x < enemy.pos.x
		sim._state(enemy, "shoot", true)
	var casting: Dictionary = enemy.ranged_cast
	if not casting.fired and sim.tick >= casting.at:
		casting.fired = true
		var target: Dictionary = sim.unit_by_id(casting.target)
		# The source retains the original target through the windup, including
		# its corpse. The arrow resolves the dead target when it lands.
		if not target.is_empty():
			var offset: Vector2 = sim.vec(attack.bullet_start_offset[0]); offset.x *= -1 if enemy.flip else 1
			var from: Vector2 = enemy.pos + offset
			var flight: float = sim.templates[attack.bullet].bullet.flight_time
			var to: Vector2 = target.pos + sim.vec(sim.templates[target.template].unit.hit_offset)
			sim._projectile(attack.bullet, target.id, from, to, flight)
			sim.projectiles[-1].source = enemy.id
	if sim.tick >= casting.end: enemy.ranged_cast = {}; return false
	enemy.last_dir = Vector2.ZERO
	return bool(attack.get("hold_advance", false))
