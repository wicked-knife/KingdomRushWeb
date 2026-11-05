extends RefCounted
## Source enemy_necromancer coroutine; ownership and clocks belong to each actor.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Mixed = preload("res://scripts/battle/dove_enemy_melee.gd")

static func initialize(sim, enemy:Dictionary) -> void:
	enemy.necromancer={"ts":sim.tick,"ids":[],"job":{},"dead_released":false}
	enemy.mixed_melee_job={};enemy.source_corpse=true

static func release(sim, enemy:Dictionary) -> void:
	var state:Dictionary=enemy.necromancer
	if state.dead_released:return
	state.dead_released=true
	for id:int in state.ids:
		var child:Dictionary=sim.unit_by_id(id)
		if not child.is_empty() and child.hp>0:sim.DamageFactors.change(child,sim.templates[child.template],0.7,true,true)

static func step(sim, enemy:Dictionary, template:Dictionary) -> bool:
	var state:Dictionary=enemy.necromancer
	var attack:Dictionary=template.timed_actions.list[0]
	var job:Dictionary=state.job
	if not job.is_empty():
		# y_enemy_wait tests interruption only while its absolute wait is pending.
		if job.phase in ["windup","delay"]:
			if sim.tick<int(job.next):
				if enemy.hp<=0 or int(enemy.get("stun_count",0))>0:
					state.job={}
					if enemy.hp<=0:release(sim,enemy)
					return false
				return true
			if job.phase=="windup":
				job.phase="delay";job.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(attack.spawn_delay));return true
			_spawn(sim,enemy,attack,int(job.count));job.count+=1
			job.phase="yield";job.next=sim.tick+1;return true
		if job.phase=="yield":
			if sim.tick<int(job.next):return true
			if int(job.count)<int(attack.max_count):
				job.phase="delay";job.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(attack.spawn_delay))
				if enemy.hp<=0 or int(enemy.get("stun_count",0))>0:
					state.job={}
					if enemy.hp<=0:release(sim,enemy)
					return false
				return true
			job.phase="animation"
		if sim.tick<int(job.end):return true
		state.job={};state.ts=sim.tick
	if enemy.hp<=0:release(sim,enemy);return false
	if not enemy.mixed_melee_job.is_empty() or not enemy.get("ranged_cast",{}).is_empty():return Mixed.step(sim,enemy,template)
	if int(enemy.get("stun_count",0))>0:enemy.ranged_cast={};return false
	if enemy.blocker!=0:state.ts=sim.tick
	elif int(enemy.get("silence_count",0))==0 and float(sim.tick)/30-float(state.ts)/30>float(attack.cooldown):
		# Preserve the source's actual list loop (including its negative step).
		if state.ids.size()==1:
			var child:Dictionary=sim.unit_by_id(int(state.ids[0]))
			if child.is_empty() or child.hp<=0:state.ids.clear()
		if state.ids.size()>=30:state.ts+=30;return Mixed.step(sim,enemy,template)
		enemy.pending={};enemy.ranged_cast={};enemy.last_dir=Vector2.ZERO
		sim._state(enemy,str(attack.animation),true);enemy.playback_loop=false
		state.job={"phase":"windup","count":0,"next":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(attack.spawn_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(template.render.sprites[0],str(attack.animation)))}
		return true
	return Mixed.step(sim,enemy,template)

static func _spawn(sim, enemy:Dictionary, attack:Dictionary, index:int) -> void:
	var roll:float=sim.rng.randf();var choice:int=attack.entity_names.size()-1
	for i:int in attack.entity_chances.size():
		if roll<=float(attack.entity_chances[i]):choice=i;break
	var name:String=attack.entity_names[choice]
	var offset:Array=attack.summon_offsets[index if index<attack.summon_offsets.size() else 0]
	var node:int=enemy.node+sim.rng.randi_range(int(offset[1]),int(offset[2]))
	var speed:float=(0.5+sim.rng.randf()*0.2)*30
	if node<0 or node>=sim.data.paths.paths[enemy.path][int(offset[0])-1].size():return
	var child:Dictionary=sim._spawn_enemy(name,int(offset[0])-1,enemy.path,"necromancer")
	child.node=node;child.progress=float(node);child.pos=sim.vec(sim.data.paths.paths[child.path][child.subpath][node]);child.gold_override=0
	child.speed_override=speed;child.summoner=enemy.id
	sim.DamageFactors.change(child,sim.templates[name],0.7,true)
	sim._state(child,str(attack.spawn_animation),true);child.playback_loop=false
	child.health_bar_hidden=true
	child.raise_until=sim.tick+Anim.duration(sim.animations,Anim.key(sim.templates[name].render.sprites[0],str(attack.spawn_animation)))
	enemy.necromancer.ids.append(child.id)
