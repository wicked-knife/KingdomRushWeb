extends RefCounted
## Frozen tower_scripts.tower_tesla and game_scripts.ray_tesla.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers={"bolt":0,"overcharge":0};tower.layers={}
	tower.tesla={"at":sim.tick,"cast":{}}

static func candidates(sim, tower: Dictionary) -> Array:
	var t:Dictionary=sim.tower_template(tower)
	var found:Array=[]
	for e:Dictionary in sim.enemies:
		if sim.Targets.matches(sim,e,t.attacks.list[0]) and sim.distance(tower.pos+sim.vec(t.tower.range_offset),e.pos)<=float(t.attacks.range):found.append(e)
	found.sort_custom(func(a,b):
		var af:int=int(a.get("vis",sim.templates[a.template].vis).flags)
		var bf:int=int(b.get("vis",sim.templates[b.template].vis).flags)
		if (af&64)!=0 and (bf&(64|128))==0:return true
		if (bf&64)!=0 and (af&(64|128))==0:return false
		return sim.data.paths.paths[a.path][a.subpath].size()-int(a.node)<sim.data.paths.paths[b.path][b.subpath].size()-int(b.node))
	return found

static func step(sim, tower: Dictionary) -> void:
	var t:Dictionary=sim.tower_template(tower)
	var a:Dictionary=t.attacks.list[0]
	var job:Dictionary=tower.tesla.cast
	if not job.is_empty():
		if not job.fired and sim.tick>=job.fire:
			job.fired=true
			var target:Dictionary=sim.unit_by_id(job.target)
			if target.is_empty() or target.hp<=0 or sim.distance(tower.pos+sim.vec(t.tower.range_offset),target.pos)>float(t.attacks.range)*float(t.attacks.range_check_factor):
				var choices:Array=candidates(sim,tower)
				target={} if choices.is_empty() else choices[0]
			if not target.is_empty():
				sim.event.emit("sound",{"id":a.sound_shoot})
				launch(sim,tower,target,tower.pos+sim.vec(a.bullet_start_offset),int(tower.powers.bolt))
			if int(tower.powers.overcharge)>0:
				var spec:Dictionary=sim.templates.aura_tesla_overcharge.aura
				var point:Vector2=tower.pos+sim.vec(t.attacks.list[1].bullet_start_offset)
				sim.snow.burst(sim,"ps_tesla_overcharge",point,float(t.attacks.range)/float(spec.radius))
				sim.auras.append({"template":"aura_tesla_overcharge","pos":point,"at":sim.tick,"level":tower.powers.overcharge,"source":tower.id,"factor":sim.attack_factor(tower),"scale":float(t.attacks.range)/float(spec.radius)})
		if sim.tick<job.end:return
		tower.tesla.cast={}
		tower.layers[2]={"state":"idle","at":sim.tick,"loop":true}
	if tower.get("blocked",false):return
	if float(sim.tick)/30-float(tower.tesla.at)/30<=float(a.cooldown)*float(tower.get("cooldown_factor",t.tower.cooldown_factor)):return
	var choices:Array=candidates(sim,tower)
	if choices.is_empty():tower.tesla.at+=5;return
	tower.tesla.at=sim.tick
	tower.layers[2]={"state":a.animation,"at":sim.tick,"loop":false}
	tower.tesla.cast={"target":choices[0].id,"fire":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.shoot_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[1],a.animation)),"fired":false}

static func launch(sim, source: Dictionary, target: Dictionary, point: Vector2, level: int, previous: Dictionary = {}) -> void:
	sim._projectile("ray_tesla",target.id,point,target.pos,1,source)
	var p:Dictionary=sim.projectiles[-1]
	p.level=level;p.bounces=int(previous.get("bounces",-1))+1
	p.seen=previous.get("seen",[]);p.bounce_scale=1.0 if previous.is_empty() else float(sim.templates.ray_tesla.bounce_scale_y_factor)
	p.damage_factor=previous.get("damage_factor",sim.attack_factor(source))
	p.source=source.get("id",0);p.playback_loop=false
	# Dove queues new rays for the next simulation frame. Do not expose an
	# uninitialized, full-size horizontal sprite while the coroutine is pending.
	p.start_at=sim.tick+1;p.hidden=true

static func projectile(sim, p: Dictionary, b: Dictionary) -> void:
	if sim.tick<int(p.start_at):return
	var t:Dictionary=sim.templates[p.template]
	var target:Dictionary=sim.unit_by_id(p.target)
	if not p.has("tesla_started"):
		p.tesla_started=true;p.at=sim.tick;p.hidden=false
		if target.is_empty():p.done=true;return
		if not track_sprite(sim,p,b):p.done=true;return
		p.seen.append(target.id)
		if target.template not in t.excluded_templates:
			var factor:float=1.0 if not sim.upgrades.get_tech("engineer_efficiency").is_empty() else float(t.bounce_damage_factor)
			var total:float=(sim.rng.randi_range(int(t.bounce_damage_min),int(t.bounce_damage_max))+int(p.level)*float(t.bounce_damage_inc))*factor
			var spec:Dictionary=sim.templates.mod_ray_tesla
			if sim.modifiers.apply(sim,"mod_ray_tesla",target,1,str(p.get("damage_source",sim.next_id)),-1,float(p.damage_factor)):
				var m:Dictionary=sim.modifiers.active[-1]
				m.damage=total*float(spec.dps.cocos_cycles)/float(spec.dps.cocos_frames)/(float(spec.modifier.duration)/float(spec.dps.damage_every))
				m.born=sim.tick+1;m.at=m.born;m.expires=m.born+sim.frames(float(spec.modifier.duration))
				m.damage_ts=float(m.born)/30-float(sim.frames(float(spec.dps.damage_every)))/30
				m.next_hit=m.born
			sim.next_id+=1
		p.bounce_at=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(t.bounce_delay))
	if not p.get("bounced",false):
		var maximum:int=int(t.bounces_lvl[str(int(p.level))])
		if int(p.bounces)<maximum and sim.tick<int(p.bounce_at):return
		p.bounced=true
		var levels:Dictionary=t.bounces_lvl
		if int(p.bounces)<int(levels[str(int(p.level))]):
			var radius:float=float(t.bounce_range)+float(t.bounce_range_inc)*int(p.level)
			var next:Dictionary={};var nearest:float=INF
			for e:Dictionary in sim.enemies:
				if e.id in p.seen or not sim.modifiers.flags_match(sim,e,{"vis_flags":t.bounce_vis_flags,"vis_bans":t.bounce_vis_bans}):continue
				var d:float=sim.distance(p.to,e.pos+sim.vec(sim.templates[e.template].unit.hit_offset))
				if e.hp>0 and d<=radius:
					var squared:float=p.to.distance_squared_to(e.pos+sim.vec(sim.templates[e.template].unit.hit_offset))
					if squared<nearest:next=e;nearest=squared
			if not next.is_empty():launch(sim,target,next,p.to,int(p.level),p)
	p.done=sim.tick-int(p.at)>=Anim.duration(sim.animations,"ray_tesla")
	if not p.done and not p.get("track_invalid",false):track_sprite(sim,p,b)

static func track_sprite(sim, p:Dictionary, b:Dictionary) -> bool:
	# Source coroutine freezes geometry during bounce_delay, then updates both
	# endpoints before testing jumps. A failed track permanently hides this ray.
	var old_from:Vector2=p.pos;var old_to:Vector2=p.to
	var target:Dictionary=sim.unit_by_id(p.target)
	if not target.is_empty():p.to=target.pos+sim.vec(sim.templates[target.template].unit.hit_offset)
	var source:Dictionary=sim.unit_by_id(int(p.source)) if str(p.source).is_valid_int() else {}
	if int(p.bounces)>0 and not source.is_empty():p.pos=source.pos+sim.vec(sim.templates[source.template].unit.hit_offset)
	if maxf(absf(p.pos.x-old_from.x),absf(p.pos.y-old_from.y))>float(b.max_track_distance) or maxf(absf(p.to.x-old_to.x),absf(p.to.y-old_to.y))>float(b.max_track_distance):
		p.hidden=true;p.track_invalid=true;return false
	p.rotation=(p.to-p.pos).angle()
	var length:float=p.pos.distance_to(p.to)/float(sim.templates[p.template].image_width)
	p.sprite_scale=Vector2(length,(0.4+clampf(length*0.6,0,0.6))*float(p.bounce_scale))
	return true

static func auras(sim) -> void:
	for aura:Dictionary in sim.auras.duplicate():
		if aura.template!="aura_tesla_overcharge":continue
		var t:Dictionary=sim.templates[aura.template]
		if sim.tick-int(aura.at)<sim.source_unconditional_wait_ticks(int(aura.at),float(t.aura.duration)):continue
		for e:Dictionary in sim.enemies:
			if e.hp<=0 or not sim.modifiers.flags_match(sim,e,t.aura) or sim.distance(aura.pos,e.pos)>float(t.aura.radius)*float(aura.scale):continue
			var amount:float=sim.rng.randi_range(int(t.aura.damage_min),int(t.aura.damage_max))+float(t.aura.damage_inc)*int(aura.level)
			sim.damage(e,amount*float(aura.factor),int(t.aura.damage_type))
			if e.template not in t.aura.excluded_templates:sim.modifiers.apply(sim,t.aura.mod,e,1,str(aura.source))
		sim.auras.erase(aura)
