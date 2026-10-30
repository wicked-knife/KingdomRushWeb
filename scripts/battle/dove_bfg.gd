extends RefCounted
## Frozen tower_bfg coroutine. Cursor preserves missile -> cluster -> bomb order.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers = {"missile":0,"cluster":0}
	tower.layers = {}
	tower.bfg = {"ts":[sim.tick,0,0],"cursor":0,"job":{},"missile_cooldown":16.0}

static func power_upgraded(sim, tower: Dictionary, power: String) -> void:
	if power == "missile":
		var t: Dictionary = sim.tower_template(tower)
		tower.bfg.missile_cooldown = float(t.attacks.list[1].cooldown_base)-float(t.powers.missile.cooldown_dec)*int(tower.powers.missile)

static func attack(sim, tower: Dictionary, index: int) -> Dictionary:
	var t: Dictionary = sim.tower_template(tower)
	var a: Dictionary = t.attacks.list[index].duplicate(true)
	if index == 1:
		a.range = float(a.range_base)*(1+float(t.powers.missile.range_inc_factor)*int(tower.powers.missile))
		a.cooldown = tower.bfg.missile_cooldown
	elif index == 2: a.cooldown = float(a.cooldown_base)-float(t.powers.cluster.cooldown_dec)*int(tower.powers.cluster)
	return a

static func step(sim, tower: Dictionary) -> void:
	if not tower.has("bfg"): initialize(sim,tower)
	var r: Dictionary = tower.bfg
	var t: Dictionary = sim.tower_template(tower)
	if not r.job.is_empty():
		if not r.job.fired and sim.tick >= r.job.hit_at:
			r.job.fired = true
			_fire(sim,tower,r.job)
		if sim.tick < r.job.end_at: return
		r.job = {}
	for guard in 4:
		if int(r.cursor) == 3:
			tower.layers[2] = {"state":"idle","at":sim.tick,"loop":true}
			r.cursor = 0
			return
		var index: int = [1,2,0][int(r.cursor)]
		r.cursor += 1
		if index > 0 and int(tower.powers[["","missile","cluster"][index]]) == 0: continue
		var a := attack(sim,tower,index)
		var factor := float(tower.get("cooldown_factor",t.tower.cooldown_factor))
		if float(sim.tick)/30-float(r.ts[index])/30 <= float(a.cooldown)*factor: continue
		var radius: float = a.get("range",t.attacks.range)
		var target: Dictionary = sim._target(tower.pos+sim.vec(t.tower.range_offset),radius,false,a,true)
		if index != 1:
			var missile: Dictionary = t.attacks.list[1]
			r.missile_cooldown = float(missile.cooldown_flying) if target.is_empty() else float(missile.cooldown_mixed_base)-float(t.powers.missile.cooldown_mixed_dec)*int(tower.powers.missile)
		if target.is_empty(): r.ts[index] += 5; continue
		r.ts[index] = sim.tick
		r.job = {"index":index,"trigger":target.id,"trigger_pos":target.pos,"fired":false,
			"hit_at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.shoot_time)),
			"end_at":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[1],a.animation))}
		tower.layers[2] = {"state":a.animation,"at":sim.tick,"loop":false,"idle":"idle"}
		sim.event.emit("bfg_attack",{"index":index,"tick":sim.tick,"target":target.id})
		return

static func _fire(sim, tower: Dictionary, job: Dictionary) -> void:
	var t: Dictionary = sim.tower_template(tower)
	var index := int(job.index)
	var a := attack(sim,tower,index)
	var target: Dictionary = sim._target(tower.pos+sim.vec(t.tower.range_offset),float(a.get("range",t.attacks.range)),false,a,true)
	var from: Vector2 = tower.pos+sim.vec(a.bullet_start_offset)
	var to: Vector2 = from+sim.vec(a.launch_vector) if index==1 else (sim.source_prediction(target,a.node_prediction) if not target.is_empty() else job.trigger_pos)
	var bullet: Dictionary = sim.templates[a.bullet].bullet
	sim._projectile(a.bullet,target.get("id",job.trigger) if index==1 else 0,from,to,float(bullet.get("flight_time",1)),tower)
	var p: Dictionary = sim.projectiles[-1]
	if index == 1:
		p.damage_min = float(bullet.damage_min)+float(t.powers.missile.damage_inc)*int(tower.powers.missile)
		p.damage_max = float(bullet.damage_max)+float(t.powers.missile.damage_inc)*int(tower.powers.missile)
	elif index == 2:
		p.fragment_count = int(t.powers.cluster.fragment_count_base)+int(t.powers.cluster.fragment_count_inc)*int(tower.powers.cluster)

static func cluster_insert(sim, p: Dictionary, bullet: Dictionary) -> void:
	var nearest := INF
	var target: Dictionary = sim.unit_by_id(int(p.target))
	for pi in sim.data.paths.paths.size():
		if not target.is_empty() and int(target.path)!=pi: continue
		for ni in sim.data.paths.paths[pi][0].size():
			var point: Vector2 = sim.vec(sim.data.paths.paths[pi][0][ni])
			var distance: float = point.distance_squared_to(p.to)
			if distance < nearest:
				nearest = distance; p.pred_pi = pi; p.pred_ni = ni
	if p.has("pred_pi"): p.to = sim.vec(sim.data.paths.paths[p.pred_pi][0][p.pred_ni])
	p.to += sim.vec(bullet.dest_pos_offset)
	p.velocity = sim.Projectile.launch(p.from,p.to,float(bullet.flight_time),bullet)

static func cluster_step(sim, p: Dictionary, bullet: Dictionary) -> void:
	var elapsed := float(sim.tick-int(p.at))/30
	if elapsed < float(bullet.flight_time):
		var previous:Vector2=p.pos
		p.pos = p.from+p.velocity*elapsed+Vector2(0,0.5*float(bullet.g)*elapsed*elapsed)
		p.rotation = (p.pos-previous).angle() if bullet.get("align_with_trajectory",false) else (deg_to_rad(20)-float(bullet.rotation_speed)*(elapsed+sim.STEP))*(1 if p.to.x>p.from.x else -1)
		p.hidden = p.pos.distance_to(p.from)<float(bullet.hide_radius) or p.pos.distance_to(p.to)<float(bullet.hide_radius)
		return
	p.done = true
	sim.add_effect(bullet.hit_fx,p.to)
	sim.event.emit("sound",{"id":sim.templates[p.template].sound_events.hit})
	var count := int(p.get("fragment_count",bullet.fragment_count))
	var spread := int(bullet.fragment_node_spread)
	for i in range(1,count+1):
		var dest: Vector2
		if p.has("pred_pi"):
			var path: Array = sim.data.paths.paths[p.pred_pi][0]
			var node := clampi(int(p.pred_ni)+spread*floori(count*0.5)-i*spread,0,path.size()-1)
			dest = sim.vec(path[node])
		else:
			var angle := TAU*i/count
			var radius: float = (50*sim.rng.randf()+45)*0.5
			dest = p.to+Vector2(cos(angle),0.7*sin(angle))*radius
		dest += Vector2(sim.rng.randf_range(-bullet.fragment_pos_spread.x,bullet.fragment_pos_spread.x),sim.rng.randf_range(-bullet.fragment_pos_spread.y,bullet.fragment_pos_spread.y))
		var flight: float = sim.templates[bullet.fragment_name].bullet.flight_time+float(i*sim.rng.randi_range(1,2))/30
		sim._projectile(bullet.fragment_name,0,p.pos,dest,flight)
		var fragment: Dictionary = sim.projectiles[-1]
		fragment.damage_factor = p.damage_factor; fragment.source = p.source
		fragment.initial_rotation = deg_to_rad(100*sim.rng.randf())
	sim.event.emit("bfg_fragments",{"tick":sim.tick,"count":count,"pos":p.pos})
