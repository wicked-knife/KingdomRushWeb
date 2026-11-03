extends "res://scripts/battle/controllers/default_level.gd"
const Anim = preload("res://scripts/battle/dove_animation.gd")
var graveyards:Array=[]
var empty_at:int=-1

func reset(sim) -> void:
	super.reset(sim);graveyards.clear();empty_at=-1
	for e:Dictionary in sim.data.layout.entities_list:
		var t:Dictionary=sim.templates.get(e.template,{})
		if t.has("graveyard"):graveyards.append({"spec":t.graveyard.duplicate(true),"next":0,"queue":[]})

func extra_fire_point(point:Vector2) -> bool:return Rect2(127,483,130,90).has_point(point)

func eligible(sim,e:Dictionary,g:Dictionary) -> bool:
	if e.hp>0 or e.get("_in_graveyard",false) or sim.tick-int(e.dead_at)<sim.frames(float(g.dead_time)):return false
	var vis:Dictionary=e.get("vis",sim.templates[e.template].vis)
	return (int(vis.flags)&int(g.vis_has))!=0 and (int(vis.flags)&int(g.vis_bans))==0 and (int(vis.bans)&int(g.vis_flags))==0 and not e.get("hp_before_timeout",false) and e.template not in g.get("excluded_templates",[])

func step(sim) -> void:
	for item:Dictionary in graveyards:
		if sim.tick<int(item.next):continue
		var g:Dictionary=item.spec
		if item.queue.is_empty():item.queue=sim.enemies.filter(func(e):return eligible(sim,e,g))
		if item.queue.is_empty():item.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(g.check_interval));continue
		var corpse:Dictionary=item.queue.pop_front()
		corpse._in_graveyard=true
		for spawn:Array in g.spawns_by_health:
			if float(corpse.max_hp)>float(spawn[1]):continue
			var point:Vector2=sim.vec(g.spawn_pos[sim.rng.randi_range(0,g.spawn_pos.size()-1)])
			var best:float=INF;var path:int=-1;var node:int=0
			for pi:int in sim.data.paths.paths.size():
				if g.has("pi") and pi!=int(g.pi)-1:continue
				for ni:int in sim.data.paths.paths[pi][0].size():
					var d:float=point.distance_squared_to(sim.vec(sim.data.paths.paths[pi][0][ni]))
					if d<best:best=d;path=pi;node=ni
			if path<0:continue
			var e:Dictionary=sim._spawn_enemy(spawn[0],sim.rng.randi_range(0,2),path,"graveyard")
			e.pos=point;e.node=node;e.progress=float(node);e.forced_waypoint=sim.vec(sim.data.paths.paths[path][e.subpath][node])
			sim._state(e,"raise",true);e.playback_loop=false
			e.raise_until=sim.tick+Anim.duration(sim.animations,Anim.key(sim.templates[e.template].render.sprites[0],"raise"))
			e.skeleton_aura_born=sim.tick
			if not g.get("keep_gold",false):e.gold_override=0
			break
		item.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(g.spawn_interval))

func can_finish(sim) -> bool:
	if not super.can_finish(sim):empty_at=-1;return false
	if empty_at<0:empty_at=sim.tick;return false
	var wait_ticks:float=0
	for item:Dictionary in graveyards:wait_ticks=maxf(wait_ticks,(float(item.spec.dead_time)+float(item.spec.check_interval))*30)+2
	return sim.tick-empty_at>wait_ticks
