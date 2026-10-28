extends RefCounted
## Frozen kr1/tower_scripts.lua tower_ranger and game_scripts aura_ranger_thorn.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	if power == "thorn" and int(tower.powers.thorn) == 1:
		tower.ranger.aura = true; tower.ranger.thorn_ts = float(sim.tick)
		tower.layers[5] = {"state":"idle","at":sim.tick,"loop":true,"flip":false,"visible":true}

static func initialize(sim: RefCounted, tower: Dictionary) -> void:
	tower.powers = {"poison":0,"thorn":0}
	tower.ranger = {"shot":-1,"animation_until":sim.tick,"reservations":[],"thorn_ts":float(sim.tick),"casting":{},"aura":false}
	tower.layers = {}
	tower.attack_at = sim.tick + ceili(float(sim.tower_template(tower).attacks.list[0].cooldown) * 30.0)

static func candidates(sim: RefCounted, center: Vector2, radius: float, rule: Dictionary) -> Array:
	var found: Array = []
	for e: Dictionary in sim.enemies:
		if e.hp > 0 and sim.distance(center, e.pos) <= radius and sim.modifiers.flags_match(sim, e, rule): found.append(e)
	found.sort_custom(func(a,b):
		var af := (int(a.get("vis", sim.templates[a.template].vis).get("flags",0)) & 128) != 0
		var bf := (int(b.get("vis", sim.templates[b.template].vis).get("flags",0)) & 128) != 0
		if af != bf: return af
		return sim.data.paths.paths[a.path][a.subpath].size() - a.progress < sim.data.paths.paths[b.path][b.subpath].size() - b.progress)
	return found

static func step(sim: RefCounted, tower: Dictionary) -> void:
	var t: Dictionary = sim.tower_template(tower)
	var a: Dictionary = t.attacks.list[0]
	var r: Dictionary = tower.ranger
	var center: Vector2 = tower.pos + sim.vec(t.tower.range_offset)
	if tower.powers.thorn > 0: _thorn(sim, tower, center)
	if not tower.pending.is_empty() and sim.tick >= tower.pending.at:
		var e: Dictionary = sim.unit_by_id(tower.pending.target)
		if not e.is_empty() and e.hp <= 0:
			var replacements := candidates(sim, e.pos, 50, a)
			if not replacements.is_empty(): e = replacements[0]
		if not e.is_empty():
			var sid := int(tower.pending.sid)
			var offset: Vector2 = sim.vec(t.render.sprites[sid - 1].offset)
			var bullet_offset: Vector2 = sim.vec(a.bullet_start_offset[0 if e.pos.y > center.y else 1])
			bullet_offset.x *= 1 if e.pos.x > center.x else -1
			sim._projectile(a.bullet, e.id, tower.pos + offset + bullet_offset, e.pos + sim.vec(sim.templates[e.template].unit.hit_offset), sim.templates[a.bullet].bullet.flight_time, tower)
			var bullet: Dictionary = sim.projectiles[-1]
			bullet.poison_level = int(tower.powers.poison); bullet.source = str(tower.id)
			sim.event.emit("ranger_shot", {"target":e.id,"sid":sid,"tick":sim.tick})
		tower.pending = {}
	if sim.tick < tower.attack_at or sim.tick < r.animation_until or not tower.pending.is_empty(): return
	var targets := candidates(sim, center, t.attacks.range, a)
	if targets.is_empty(): tower.attack_at += 5; return
	var target: Dictionary = targets[0]
	r.reservations = r.reservations.filter(func(p): return float(sim.tick - p.at) < float(sim.templates[a.bullet].bullet.flight_time) * 30)
	if tower.powers.poison > 0:
		for e: Dictionary in targets:
			var vis: Dictionary = e.get("vis",sim.templates[e.template].vis)
			if (int(vis.bans) & int(sim.data.constants.F_POISON)) == 0 and not sim.modifiers.has(e.id,"mod_ranger_poison") and not r.reservations.any(func(p): return p.id == e.id):
				target = e; r.reservations.append({"id":e.id,"at":sim.tick + sim.frames(a.shoot_time)}); break
	r.shot = (int(r.shot) + 1) % 2
	var sid := int(r.shot) + 3
	var offset: Vector2 = sim.vec(t.render.sprites[sid - 1].offset)
	var up: bool = target.pos.y > tower.pos.y + offset.y
	var state := "shootingUp" if up else "shootingDown"
	var length := Anim.duration(sim.animations, Anim.key(t.render.sprites[sid - 1], state))
	tower.layers[sid] = {"state":state,"at":sim.tick,"loop":false,"flip":target.pos.x < tower.pos.x + offset.x,"idle":"idleUp" if up else "idleDown"}
	r.animation_until = sim.tick + length
	tower.attack_at = sim.tick + ceili(float(a.cooldown) * 30)
	tower.pending = {"target":target.id,"sid":sid,"at":sim.tick + sim.frames(a.shoot_time)}

static func _thorn_targets(sim: RefCounted, tower: Dictionary, center: Vector2, a: Dictionary) -> Array:
	# filter_on uses spatial cell order, unlike the ordinary foremost query.
	sim._sync_enemy_cells()
	var cells: Array = sim.enemy_cells.keys()
	cells.sort_custom(func(x,y): return x.y < y.y if x.y != y.y else x.x < y.x)
	var targets: Array = []
	for cell: Vector2i in cells:
		for id: int in sim.enemy_cells[cell]:
			var e: Dictionary = sim.unit_by_id(id)
			if e.hp > 0 and sim.distance(center,e.pos) <= float(sim.tower_template(tower).attacks.range) and sim.modifiers.flags_match(sim,e,a) and sim.tick - float(e.get("ranger_thorn_ts",-100000)) >= float(a.cooldown) * 30 * 0.8: targets.append(e)
	return targets

static func _thorn(sim: RefCounted, tower: Dictionary, center: Vector2) -> void:
	var r: Dictionary = tower.ranger
	var a: Dictionary = sim.templates.aura_ranger_thorn.aura
	if not r.aura: r.aura = true; r.thorn_ts = float(sim.tick)
	if not r.casting.is_empty():
		if not r.casting.hit and sim.tick >= r.casting.hit_at:
			r.casting.hit = true
			var targets := _thorn_targets(sim,tower,center,a)
			if targets.size() >= int(a.min_count):
				sim.event.emit("sound",{"id":a.hit_sound})
				var level := int(tower.powers.thorn)
				var m: Dictionary = sim.templates.mod_thorn.modifier
				for e: Dictionary in targets.slice(0,int(a.max_count) + int(a.max_count_inc) * level):
					e.ranger_thorn_ts = sim.tick
					var duration := float(m.duration) + float(m.duration_inc) * level
					if sim.modifiers.has(e.id,"mod_ranger_poison"): duration += int(tower.powers.poison) * float(m.duration_inc) * 0.5
					sim.modifiers.apply(sim,"mod_thorn",e,level,str(tower.id),duration,sim.attack_factor(tower))
		if sim.tick < r.casting.ends_at: return
		r.casting = {}
	if float(sim.tick) - float(r.thorn_ts) < float(a.cooldown) * 30: return
	if _thorn_targets(sim,tower,center,a).size() < int(a.min_count): r.thorn_ts += 1.5; return
	r.thorn_ts = float(sim.tick)
	var sprite: Dictionary = sim.tower_template(tower).render.sprites[4]
	tower.layers[5] = {"state":"shoot","at":sim.tick,"loop":false,"flip":false,"idle":"idle","visible":true}
	r.casting = {"hit":false,"hit_at":sim.tick + sim.frames(a.hit_time),"ends_at":sim.tick + Anim.duration(sim.animations,Anim.key(sprite,"shoot"))}
