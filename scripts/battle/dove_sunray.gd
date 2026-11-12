extends RefCounted
## The Dove sunray is an automatic tower, including its prediction-time perks.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers={"ray":1,"gold":0,"charge":0};tower.layers={}
	tower.sunray={"last":sim.tick,"casting":{},"charging":true}
	upgraded(sim,tower,"ray")

static func upgraded(sim, tower: Dictionary, power: String) -> void:
	if power!="ray":return
	var t:Dictionary=sim.tower_template(tower)
	var cooldown:float=float(t.powers.ray.cooldown_base)+float(t.powers.ray.cooldown_inc)*int(tower.powers.ray)
	tower.sunray.last=sim.tick-sim.frames(cooldown)
	for index:int in range(7,11):tower.layers[index]={"visible":index-6<=int(tower.powers.ray),"state":"idle","at":sim.tick,"loop":true}

static func targets(sim,tower:Dictionary) -> Array:
	var t:Dictionary=sim.tower_template(tower)
	return sim.Ranger.candidates(sim,tower.pos+sim.vec(t.tower.range_offset),float(t.attacks.range),t.attacks.list[0])

static func group_animation(sim,tower:Dictionary,state:String,looping:bool) -> void:
	for index:int in range(3,7):tower.layers[index]={"state":state,"at":sim.tick,"loop":looping}
	for index:int in range(7,11):
		if tower.layers[index].visible:tower.layers[index].state="charge" if state=="charging" else "idle";tower.layers[index].at=sim.tick

static func step(sim,tower:Dictionary) -> void:
	var t:Dictionary=sim.tower_template(tower)
	var state:Dictionary=tower.sunray
	var a:Dictionary=t.attacks.list[0]
	var level:int=int(tower.powers.ray)
	var cooldown:float=(float(t.powers.ray.cooldown_base)+float(t.powers.ray.cooldown_inc)*level)*float(tower.get("cooldown_factor",t.tower.cooldown_factor))
	var radius:float=float(t.powers.ray.radius_base)+float(t.powers.ray.radius_inc)*level
	var cast:Dictionary=state.casting
	if state.has("ready_at"):
		if sim.tick<int(state.ready_at):return
		state.erase("ready_at");group_animation(sim,tower,"ready_idle",true)
	if not cast.is_empty():
		if not cast.fired and sim.tick>=cast.at:
			cast.fired=true
			var chosen:Dictionary=sim.unit_by_id(int(cast.target))
			if not chosen.is_empty():
				var enemies:Array=sim.enemies.filter(func(e):return sim.Targets.matches(sim,e,a) and sim.distance(chosen.pos,e.pos)<=radius)
				if not enemies.is_empty():
					state.last=sim.tick
					var factor:float=sim.attack_factor(tower)*4.0/(3+enemies.size())
					var kills:int=0
					var b:Dictionary=sim.templates[a.bullet].bullet
					for enemy:Dictionary in enemies:
						# Source predicts with the base bullet before applying the ray-level damage.
						var prediction:float=sim.predict_damage(enemy,float(b.damage_min)*factor,int(b.damage_type))
						var boss:bool=(int(enemy.get("vis",sim.templates[enemy.template].vis).flags)&32)!=0
						var gold:float=sim.unit_gold(enemy)
						if int(tower.powers.gold)>0 and gold>0 and not boss:
							if prediction>=enemy.hp:
								enemy.gold_override=float(gold)*(1+float(t.powers.gold.gold_factor));sim.add_effect("fx_coin_jump",enemy.pos)
							else:sim.gold+=1
						if int(tower.powers.charge)>0 and prediction>=enemy.hp and not boss:kills+=1
						sim._projectile(a.bullet,enemy.id,tower.pos+sim.vec(a.bullet_start_offset),enemy.pos,float(sim.templates[a.bullet].ray_duration),tower)
						var p:Dictionary=sim.projectiles[-1]
						p.level=level;p.damage_factor=factor;p.ray_scale=float(sim.templates[a.bullet].ray_y_scales[level-1])
					if kills>0:
						var pow:Dictionary=t.powers.charge
						var reduction:float=float(pow.min_charge_factor)+(float(pow.max_charge_factor)-float(pow.min_charge_factor))*(1-exp(-0.3*(kills-1)))
						state.last-=cooldown*30*reduction
		if sim.tick<cast.end:return
		state.casting={}
	if tower.get("blocked",false):return
	if float(sim.tick)/30-float(state.last)/30<=cooldown:
		if not state.charging:group_animation(sim,tower,"charging",true)
		state.charging=true;return
	if state.charging:
		group_animation(sim,tower,"ready_start",false);state.charging=false
		state.ready_at=sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[2],"ready_start"));return
	var choices:Array=targets(sim,tower)
	if choices.is_empty():return
	# Source seek advances through consecutive candidates near the first enemy.
	var target:Dictionary=choices[0]
	var first:Vector2=target.pos
	for candidate:Dictionary in choices.slice(1):
		if first.distance_squared_to(candidate.pos)>radius*radius:break
		target=candidate
	group_animation(sim,tower,"shoot",false)
	state.casting={"target":target.id,"at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.shoot_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[2],"shoot")),"fired":false}

static func projectile(sim,p:Dictionary,b:Dictionary) -> void:
	var target:Dictionary=sim.unit_by_id(int(p.target))
	var t:Dictionary=sim.templates[p.template]
	if not p.has("ray_initialized"):
		p.ray_initialized=true
		if not target.is_empty() and t.get("track_target",false):p.to=target.pos+sim.vec(sim.unit_template(target).unit.hit_offset)
	if not target.is_empty() and (int(target.get("vis",sim.templates[target.template].vis).bans)&2)!=0:p.ray_lost=true
	if not target.is_empty() and t.get("track_target",false) and not p.get("ray_lost",false):
		var point:Vector2=target.pos+sim.vec(sim.unit_template(target).unit.hit_offset)
		if maxf(absf(point.x-p.to.x),absf(point.y-p.to.y))>float(b.max_track_distance):p.ray_lost=true
		else:p.ray_dest=point
	p.pos=p.from;p.rotation=(p.get("ray_dest",p.to)-p.from).angle()
	p.sprite_scale=Vector2(p.from.distance_to(p.get("ray_dest",p.to))/float(t.image_width),float(p.get("ray_scale",1)))
	if not p.get("applied",false) and sim.tick-p.at>=sim.source_wait_ticks(int(p.at),float(b.hit_time)):
		p.applied=true
		if not target.is_empty() and not p.get("ray_lost",false):
			var amount:float=(float(p.get("damage_min",b.damage_min))+float(b.get("damage_inc",0))*int(p.get("level",0)))*float(p.damage_factor)
			if int(b.damage_type)!=0:sim.damage(target,amount,int(b.damage_type),0,float(b.get("reduce_magic_armor",0)))
			for name:String in b.get("mods",[b.mod] if b.has("mod") else []):sim.modifiers.apply(sim,name,target,1,str(p.source),-1,float(p.damage_factor))
	if p.get("applied",false) and (sim.tick-p.at>=sim.source_wait_ticks(int(p.at),float(t.ray_duration)) or target.is_empty() or p.get("ray_lost",false)):p.done=true
