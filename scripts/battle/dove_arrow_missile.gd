extends RefCounted
## Frozen all/scripts.lua arrow_missile: ballistic flight, then seek after a miss
## or target death. The elf arrow has one hit and no piercing targets.
static func step(sim, p: Dictionary, b: Dictionary) -> bool:
	if sim.tick <= int(p.last_step): return false
	p.last_step = sim.tick
	var target: Dictionary = sim.unit_by_id(p.target)
	var elapsed: int = sim.tick - p.at
	if not p.seeking:
		p.pos += p.velocity * sim.STEP
		p.rotation = p.velocity.angle()
		p.velocity.y += float(b.g) * sim.STEP
		if elapsed < int(p.duration) and not target.is_empty() and target.hp > 0:
			trail(sim,p,b); return false
		p.seeking = true
		p.hit_distance = float(b.hit_distance)
		if not target.is_empty() and target.hp > 0 and p.pos.distance_to(target.pos + sim.vec(sim.templates[target.template].unit.hit_offset)) < float(p.hit_distance):
			return true
	if target.is_empty() or target.hp <= 0 or not sim.modifiers.flags_match(sim,target,b):
		target = sim._target(p.pos,float(b.get("retarget_range",300)))
		if target.is_empty(): return true
		p.target = target.id
	p.to = target.pos + sim.vec(sim.templates[target.template].unit.hit_offset)
	var speed: float = p.velocity.length()
	if p.pos.distance_to(p.to) <= speed * sim.STEP:
		p.hit_distance = maxf(speed * sim.STEP,float(b.hit_distance) * 1.2)
		return true
	var angle: float = p.velocity.angle_to(p.to - p.pos)
	if absf(angle) > float(b.get("max_seek_angle",PI / 6)):
		var turn: float = float(b.get("turn_speed",5 * PI / 3)) * sim.STEP
		if p.velocity.angle() > PI / 3 and p.velocity.angle() < 2 * PI / 3: turn *= 2
		p.velocity = p.velocity.rotated(turn)
	else:
		speed = clampf(speed + 30 * ceilf(speed / 30 * float(b.get("acceleration_factor",0.12))),float(b.get("min_speed",300)),float(b.get("max_speed",500)))
		p.velocity = p.pos.direction_to(p.to) * speed
	p.pos += p.velocity * sim.STEP
	p.rotation = p.velocity.angle()
	trail(sim,p,b)
	return false

static func trail(sim, p: Dictionary, b: Dictionary) -> void:
	var radius: float = b.get("hide_radius",0)
	p.hidden = radius > 0 and (p.pos.distance_to(p.from) < radius or p.pos.distance_to(p.to) < radius)
	var name: String = b.get("particles_name","")
	if p.hidden or not sim.templates.has(name): return
	var ps: Dictionary = sim.templates[name].particle_system
	sim.effects.append({"template":name,"pos":p.pos,"at":sim.tick,"duration":sim.frames(ps.particle_lifetime[0]),"rotation":p.rotation})
