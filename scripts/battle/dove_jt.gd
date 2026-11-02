extends RefCounted
## eb_jt, jt_spawner_aura and mod_jt_tower, all owned by a single simulator.
const Anim = preload("res://scripts/battle/dove_animation.gd")
var freezes: Array = []
var sounds: Array = []

func reset() -> void:
	freezes.clear()
	sounds.clear()

func sound(sim,id:String,delay:float=0) -> void:
	if delay<=0:sim.event.emit("sound",{"id":id})
	else:sounds.append({"at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,delay),"id":id})

static func initialize(sim, e: Dictionary) -> void:
	e.boss={"death_handled":false};e.jt={"phase":"walk","at":sim.tick,"freeze_at":sim.tick,"casting":{},"spawn_ts":[sim.tick/30.0,sim.tick/30.0,sim.tick/30.0]}
	e.mixed_melee_job={};e.playback_loop=true
	sim.event.emit("music",{"id":sim.templates[e.template].sound_events.insert})

static func lethal(sim,e:Dictionary,amount:float,type:int) -> bool:
	if e.get("dying",false):return true
	if sim.predict_damage(e,amount,type)<e.hp:return false
	e.dying=true;e.ignore_damage=true;e.can_select=false;e.health_bar_hidden=true
	e.vis=sim.templates[e.template].vis.duplicate(true);e.vis.bans=4294967295
	for m:Dictionary in sim.modifiers.active.duplicate():
		if m.target==e.id:sim.modifiers._release(sim,m);sim.modifiers.active.erase(m)
	e.stun_count=int(e.get("stun_count",0))+1
	return true

func freeze(sim,tower:Dictionary,source:int) -> void:
	var t:Dictionary=sim.templates.mod_jt_tower
	tower.block_count=int(tower.get("block_count",0))+1;tower.blocked=true
	freezes.append({"tower":tower.id,"source":source,"at":sim.tick,"phase":"start","clicks":0,"clicked":false,"state":"start","end_at":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"start"))})

func tower_click(sim,id:String) -> bool:
	var consumed:bool=false
	for f:Dictionary in freezes:
		if f.tower==id and f.phase=="wait":f.clicked=true;consumed=true
	return consumed

func step_freezes(sim) -> void:
	for item:Dictionary in sounds.duplicate():
		if sim.tick>=item.at:sim.event.emit("sound",{"id":item.id});sounds.erase(item)
	for f:Dictionary in freezes.duplicate():
		var tower:Dictionary=sim.tower_by_id(f.tower)
		if tower.is_empty():freezes.erase(f);continue
		var t:Dictionary=sim.templates.mod_jt_tower
		if f.phase=="start" and sim.tick>=f.end_at:f.phase="wait"
		if f.phase=="wait" and f.clicked:
			f.clicked=false;f.clicks+=1
			sim.add_effect(t.ui.click_fx,tower.pos);sim.event.emit("sound",{"id":t.sound_events.click})
			if f.clicks>=int(t.required_clicks):f.phase="click_end";f.end_start=sim.tick+1
		if f.phase=="click_end" and sim.tick>=f.end_start:
			f.phase="end";f.state="end";f.at=sim.tick;f.release_at=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(t.end_delay))
		if f.phase=="end" and sim.tick>=f.release_at:
			tower.block_count=maxi(0,int(tower.get("block_count",0))-1);tower.blocked=tower.block_count>0
			f.phase="end_wait"
		if f.phase=="end_wait" and sim.tick-f.at>=Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"end")):
			f.phase="fade";f.fade_at=sim.tick
		if f.phase=="fade" and sim.tick-f.fade_at>=60:freezes.erase(f)

func queue(view) -> void:
	var sim=view.sim
	for f:Dictionary in freezes:
		var tower:Dictionary=sim.tower_by_id(f.tower)
		if tower.is_empty():continue
		var alpha:float=clampf(1-float(sim.tick-int(f.get("fade_at",sim.tick)))/30,0,1) if f.phase=="fade" else 1.0
		view._queue_template("mod_jt_tower",tower.pos,f.state,f.at,false,false,1,false,"",{"alpha":alpha,"playback_loop":false,"layers":{2:{"visible":f.phase=="wait", "state":"", "at":f.at, "loop":true}}})
	for e:Dictionary in sim.enemies:
		if e.has("jt") and e.jt.phase=="tap":view._queue_template(sim.templates[e.template].tap_decal,e.pos)

static func step(sim,e:Dictionary,t:Dictionary) -> bool:
	var state:Dictionary=e.jt
	var a:Dictionary=t.timed_attacks.list[0]
	var cast:Dictionary=state.casting
	if not cast.is_empty():
		if not cast.hit and sim.tick>=cast.hit_at:
			cast.hit=true
			for id:String in cast.towers.slice(0,maxi(0,int(a.count)-1)):
				var tower:Dictionary=sim.tower_by_id(id)
				if not tower.is_empty():sim.jt.freeze(sim,tower,e.id)
			sim.add_effect(a.hit_decal,e.pos+sim.vec(a.hit_offset)*Vector2(-1 if e.flip else 1,1))
		if sim.tick<cast.end_at:return true
		state.casting={};state.freeze_at=sim.tick
		state.phase="breath";state.at=sim.tick
		sim._state(e,"breath",true);e.playback_loop=true
		sim.jt.sound(sim,a.exhausted_sound,float(a.exhausted_sound_args.get("delay",0)))
	if e.get("dying",false):
		if state.phase not in ["death","tap","death_end","done"]:
			state.phase="death";state.at=sim.tick;sim._state(e,"death",true);e.playback_loop=false
			sim.event.emit("sound",{"id":t.sound_events.death});return true
		if state.phase=="death" and sim.tick-state.at>=Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"death")):
			state.phase="tap";e.click_pending=false
		elif state.phase=="tap" and e.get("click_pending",false):
			e.click_pending=false;state.phase="death_end";state.at=sim.tick
			sim.jt.sounds.clear();sim.event.emit("stop_audio",{})
			sim._state(e,"death_end",true);e.playback_loop=false;sim.event.emit("sound",{"id":t.sound_events.death_explode})
		elif state.phase=="death_end" and sim.tick-state.at>=Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"death_end")):
			state.phase="done";e.ignore_damage=false;e.vis.bans=int(t.vis.bans)
			sim.damage(e,e.hp,1);state.cleanup_at=sim.tick+1
		elif state.phase=="done" and not e.boss.death_handled and sim.tick>=state.cleanup_at:
			e.boss.death_handled=true
			sim.controller.enemy_died(sim,e)
		return true
	if not e.mixed_melee_job.is_empty():return sim.Behaviors.EnemyMelee.step(sim,e,t)
	if int(e.get("stun_count",0))>0:sim._state(e,"idle");return true
	if state.phase=="breath":
		if sim.tick-state.at<sim.frames(a.exhausted_duration):return true
		state.phase="walk"
	if float(sim.tick)/30-float(state.freeze_at)/30>float(a.cooldown) and int(e.get("silence_count",0))==0 and t.enemy.can_do_magic:
		var targets:Array=sim.towers.filter(func(tower):return tower.type!="" and not tower.get("blocked",false) and sim.tower_template(tower).tower.get("can_be_mod",false) and sim.distance(e.pos,tower.pos)<=float(a.max_range))
		if not targets.is_empty():
			state.casting={"hit":false,"towers":targets.map(func(tower):return tower.id),"hit_at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.hit_time)),"end_at":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"freeze"))}
			sim._state(e,"freeze",true);e.playback_loop=false;sim.jt.sound(sim,a.sound,float(a.sound_args.get("delay",0)));return true
		else:state.freeze_at+=15
	return false

static func spawn_step(sim) -> void:
	for e:Dictionary in sim.enemies.duplicate():
		if not e.has("jt") or e.get("dying",false) or e.hp<=0:continue
		var rows:Array=sim.templates.jt_spawner_aura.spawn_data
		for index:int in rows.size():
			var row:Array=rows[index]
			if float(sim.tick)/30-float(e.jt.spawn_ts[index])>=float(row[1])+float(row[2]):
				sim._spawn_enemy(row[0],int(row[4])-1,int(row[3])-1,"jt_aura")
				e.jt.spawn_ts[index]=sim.tick/30.0-float(row[2])
