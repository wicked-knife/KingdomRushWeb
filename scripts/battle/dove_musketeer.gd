extends RefCounted
## kr1/tower_scripts tower_musketeer and all/scripts shotgun, at integer 30 Hz.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers = {"sniper":0,"shrapnel":0}
	tower.layers = {}
	tower.musketeer = {"shooter":1,"cursor":0,"ts":[sim.tick,sim.tick,sim.tick,sim.tick],"job":{}}

static func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	if int(tower.powers[power]) == 1:
		for index in ([1,2] if power == "sniper" else [3]): tower.musketeer.ts[index] = sim.tick

static func _targets(sim, tower: Dictionary, attack: Dictionary, radius: float) -> Array:
	return sim.Ranger.candidates(sim,tower.pos + sim.vec(sim.tower_template(tower).tower.range_offset),radius,attack)

static func _foremost(sim, a: Dictionary, b: Dictionary) -> bool:
	return sim.data.paths.paths[a.path][a.subpath].size()-int(a.node) < sim.data.paths.paths[b.path][b.subpath].size()-int(b.node)

static func _spatial(sim, a: Dictionary, b: Dictionary) -> bool:
	var ac := Vector2i(floor(a.pos.x/50),floor(a.pos.y/50))
	var bc := Vector2i(floor(b.pos.x/50),floor(b.pos.y/50))
	if ac.y != bc.y: return ac.y < bc.y
	if ac.x != bc.x: return ac.x < bc.x
	return a.id < b.id

static func _animate(sim, tower: Dictionary, index: int, target: Dictionary, action: String) -> int:
	var sprite: Dictionary = sim.tower_template(tower).render.sprites[index + 2]
	var offset: Vector2 = sim.vec(sprite.offset)
	var direction := 0 if target.pos.y > tower.pos.y + offset.y else 1
	var state: String = sprite.angles[action][direction]
	tower.layers[index + 3] = {"state":state,"at":sim.tick,"loop":false,"flip":target.pos.x < tower.pos.x + offset.x,"idle":sprite.angles.idle[direction]}
	return direction

static func _begin(sim, tower: Dictionary, target: Dictionary, index: int) -> void:
	var r: Dictionary = tower.musketeer
	var t: Dictionary = sim.tower_template(tower)
	var attack: Dictionary = t.attacks.list[index]
	r.shooter = (int(r.shooter) + 1) % 2
	var facing := _animate(sim,tower,r.shooter,target,attack.animation)
	if index > 0:
		_animate(sim,tower,1-int(r.shooter),target,attack.animation_seeker)
		if index == 3:
			tower.layers[4-int(r.shooter)].flip = (1-int(r.shooter)) < int(r.shooter)
			tower.layers[int(r.shooter)+3].draw_order = 5
	var sprite: Dictionary = t.render.sprites[int(r.shooter)+2]
	r.job = {"index":index,"target":target.id,"entity":target,"target_pos":target.pos,"facing":facing,"sid":int(r.shooter)+3,
		"hit_at":sim.tick+sim.frames(attack.shoot_time),"end_at":sim.tick+Anim.duration(sim.animations,Anim.key(sprite,sprite.angles[attack.animation][facing])),"fired":false}
	if index == 3:
		var radius := float(t.attacks.range)*float(attack.range_factor)
		var distance_value: float = sim.distance(tower.pos+sim.vec(t.tower.range_offset),target.pos)
		r.job.spread=clampf(distance_value/radius,0.75,1.5)
		r.job.far_factor=float(t.powers.shrapnel.far_damage_factor) if distance_value>radius else 1.0
	if index in [1,2]:
		sim.add_effect("mod_van_helsing_crosshair",target.pos,{"target":target.id,"duration":sim.frames(sim.templates.mod_van_helsing_crosshair.modifier.duration)+1,"owner":tower.id})
	sim.event.emit("musketeer_attack",{"index":index,"target":target.id,"tick":sim.tick,"sid":r.job.sid})

static func _fire(sim, tower: Dictionary, job: Dictionary) -> void:
	var t: Dictionary = sim.tower_template(tower)
	var index := int(job.index)
	var attack: Dictionary = t.attacks.list[index]
	var enemy: Dictionary = sim.unit_by_id(job.target)
	if enemy.is_empty(): enemy = job.entity
	if not enemy.is_empty() and enemy.hp <= 0 and index in [1,2]:
		var nearby: Array = sim.enemies.filter(func(e): return e.hp > 0 and sim.distance(enemy.pos,e.pos) <= 50 and sim.Targets.matches(sim,e,attack))
		nearby.sort_custom(func(a,b): return sim.data.paths.paths[a.path][a.subpath].size()-a.progress < sim.data.paths.paths[b.path][b.subpath].size()-b.progress)
		if not nearby.is_empty(): enemy = nearby[0]
	if enemy.is_empty(): return
	var offset: Vector2 = sim.vec(attack.bullet_start_offset[int(job.facing)])
	offset.x *= 1 if enemy.pos.x > tower.pos.x + sim.vec(t.tower.range_offset).x else -1
	var point: Vector2 = tower.pos + sim.vec(t.render.sprites[int(job.sid)-1].offset) + offset
	if index == 3:
		var range_value := float(t.attacks.range) * float(attack.range_factor)
		var distance_value: float = sim.distance(tower.pos+sim.vec(t.tower.range_offset),enemy.pos)
		var spread := float(job.spread)
		var factor := float(job.far_factor)
		var aim: Vector2 = sim._predict(enemy,float(attack.node_prediction))
		sim.add_effect(attack.shoot_fx,point,{"rotation":(aim-point).angle()})
		for i in int(attack.loops):
			var flight: float = sim.rng.randf_range(sim.templates[attack.bullet].bullet.flight_time_min,sim.templates[attack.bullet].bullet.flight_time_max)
			var radius: float = sim.rng.randf_range(float(attack.min_spread)*spread,float(attack.max_spread)*spread)
			var angle := i*TAU/int(attack.loops)
			var destination := aim+Vector2(cos(angle),sin(angle)*0.7)*radius
			sim._projectile(attack.bullet,0,point,destination,flight,tower)
			var p: Dictionary = sim.projectiles[-1]
			p.level = int(tower.powers.shrapnel); p.damage_factor *= factor
			p.damage_min = float(sim.templates[attack.bullet].bullet.damage_min)+float(sim.templates[attack.bullet].bullet.damage_min_inc)*int(p.level)
			p.damage_max = float(sim.templates[attack.bullet].bullet.damage_max)+float(sim.templates[attack.bullet].bullet.damage_max_inc)*int(p.level)
	else:
		sim._projectile(attack.bullet,enemy.id,point,enemy.pos+sim.vec(sim.templates[enemy.template].unit.hit_offset),1.0,tower)
		var p: Dictionary = sim.projectiles[-1]
		p.level = int(tower.powers.sniper) if index > 0 else 0
		if index == 1:
			p.damage_type = 64
			if (int(enemy.get("vis",sim.templates[enemy.template].vis).flags)&32)!=0:
				var factor := float(t.powers.sniper.boss_damage_base)+float(t.powers.sniper.boss_damage_inc)*int(p.level)
				p.damage_min *= factor; p.damage_max *= factor
			else:
				var extra := float(t.powers.sniper.damage_factor_inc)*int(p.level)*float(enemy.max_hp)
				p.damage_min += extra; p.damage_max += extra
		# Source tower applies precision after the sniper HP adjustment, then shotgun rolls again at impact.
		var precision: Dictionary = sim.upgrades.get_tech("archer_precision")
		if not precision.is_empty() and sim.rng.randf() < float(precision.chance):
			p.damage_min *= float(precision.damage_factor); p.damage_max *= float(precision.damage_factor); p.critical = true

static func step(sim, tower: Dictionary) -> void:
	var r: Dictionary = tower.musketeer
	var t: Dictionary = sim.tower_template(tower)
	if not r.job.is_empty():
		if not r.job.fired and sim.tick >= r.job.hit_at: r.job.fired=true; _fire(sim,tower,r.job)
		if sim.tick < r.job.end_at: return
		tower.layers[int(r.job.sid)].erase("draw_order")
		sim.effects = sim.effects.filter(func(e): return e.get("owner","") != tower.id)
		r.job = {}
	while int(r.cursor) < 4:
		var index: int = [2,1,3,0][int(r.cursor)]
		r.cursor += 1
		var attack: Dictionary = t.attacks.list[index]
		var power: Dictionary = t.powers.get(attack.get("power_name",""),{})
		if index > 0 and int(tower.powers[attack.power_name]) == 0: continue
		if index == 2 and sim.rng.randf() >= float(power.instakill_chance_inc)*int(tower.powers.sniper): continue
		var period: float = float(attack.cooldown)*30*float(t.tower.get("cooldown_factor",1))
		if sim.tick-float(r.ts[index]) <= period: continue
		var radius := float(t.attacks.range)*float(attack.get("range_factor",1))
		var targets: Array = _targets(sim,tower,attack,radius*(1.5 if index == 3 else 1))
		if index in [1,2]: targets.sort_custom(func(a,b): return a.hp > b.hp if a.hp != b.hp else _spatial(sim,a,b))
		elif index == 3:
			# seek.lua advances through the contiguous foremost cluster, measured
			# from its first member in Euclidean distance (not the range ellipse).
			targets.sort_custom(func(a,b): return _foremost(sim,a,b))
			if not targets.is_empty():
				var first: Vector2 = targets[0].pos
				var selected: Dictionary = targets[0]
				for candidate: Dictionary in targets.slice(1):
					if first.distance_to(candidate.pos) > float(attack.min_spread): break
					selected = candidate
				targets = [selected]
		if targets.is_empty():
			r.ts[index] += 5
			if index in [1,2]: r.cursor=2
			continue
		var enemy: Dictionary = targets[0]
		if index == 2 and ((int(enemy.get("vis",sim.templates[enemy.template].vis).flags)&32)!=0 or (int(enemy.get("vis",sim.templates[enemy.template].vis).bans)&int(sim.data.constants.F_INSTAKILL))!=0): continue
		r.ts[index] = sim.tick
		if index in [1,2]: r.ts[1]=sim.tick; r.ts[2]=sim.tick
		if index == 3 and sim.distance(tower.pos+sim.vec(t.tower.range_offset),enemy.pos)>radius:
			r.ts[3] -= float(power.far_cooldown_reduction)*float(attack.cooldown)*30
		_begin(sim,tower,enemy,index)
		return
	r.cursor=0
	if sim.tick-float(r.ts[0]) > float(t.tower.long_idle_cooldown)*30:
		for i in 2: _animate(sim,tower,i,{"pos":sim.vec(t.tower.long_idle_pos)},"idle")

static func projectile(sim, p: Dictionary, b: Dictionary) -> void:
	var target: Dictionary = sim.unit_by_id(p.target)
	var speed := float(b.min_speed)
	# The source keeps the launch destination; it only rechecks target validity.
	if p.pos.distance_to(p.to) >= 2*speed/30:
		if sim.tick <= p.last_step: return
		p.last_step=sim.tick
		if not p.target_invalid:
			if target.is_empty(): p.target_invalid=true
			else:
				var delta: Vector2 = target.pos+sim.vec(sim.templates[target.template].unit.hit_offset)-p.to
				if maxf(absf(delta.x),absf(delta.y))>float(b.max_track_distance) or (int(target.get("vis",sim.templates[target.template].vis).bans)&int(sim.data.constants.F_RANGED))!=0: p.target_invalid=true
		p.pos += p.pos.direction_to(p.to)*speed/30
		p.rotation=(p.to-p.pos).angle()
		p.hidden=p.pos.distance_to(p.from)<float(b.hide_radius) or p.pos.distance_to(p.to)<float(b.hide_radius)
		if b.has("particles_name"): sim.snow.emit_trail(sim,p,b.particles_name)
		if p.pos.distance_to(p.to)>=2*speed/30: return
	p.done=true
	if not p.target_invalid and not target.is_empty() and target.hp>0:
		var precision: Dictionary = sim.upgrades.get_tech("archer_precision")
		if not precision.is_empty() and sim.rng.randf()<float(precision.chance): p.damage_min*=float(precision.damage_factor);p.damage_max*=float(precision.damage_factor);p.critical=true
		var type := int(p.get("damage_type",b.damage_type))
		var raw: float = sim.rng.randi_range(int(p.damage_min),int(p.damage_max))*float(p.damage_factor)
		if (type&4096)!=0: raw=float(target.hp)
		sim.damage(target,raw,type,0,float(b.get("reduce_armor",0)))
		if target.hp <= 0 and sim.templates[target.template].unit.get("can_explode",false):
			var fx: String = sim.templates[target.template].unit.get("explode_fx","")
			if sim.templates.has(fx):
				var sprite: Dictionary = sim.templates[fx].render.sprites[0]
				var size: int = int(sim.templates[target.template].unit.size)
				sim.add_effect(fx,target.pos,{"state":sprite.size_names[size-1]})
				target.hidden = true
		if not p.get("critical",false) and b.get("pop",[]).has("pop_headshot"):
			sim.add_effect("pop_headshot",target.pos+Vector2(0,float(sim.templates.pop_headshot.pop_y_offset)))
		if p.get("critical",false): sim.add_effect("pop_crit",target.pos+Vector2(0,float(sim.templates.pop_crit.pop_y_offset)))
		var mods: Array = [b.mod] if b.has("mod") else b.get("mods",[])
		for name: String in mods: sim.modifiers.apply(sim,name,target,maxi(1,int(p.level)),str(p.source),-1,float(p.damage_factor),{"value":raw,"type":type,"reduce_armor":float(b.get("reduce_armor",0))})
		var hit: Vector2 = target.pos+sim.vec(sim.templates[target.template].unit.hit_offset)
		sim.add_effect(str(b.get("hit_fx","")),hit)
		sim.add_effect(str(b.get("hit_blood_fx","")),hit,{"rotation":p.rotation})
	else: sim.add_effect(str(b.get("miss_fx","")),p.to)

static func shrapnel_projectile(sim, p: Dictionary, b: Dictionary) -> void:
	# bomb.update stops one tick before flight_time and integrates gravity
	# with the previous tick's velocity. Preserve this for the new projectile.
	var seconds := minf(float(sim.tick-p.at)/30,float(p.duration)/30)
	p.pos=p.from+p.velocity*seconds+Vector2(0,float(b.g)*seconds*(seconds-1.0/30)*0.5)
	p.rotation=p.initial_rotation+float(b.get("rotation_speed",0))*(-1 if p.to.x>p.from.x else 1)*seconds
	if sim.tick-p.at<p.duration: return
	p.done=true
	var low := float(p.get("damage_min",float(b.damage_min)+float(b.damage_min_inc)*int(p.get("level",0))))
	var high := float(p.get("damage_max",float(b.damage_max)+float(b.damage_max_inc)*int(p.get("level",0))))
	for enemy: Dictionary in sim.enemies:
		if not sim.Targets.matches(sim,enemy,b,true) or sim.distance(p.pos,enemy.pos)>float(b.damage_radius): continue
		var amount := high if not sim.upgrades.get_tech("engineer_efficiency").is_empty() else lerpf(high,low,clampf(sim.distance(p.to,enemy.pos)/float(b.damage_radius),0,1))
		sim.damage(enemy,amount*float(p.damage_factor),int(b.damage_type))
	var water: bool = (sim._terrain_flags(p.pos)&2)!=0 and sim.templates.has(b.get("hit_fx_water",""))
	sim.add_effect(str(b.get("hit_fx_water" if water else "hit_fx","")),p.pos)
	if not water: sim.add_effect(str(b.get("hit_decal","")),p.pos)
