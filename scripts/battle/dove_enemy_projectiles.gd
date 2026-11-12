extends RefCounted
## Enemy missile flight/retarget and bomb payloads; never share friendly splash.
const Targets = preload("res://scripts/battle/dove_targeting.gd")

static func bolt(sim, p:Dictionary, bullet:Dictionary) -> void:
	# bolt_enemy differs from friendly bolts in tracking, acceleration and yield order.
	if sim.tick<int(p.start_at):return
	if p.pos.distance_squared_to(p.to)>float(p.speed)*float(p.speed)*sim.STEP*sim.STEP:
		var target:Dictionary=sim.unit_by_id(p.target)
		p.tracked_target=target.get("id",0)
		if not target.is_empty():
			var hit:Vector2=target.pos+sim.vec(sim.unit_template(target).unit.hit_offset)
			if target.hp<=0 or (int(target.get("vis",sim.templates[target.template].vis).get("bans",0))&int(sim.data.constants.F_RANGED))!=0:
				p.target=0;p.tracked_target=0
			elif bullet.has("max_track_distance"):
				var delta:Vector2=hit-p.to
				if maxf(absf(delta.x),absf(delta.y))>float(bullet.max_track_distance):p.target=0;p.tracked_target=0
			else:p.to=hit
		p.speed=clampf(float(p.speed)+30*ceilf(float(p.speed)/30*float(bullet.acceleration_factor)),float(bullet.min_speed),float(bullet.max_speed))
		p.pos+=p.pos.direction_to(p.to)*float(p.speed)*sim.STEP
		p.rotation=(p.to-p.pos).angle()
		return
	p.done=true
	var target:Dictionary=sim.unit_by_id(int(p.tracked_target))
	if not target.is_empty() and target.hp>0:sim.damage(target,sim.rng.randi_range(int(bullet.damage_min),int(bullet.damage_max))*float(p.damage_factor),int(bullet.damage_type))
	sim.add_effect(str(bullet.get("hit_fx","")),p.to)

static func step(sim, projectile: Dictionary, bullet: Dictionary, role: String) -> bool:
	if role == "enemy_bomb":
		projectile.merge(sim.Projectile.sample(projectile, bullet, (sim.tick - projectile.at) / 30.0), true)
		if sim.tick - projectile.at < projectile.duration - 1: return true
		projectile.done = true
		sim.pending_entities.append({"kind": "spawner", "template": bullet.hit_payload, "pos": projectile.to, "owner": projectile.get("owner", 0), "level": projectile.get("payload_level", 0)})
		sim.event.emit("sound", {"id": sim.templates[projectile.template].sound_events.hit})
		return true
	if role != "enemy_missile": return false
	if not projectile.has("missile_phase"):
		projectile.missile_phase = "launch"; projectile.speed = float(bullet.min_speed)
		projectile.velocity = projectile.from.direction_to(projectile.to) * projectile.speed
		projectile.rot_dir = 1
	var target: Dictionary = sim.unit_by_id(projectile.target)
	if projectile.missile_phase == "launch":
		if projectile.pos.distance_to(projectile.to) > float(projectile.speed) * sim.STEP:
			projectile.velocity = projectile.pos.direction_to(projectile.to) * projectile.speed
			projectile.pos += projectile.velocity * sim.STEP
			projectile.rotation = projectile.velocity.angle()
			projectile.rot_dir = -1 if (not target.is_empty() and target.pos.x < projectile.pos.x) or (target.is_empty() and projectile.velocity.x < 0) else 1
			trail(sim, projectile, bullet)
			return true
		projectile.missile_phase = "seek"
		if target.is_empty() or target.hp <= 0: target = retarget(sim, projectile, target, bullet)
		if not target.is_empty(): projectile.to = target.pos + sim.vec(sim.unit_template(target).unit.hit_offset)
	if projectile.pos.distance_to(projectile.to) <= float(projectile.speed) * sim.STEP:
		projectile.done = true
		for soldier: Dictionary in sim.soldiers:
			var hit: Vector2 = soldier.pos + sim.vec(sim.unit_template(soldier).unit.hit_offset)
			if Targets.matches(sim, soldier, bullet, true) and sim.distance(hit, projectile.to) <= float(bullet.damage_radius):
				var factor = clampf(sim.distance(hit, projectile.pos) / float(bullet.damage_radius), 0, 1)
				sim.damage(soldier, lerpf(float(bullet.damage_max), float(bullet.damage_min), factor) * float(projectile.get("damage_factor",1.0)), int(bullet.damage_type))
		sim.add_effect(bullet.hit_fx, projectile.pos)
		sim.event.emit("sound", {"id": sim.templates[projectile.template].sound_events.hit})
		return true
	if target.is_empty() or not Targets.matches(sim, target, bullet):
		target = retarget(sim, projectile, target, bullet)
		if not target.is_empty(): projectile.rot_dir = -1 if target.pos.x < projectile.pos.x else 1
	if not target.is_empty(): projectile.to = target.pos + sim.vec(sim.unit_template(target).unit.hit_offset)
	var direction: Vector2 = projectile.to - projectile.pos
	var angle: float = projectile.velocity.angle_to(direction)
	if absf(angle) > float(bullet.get("max_seek_angle", 0.2)):
		var rotation = float(bullet.turn_speed) * sim.STEP * int(projectile.rot_dir)
		if projectile.velocity.angle() > PI / 3 and projectile.velocity.angle() < PI * 2 / 3: rotation *= 2
		projectile.velocity = projectile.velocity.rotated(rotation)
	else:
		projectile.speed = clampf(projectile.speed + 30 * ceilf(projectile.speed / 30.0 * float(bullet.acceleration_factor)), bullet.min_speed, bullet.max_speed)
		projectile.velocity = direction.normalized() * projectile.speed
	projectile.rotation = projectile.velocity.angle()
	projectile.pos += projectile.velocity * sim.STEP
	trail(sim, projectile, bullet)
	return true

static func retarget(sim, p: Dictionary, previous: Dictionary, bullet: Dictionary) -> Dictionary:
	var origin: Vector2 = previous.get("pos", p.pos)
	var candidates: Array = []
	for soldier: Dictionary in sim.soldiers:
		if Targets.matches(sim, soldier, bullet) and sim.distance(origin, soldier.pos) <= float(bullet.retarget_range): candidates.append(soldier)
	var target: Dictionary = {} if candidates.is_empty() else candidates[sim.rng.randi_range(0, candidates.size() - 1)]
	p.target = target.get("id", 0)
	return target

static func trail(sim, p: Dictionary, bullet: Dictionary) -> void:
	if not bullet.has("particles_name"): return
	# Visual particles use no combat random draws.
	sim.add_effect(bullet.particles_name, p.pos, {"duration": 15, "rotation": p.rotation})
