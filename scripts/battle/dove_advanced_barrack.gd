extends RefCounted
## Source soldier_barrack attacks for Barbarians and Sasquatch. Per-unit powers
## mutate private templates, preserving the source dual/twister upgrade order.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func supports(name: String) -> bool:
	return name in ["soldier_barbarian","soldier_sasquash"]

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers={"dual":0,"twister":0,"throwing":0}
	tower.slots=[0,0,0,0]

static func insert(sim, soldier: Dictionary, tower: Dictionary) -> void:
	soldier.source_corpse=true
	soldier.combat_template=sim.templates[soldier.template].duplicate(true)
	soldier.advanced_job={};soldier.melee_ts=[0,0];soldier.ranged_ts=0;soldier.range_check_ts=0
	soldier.power_changes=[]
	if soldier.template!="soldier_barbarian":return
	soldier.powers={"dual":0,"twister":0,"throwing":0}
	for power: String in sim.data.get("power_orders",{}).get(soldier.template,["dual","throwing","twister"]):
		_apply_power(sim,soldier,power,int(tower.get("powers",{}).get(power,0)))

static func upgraded(sim, tower: Dictionary, power: String) -> void:
	for soldier: Dictionary in sim.soldiers:
		if soldier.home==tower.id and soldier.hp>0:
			soldier.power_changes.append({"power":power,"level":int(tower.powers[power])})

static func _apply_power(sim, soldier: Dictionary, power: String, level: int) -> void:
	var previous:=int(soldier.powers[power])
	var increase:=level-previous
	if increase<=0:return
	soldier.powers[power]=level
	var t:Dictionary=soldier.combat_template
	for component in ["melee","ranged"]:
		for a:Dictionary in t[component].attacks:
			if a.get("power_name","")!=power:continue
			a.level=level;a.disabled=false
			if a.has("chance_inc"):a.chance+=float(a.chance_inc)*increase
			if a.has("range_inc"):a.max_range+=float(a.range_inc)*increase
			if component=="melee" and a.has("damage_inc"):
				a.damage_min+=float(a.damage_inc)*increase;a.damage_max+=float(a.damage_inc)*increase
	if power!="dual":return
	if not soldier.get("dual_applied",false):
		soldier.dual_applied=true
		for a:Dictionary in t.melee.attacks:a.animation+="2";a.damage_type=int(sim.data.constants.DAMAGE_RUDE)
		t.ranged.attacks[0].animation+="2";t.ranged.attacks[0].bullet="axe_barbarian_rude"
		t.render.sprites[0].angles.walk[0]+="2";t.soldier.melee_slot_offset={"x":7,"y":0}
	var twister:Dictionary=t.melee.attacks[1]
	if not twister.has("damage_min_base"):
		twister.damage_min_base=twister.damage_min;twister.damage_max_base=twister.damage_max
	var extra:=level*float(t.melee.attacks[0].damage_inc)*float(t.powers.dual.twister_damage_factor)
	twister.damage_min=float(twister.damage_min_base)+extra;twister.damage_max=float(twister.damage_max_base)+extra

static func _move(sim, s:Dictionary, point:Vector2, t:Dictionary) -> bool:
	var moving:bool=sim._soldier_move(s,point,float(t.motion.max_speed))
	if s.get("dual_applied",false):
		if s.state=="running":sim._state(s,"running2")
		elif s.state=="idle":sim._state(s,"idle2")
	s.playback_loop=true
	return moving

static func _idle(sim, s:Dictionary) -> void:
	sim._state(s,"idle2" if s.get("dual_applied",false) else "idle")
	s.playback_loop=true

static func _changes(sim,s:Dictionary) -> void:
	for change:Dictionary in s.power_changes:_apply_power(sim,s,change.power,int(change.level))
	s.power_changes.clear()

static func _interrupt(sim,s:Dictionary,t:Dictionary) -> void:
	var job:Dictionary=s.advanced_job
	# The source checks stun/rally only inside the pre-hit wait. At its endpoint
	# the hit still occurs; a completed throw also commits its cooldown on return.
	if not job.is_empty() and not job.hit and sim.tick>=int(job.hit_at):_job(sim,s,t)
	job=s.advanced_job
	if not job.is_empty() and job.kind=="ranged" and job.get("done",false):s.ranged_ts=int(job.started)
	s.advanced_job={}

static func step(sim, s:Dictionary) -> void:
	if not s.has("combat_template"):insert(sim,s,sim.tower_by_id(s.home))
	if s.hp<=0:return
	var t:Dictionary=s.combat_template
	if s.get("rally_pending",false):
		_interrupt(sim,s,t);sim._unblock(s);s.rally_pending=false;s.rallying=true
	if int(s.get("stun_count",0))>0:_interrupt(sim,s,t);_changes(sim,s);_idle(sim,s);return
	if s.rallying:
		_interrupt(sim,s,t);_changes(sim,s)
		if not _move(sim,s,s.dest,t):s.rallying=false;_idle(sim,s)
		return
	if not s.advanced_job.is_empty():
		var previous_job:Dictionary=s.advanced_job
		_job(sim,s,t)
		if not s.advanced_job.is_empty() or previous_job.kind!="ranged" or not previous_job.get("done",false):return
	_changes(sim,s)
	# range_while_blocking is checked before melee even when a blocker exists.
	if t.has("ranged") and _ranged(sim,s,t):return
	var target:Dictionary=sim.unit_by_id(int(s.target))
	if target.is_empty() or target.hp<=0 or not s.id in target.blockers or not sim.Targets.matches(sim,target,{"vis_flags":1}):
		sim._unblock(s);target=sim._soldier_target(s)
	elif target.blockers.find(s.id)>0:
		var other:Dictionary=sim._soldier_target(s,true)
		if not other.is_empty():sim._unblock(s);target=other
	if not target.is_empty() and s.target==0:
		s.target=target.id;target.blockers.append(s.id);target.blocker=target.blockers[0]
	if not target.is_empty():
		var point:Vector2=sim.melee_slot(s,target)
		var arrived:bool=s.pos.is_equal_approx(point)
		if _move(sim,s,point,t) or not arrived:return
		s.flip=target.pos.x<s.pos.x
		if _melee(sim,s,target,t):return
		_idle(sim,s)
	elif not _move(sim,s,s.dest,t):
		_idle(sim,s)
		if sim.tick-s.last_hit>=sim.frames(t.regen.last_hit_standoff_time) and sim.tick>=s.regen_at:
			if s.hp<s.max_hp:s.hp=minf(s.max_hp,s.hp+s.max_hp*float(sim.data.rules.soldier_regen_factor))
			s.regen_at=sim.tick+sim.frames(t.regen.cooldown)

static func _ranged(sim, s:Dictionary, t:Dictionary) -> bool:
	var a:Dictionary=t.ranged.attacks[0]
	if a.get("disabled",false) or sim.tick-int(s.range_check_ts)<3:return false
	sim.rng.randf()
	var candidates:Array=sim.Ranger.candidates(sim,s.pos,float(a.max_range),a).filter(func(e):return sim.distance(s.pos,e.pos)>=float(a.min_range))
	if candidates.is_empty():s.range_check_ts=sim.tick;return false
	if float(sim.tick-int(s.ranged_ts))/30<float(a.cooldown)*float(t.unit.cooldown_factor):return false
	var target:Dictionary=candidates[0]
	_begin(sim,s,t,a,{"kind":"ranged","target":target.id,"entity":target,"aim":target.pos,"index":0},float(a.shoot_time))
	return true

static func _melee(sim, s:Dictionary, target:Dictionary, t:Dictionary) -> bool:
	var order:Array=[1,0] if t.melee.attacks.size()>1 else [0]
	for index:int in order:
		var a:Dictionary=t.melee.attacks[index]
		var cooldown:float=t.melee.get("cooldown",a.cooldown) if a.get("shared_cooldown",false) else a.cooldown
		if a.get("disabled",false) or float(sim.tick-int(s.melee_ts[index]))/30<=cooldown*float(t.unit.cooldown_factor) or not sim.Targets.matches(sim,target,a):continue
		if sim.rng.randf()>=float(a.chance):s.melee_ts[index]=sim.tick;continue
		_begin(sim,s,t,a,{"kind":"melee","target":target.id,"entity":target,"index":index},float(a.hit_time))
		return true
	return false

static func _begin(sim, s:Dictionary, t:Dictionary, a:Dictionary, job:Dictionary, delay:float) -> void:
	job.started=sim.tick;job.hit_at=sim.tick+sim.source_wait_ticks(sim.tick,delay)
	job.end_at=sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],a.animation));job.hit=false
	s.advanced_job=job;s.flip=job.entity.pos.x<s.pos.x;s.playback_loop=false
	sim._state(s,a.animation,true)
	if a.has("sound"):sim.event.emit("sound",{"id":a.sound})
	sim.event.emit("advanced_barrack_attack",{"tick":sim.tick,"id":s.id,"kind":job.kind,"index":job.index,"state":s.state})

static func _job(sim, s:Dictionary, t:Dictionary) -> void:
	var job:Dictionary=s.advanced_job
	var a:Dictionary=t.ranged.attacks[0] if job.kind=="ranged" else t.melee.attacks[int(job.index)]
	if not job.hit and sim.tick>=job.hit_at:
		job.hit=true
		if job.kind=="ranged":
			if job.entity.pos.distance_to(job.aim)<=float(a.max_track_distance):
				var offset:Vector2=sim.vec(a.bullet_start_offset[0])*Vector2(-1 if s.flip else 1,1)
				var to:Vector2=job.aim+sim.vec(sim.templates[job.entity.template].unit.hit_offset)
				sim._projectile(a.bullet,int(job.target),s.pos+offset,to,float(sim.templates[a.bullet].bullet.flight_time),s)
				sim.projectiles[-1].level=int(a.level)
				job.done=true
			else:
				s.advanced_job={};_idle(sim,s);return
		else:
			s.melee_ts[int(job.index)]=int(job.started)
			if a.get("shared_cooldown",false):
				for i in t.melee.attacks.size():
					if t.melee.attacks[i].get("shared_cooldown",false):s.melee_ts[i]=int(job.started)
			if a.has("sound_hit"):sim.event.emit("sound",{"id":a.sound_hit})
			if a.type=="area":
				var point:Vector2=s.pos+sim.vec(a.get("hit_offset",{"x":0,"y":0}))*Vector2(-1 if s.flip else 1,1)
				var targets:Array=sim.enemies.filter(func(e):return sim.Targets.matches(sim,e,a,true) and sim.distance(point,e.pos)<=float(a.damage_radius))
				if a.has("count"):targets.sort_custom(func(x,y):return point.distance_squared_to(x.pos)<point.distance_squared_to(y.pos))
				for target:Dictionary in targets.slice(0,int(a.get("count",targets.size()))):
					sim.damage(target,sim.rng.randi_range(int(a.damage_min),int(a.damage_max))*sim.attack_factor(s),int(a.damage_type),int(s.id))
				for name in ["hit_fx","hit_decal"]:sim.add_effect(a.get(name,""),point)
			elif not job.entity.is_empty() and job.entity.hp>0 and s.id in job.entity.blockers:
				var dodge:Dictionary=sim.templates[job.entity.template].get("dodge",{})
				if dodge.is_empty() or int(job.entity.get("stun_count",0))>0 or sim.rng.randf()>float(dodge.chance):
					sim.damage(job.entity,sim.rng.randi_range(int(a.damage_min),int(a.damage_max))*sim.attack_factor(s),int(a.damage_type),int(s.id))
	if sim.tick>=job.end_at:
		if job.kind=="ranged" and job.get("done",false):s.ranged_ts=int(job.started)
		s.advanced_job={};_idle(sim,s)
