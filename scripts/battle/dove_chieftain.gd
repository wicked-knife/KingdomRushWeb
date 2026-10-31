extends RefCounted
## enemy_troll_chieftain rage loops. Target lists are re-evaluated at each cast.
const Anim=preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, enemy:Dictionary) -> void:
	enemy.rage_ts=sim.tick;enemy.rage_job={}

static func targets(sim, enemy:Dictionary, a:Dictionary) -> Array:
	var found:Array=sim.enemies.filter(func(e):return e.template in a.allowed_templates and sim.Targets.matches(sim,e,a) and sim.distance(enemy.pos,e.pos)<=float(a.max_range) and not sim.modifiers.active.any(func(m):return m.target==e.id and (m.template in a.exclude_with_mods or sim.templates[m.template].modifier.get("type","")=="slow")))
	found.sort_custom(func(x,y):
		var xc:=Vector2i(floori(x.pos.x/50),floori(x.pos.y/50))
		var yc:=Vector2i(floori(y.pos.x/50),floori(y.pos.y/50))
		return xc.y<yc.y if xc.y!=yc.y else (xc.x<yc.x if xc.x!=yc.x else x.id<y.id))
	return found

static func step(sim, enemy:Dictionary, t:Dictionary) -> bool:
	if not enemy.has("rage_job"):initialize(sim,enemy)
	var a:Dictionary=t.timed_attacks.list[0]
	var job:Dictionary=enemy.rage_job
	if not job.is_empty():
		# y_enemy_wait checks interruption only while tick_ts < stop_ts.
		# The animation wait after applying the effects is unconditional.
		if not job.hit and sim.tick<int(job.at) and int(enemy.get("stun_count",0))>0:
			enemy.rage_job={};sim._state(enemy,"idle",true);return true
		if not job.hit and sim.tick>=job.at:
			job.hit=true
			sim.event.emit("sound",{"id":a.cast_sound})
			var list:Array=targets(sim,enemy,a)
			for target:Dictionary in list.slice(0,int(a.max_count[int(sim.data.level.difficulty)-1])):
				for name:String in a.mods:sim.modifiers.apply(sim,name,target,1,str(enemy.id))
			sim.event.emit("chieftain_cast",{"tick":sim.tick,"id":enemy.id,"loop":job.loop})
		if sim.tick<int(job.end):return true
		if int(job.loop)<int(a.loops):_begin(sim,enemy,t,int(job.loop)+1);return true
		enemy.rage_job={}
		return false
	if int(enemy.get("stun_count",0))>0:sim._state(enemy,"idle");return true
	if enemy.blocker!=0:enemy.rage_ts=sim.tick;return false
	if int(enemy.get("silence_count",0))>0 or float(sim.tick)/30-float(enemy.rage_ts)/30<=float(a.cooldown):return false
	if targets(sim,enemy,a).is_empty():enemy.rage_ts=sim.tick-(float(a.cooldown)-0.5)*30-0.00003;return false
	enemy.rage_ts=sim.tick
	_begin(sim,enemy,t,1)
	return true

static func _begin(sim, enemy:Dictionary, t:Dictionary, loop:int) -> void:
	var a:Dictionary=t.timed_attacks.list[0]
	enemy.rage_job={"loop":loop,"hit":false,"at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.cast_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],a.animation))}
	enemy.last_dir=Vector2.ZERO;enemy.playback_loop=false
	sim._state(enemy,a.animation,true)
	sim.event.emit("chieftain_animation",{"tick":sim.tick,"state":a.animation})
	if int(enemy.get("stun_count",0))>0:
		enemy.rage_job={};sim._state(enemy,"idle",true)
