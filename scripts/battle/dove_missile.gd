extends RefCounted
## all/scripts.missile, including launch, target reservation, splash and BFG removal.
static func _target(sim, p: Dictionary, previous: Dictionary, bullet: Dictionary, limited: bool) -> Dictionary:
	var point: Vector2 = previous.get("pos",p.pos)
	var best := {}
	var remaining := INF
	for enemy: Dictionary in sim.enemies:
		if not sim.Targets.matches(sim,enemy,{"vis_flags":bullet.vis_flags}) or sim.distance(point,enemy.pos)>float(bullet.retarget_range): continue
		if limited and int(enemy.get("missile_count",0))>=3: continue
		var left: int = sim.data.paths.paths[enemy.path][enemy.subpath].size()-int(enemy.node)
		var mocking: bool = (int(enemy.get("vis",sim.templates[enemy.template].vis).flags)&64)!=0
		var old_mocking: bool = not best.is_empty() and (int(best.get("vis",sim.templates[best.template].vis).flags)&64)!=0
		if best.is_empty() or mocking and not old_mocking or mocking==old_mocking and left<remaining:
			best=enemy; remaining=left
	p.target = best.get("id",0)
	return best

static func _reserve(p: Dictionary, target: Dictionary, bullet: Dictionary) -> void:
	if target.is_empty(): return
	p.missile_target = target
	target.missile_count = int(target.get("missile_count",0))+1

static func step(sim, p: Dictionary, bullet: Dictionary) -> void:
	if not p.has("missile_phase"):
		p.missile_phase="launch"; p.speed=float(bullet.min_speed); p.rot_dir=1; p.hidden=false
		p.velocity=p.from.direction_to(p.to)*p.speed; p.playback_state="flying"
	var target: Dictionary = sim.unit_by_id(int(p.target))
	if target.is_empty(): target=p.get("missile_target",{})
	if p.missile_phase=="launch":
		if p.pos.distance_squared_to(p.to)>float(p.speed)*float(p.speed)*sim.STEP*sim.STEP:
			p.velocity=p.pos.direction_to(p.to)*p.speed
			p.pos+=p.velocity*sim.STEP; p.rotation=p.velocity.angle()
			if bullet.get("rot_dir_from_long_angle",false) and not target.is_empty(): p.rot_dir=-1 if target.pos.x<p.pos.x else 1
			elif p.velocity.x<0:p.rot_dir=-1
			_trail(sim,p,bullet);return
		p.missile_phase="seek"
		if target.is_empty() or target.hp<=0:target=_target(sim,p,target,bullet,false)
		if not target.is_empty():
			_reserve(p,target,bullet);p.to=target.pos+sim.vec(sim.unit_template(target).unit.hit_offset)
	if p.pos.distance_squared_to(p.to)<=float(p.speed)*float(p.speed)*sim.STEP*sim.STEP:
		_hit(sim,p,bullet,target);return
	if target.is_empty() or target.hp<=0 or not sim.modifiers.flags_match(sim,target,{"vis_flags":bullet.vis_flags}):
		target=_target(sim,p,target,bullet,true)
		if not target.is_empty():
			if bullet.get("rot_dir_from_long_angle",false):p.rot_dir=-1 if target.pos.x<p.pos.x else 1
			_reserve(p,target,bullet)
	if not target.is_empty():p.to=target.pos+sim.vec(sim.unit_template(target).unit.hit_offset)
	var direction: Vector2=p.to-p.pos
	if absf(p.velocity.angle_to(direction))>float(bullet.get("max_seek_angle",PI/6)):
		var rotation: float=float(bullet.turn_speed)*sim.STEP*int(p.rot_dir)
		if p.velocity.angle()>PI/3 and p.velocity.angle()<PI*2/3:rotation*=2
		p.velocity=p.velocity.rotated(rotation)
	else:
		p.speed=clampf(float(p.speed)+30*ceilf(float(p.speed)/30*float(bullet.acceleration_factor)),float(bullet.min_speed),float(bullet.max_speed))
		p.velocity=direction.normalized()*p.speed
	p.pos+=p.velocity*sim.STEP;p.rotation=p.velocity.angle()
	_trail(sim,p,bullet)

static func _trail(sim, p: Dictionary, bullet: Dictionary) -> void:
	if bullet.has("particles_name"):sim.snow.emit_trail(sim,p,bullet.particles_name)

static func _hit(sim, p: Dictionary, bullet: Dictionary, target: Dictionary) -> void:
	p.done=true
	var center: Vector2=p.to
	if not target.is_empty():
		center=target.pos;target.missile_count=int(target.get("missile_count",1))-1
	var minimum:=float(p.get("damage_min",bullet.damage_min))
	var maximum:=float(p.get("damage_max",bullet.damage_max))
	for enemy: Dictionary in sim.enemies:
		if not sim.Targets.matches(sim,enemy,bullet,true) or sim.distance(center,enemy.pos)>float(bullet.damage_radius):continue
		var delta:Vector2=enemy.pos-p.to
		var angle:=delta.angle()
		var radius:=Vector2(cos(angle),0.7*sin(angle)).length()*float(bullet.damage_radius)
		var amount:=maximum if not sim.upgrades.get_tech("engineer_efficiency").is_empty() else lerpf(maximum,minimum,clampf(delta.length()/radius,0,1))
		sim.damage(enemy,amount*float(p.damage_factor),int(bullet.damage_type))
		for name:String in bullet.get("mods",[bullet.mod] if bullet.has("mod") else []):
			sim.modifiers.apply(sim,name,enemy,1,str(p.source),-1,float(p.damage_factor))
	var flying:bool=not target.is_empty() and (int(target.get("vis",sim.templates[target.template].vis).flags)&128)!=0
	var fx:String=bullet.get("hit_fx_air",bullet.get("hit_fx","")) if flying else bullet.get("hit_fx","")
	var extra:Dictionary={}
	if not target.is_empty():extra.sort_y_offset=float(target.pos.y-p.pos.y-2)
	sim.add_effect(fx,p.pos,extra)
	sim.event.emit("sound",{"id":sim.templates[p.template].sound_events.hit})
	if not sim.data.get("callbacks",{}).get(p.template,{}).get("remove","").ends_with("missile_bfg.remove"):return
	for i in range(1,4):
		var rotation:float=p.velocity.angle()+i*TAU/3
		var dest:Vector2=p.pos+Vector2(cos(rotation),sin(rotation))*100
		sim._projectile("missile_bfg_second",int(p.target),p.pos,dest,1)
		var child:Dictionary=sim.projectiles[-1]
		child.damage_factor=p.damage_factor;child.damage_min=minimum/3;child.damage_max=maximum/3;child.source=p.source;child.rotation=rotation
	sim.event.emit("bfg_secondary_missiles",{"tick":sim.tick,"count":3,"pos":p.pos})
