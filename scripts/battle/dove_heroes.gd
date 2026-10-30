extends RefCounted
## First source hero adapter. Common lifecycle stays separate from Malik's
## explicit attacks; future heroes can reuse the battle boundary and movement.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")
const GridPath = preload("res://scripts/battle/dove_grid_path.gd")
var fissures: Array = []

func reset(sim) -> void:
	fissures.clear()
	for name: String in sim.data.get("battle_heroes",[]):
		var t: Dictionary=sim.templates[name]
		t.health.hp_max=t.hero.level_stats.hp_max[0]
		var point := Vector2.ZERO
		for entry: Dictionary in sim.data.layout.entities_list:
			if entry.template=="decal_defend_point": point=sim.vec(entry.pos);break
		var custom: Variant=sim.data.layout.get("custom_spawn_pos",{})
		if custom is Dictionary and custom.has("x"): point=sim.vec(custom)
		var hero: Dictionary=sim._soldier(name,"",0,point,point)
		hero.hero=t.hero.duplicate(true);hero.hero.level=1;hero.hero.xp=0;hero.hero.xp_queued=0
		hero.attack_ts=[0,0,0,0];hero.attack_order=[1,3,2,0]
		hero.dest=point;hero.rally_center=point;hero.rallying=false
		hero.waypoints=[];hero.regen_counter=0.0;hero.last_block_at=0
		hero.hero_phase="intro";hero.playback_loop=false;hero.health_bar_hidden=true
		hero.can_click=true
		level_up(sim,hero)
		sim._state(hero,"levelup",true)
		hero.busy_until=sim.tick+animation_ticks(sim,hero,"levelup")
		voice(sim,t,"insert")

static func animation_ticks(sim,hero: Dictionary,state: String) -> int:
	return Anim.duration(sim.animations,Anim.key(sim.templates[hero.template].render.sprites[0],state))

static func voice(sim,t: Dictionary,event: String) -> void:
	if t.get("sound_events",{}).has(event):sim.event.emit("sound",{"id":t.sound_events[event]})

static func level_up(sim,hero: Dictionary) -> void:
	var t: Dictionary=sim.templates[hero.template]
	var level: int=int(hero.hero.level)
	var stats: Dictionary=hero.hero.level_stats
	hero.max_hp=float(stats.hp_max[level-1]);hero.hp=hero.max_hp
	hero.armor=clampf(float(stats.armor[level-1])+float(t.health.get("armor_buff",0)),0,1 if float(stats.armor[level-1])>=1 else 0.99)
	for index in [0,1]:
		t.melee.attacks[index].damage_min=stats.melee_damage_min[level-1]
		t.melee.attacks[index].damage_max=stats.melee_damage_max[level-1]
	for name: String in ["smash","fissure"]:
		var skill: Dictionary=hero.hero.skills[name]
		var steps: Array=skill.xp_level_steps
		if level>steps.size() or steps[level-1]==null: continue
		var rank: int=int(steps[level-1]);skill.level=rank
		var attack: Dictionary=t.melee.attacks[2 if name=="smash" else 3]
		attack.disabled=false
		if name=="smash":
			attack.damage_min=skill.damage_min[rank-1];attack.damage_max=skill.damage_max[rank-1];attack.mod_chance=skill.stun_chance[rank-1]
		else:
			var aura: Dictionary=sim.templates[attack.hit_aura].aura
			aura.level=rank;aura.damage_min=skill.damage_min[rank-1];aura.damage_max=skill.damage_max[rank-1]

static func gain_skill_xp(hero: Dictionary,name: String) -> void:
	var skill: Dictionary=hero.hero.skills[name]
	var rank: int=int(skill.level)
	if rank>0:hero.hero.xp_queued+=float(skill.xp_gain[rank-1]) if skill.has("xp_gain") else rank*float(skill.xp_gain_factor)

static func update_xp(sim,hero: Dictionary) -> bool:
	if float(hero.hero.xp_queued)==0: return false
	var rules: Dictionary=sim.data.hero_rules
	var difficulty: int=int(sim.data.level.difficulty)
	var multiplier: float=float(rules.hero_xp_gain_per_difficulty_mode[difficulty-1])
	if int(sim.data.level.id)<=9:multiplier*=0.1*int(sim.data.level.id)
	hero.hero.xp+=floorf(float(hero.hero.xp_queued)*multiplier+0.5);hero.hero.xp_queued=0
	var level: int=int(hero.hero.level)
	if level>=10 or float(hero.hero.xp)<float(rules.hero_xp_thresholds[level-1]):return false
	hero.hero.level=level+1;level_up(sim,hero)
	sim.event.emit("sound",{"id":"HeroLevelUp"});sim.event.emit("hero_level_up",{"id":hero.id,"level":hero.hero.level})
	return true

static func move_command(sim,hero: Dictionary,point: Vector2) -> bool:
	if hero.is_empty() or not hero.has("hero") or hero.hp<=0 or hero.hero_phase=="respawn": return false
	var t: Dictionary=sim.templates[hero.template]
	if not sim.valid_ground(point,int(t.nav_grid.valid_terrains_dest)): return false
	if t.hero_rally.requires_node_nearby and not sim._valid_node_nearby(point,1.0,sim.NF_RALLY):return false
	var points: Variant=GridPath.new().waypoints(sim.data.terrain,hero.pos,hero.dest,point,int(t.nav_grid.valid_terrains))
	if points==null:return false
	hero.waypoints=points;hero.dest=point;hero.rally_center=point;hero.hero_move_pending=true
	return true

func step(sim,hero: Dictionary) -> void:
	var t: Dictionary=sim.templates[hero.template]
	if hero.hero_phase in ["intro","levelup"]:
		if sim.tick<int(hero.busy_until):return
		hero.hero_phase="active";hero.health_bar_hidden=false;sim._state(hero,"idle",true)
		if hero.hp<=0:death_step(sim,hero,t)
		return
	if hero.hp<=0 or hero.hero_phase=="respawn": death_step(sim,hero,t);return
	if int(hero.get("stun_count",0))>0:
		hero.pending={};hero.hero_phase="active";sim._state(hero,"idle");return
	if hero.get("hero_move_pending",false):
		sim._unblock(hero);hero.pending={};hero.hero_move_pending=false
		hero.hero_phase="moving";hero.vis=t.vis.duplicate(true);hero.vis.bans=0xffffffff
		hero.move_immune=int(t.hero_rally.immune_to)
		hero.erase("walk_point");hero.walk_arrived=false
		voice(sim,t,"change_rally_point")
	if hero.hero_phase=="moving":
		if hero.get("walk_arrived",false) and hero.pos.is_equal_approx(hero.dest):
			hero.hero_phase="active";hero.vis=t.vis.duplicate(true);hero.move_immune=0;sim._state(hero,"idle",true)
		else:
			if not hero.has("walk_point") or hero.get("walk_arrived",false):
				hero.walk_point=hero.waypoints.pop_front() if not hero.waypoints.is_empty() else hero.dest
				hero.walk_unsnapped=not hero.waypoints.is_empty()
			var delta: Vector2=hero.walk_point-hero.pos
			var distance: float=float(t.motion.max_speed)*sim.STEP*sim.modifiers.speed(hero.id,sim)
			hero.flip=delta.x<0;sim._state(hero,"running")
			hero.walk_arrived=delta.length()<=distance
			hero.pos=hero.pos+delta.normalized()*distance if hero.walk_unsnapped or not hero.walk_arrived else hero.walk_point
			return
	if hero.hero_phase=="attack":
		attack_step(sim,hero,t);return
	if update_xp(sim,hero):
		hero.hero_phase="levelup";hero.busy_until=sim.tick+animation_ticks(sim,hero,"levelup");sim._state(hero,"levelup",true);return
	var target: Dictionary=sim.unit_by_id(int(hero.target))
	if target.is_empty() or target.hp<=0 or not hero.id in target.blockers or not Targets.matches(sim,target,{"vis_flags":1,"vis_bans":256}):
		sim._unblock(hero);target=pick_target(sim,hero,t)
	elif target.blockers.find(hero.id)>0:
		var alternate: Dictionary=sim._soldier_target(hero,true)
		if not alternate.is_empty():sim._unblock(hero);target=alternate
	if not target.is_empty():
		if hero.target==0:hero.target=target.id;target.blockers.append(hero.id);target.blocker=target.blockers[0]
		var slot: Vector2=sim.melee_slot(hero,target)
		var arrived: bool=hero.pos.is_equal_approx(slot)
		if sim._soldier_move(hero,slot,float(t.motion.max_speed)) or not arrived:return
		hero.flip=target.pos.x<hero.pos.x
		var index := choose_attack(sim,hero,target,t)
		if index>=0:
			var attack: Dictionary=t.melee.attacks[index]
			if attack.has("xp_from_skill"):gain_skill_xp(hero,attack.xp_from_skill)
			hero.pending={"index":index,"target":target.id,"started":sim.tick,"at":sim.tick+sim.source_wait_ticks(sim.tick,float(attack.hit_time)),"resolved":false}
			hero.hero_phase="attack";hero.busy_until=sim.tick+animation_ticks(sim,hero,attack.animation)
			sim._state(hero,attack.animation,true)
			if attack.get("sound","")!="":sim.event.emit("sound",{"id":attack.sound})
		elif hero.state=="running":sim._state(hero,"idle",true)
	else:
		if sim._soldier_move(hero,hero.dest,float(t.motion.max_speed)):return
		sim._state(hero,"idle")
		if float(sim.tick-int(hero.last_hit))/30.0>float(t.regen.last_hit_standoff_time):
			hero.regen_counter+=sim.STEP
			if float(hero.regen_counter)>float(t.regen.cooldown):
				hero.hp=minf(float(hero.max_hp),float(hero.hp)+ceilf(float(hero.max_hp)*float(sim.data.hero_rules.soldier_regen_factor)));hero.regen_counter=0.0

static func pick_target(sim,hero: Dictionary,t: Dictionary) -> Dictionary:
	if float(sim.tick-int(hero.last_block_at))/30.0<0.1:return {}
	var chosen := {};var nearest := INF
	for enemy: Dictionary in sim.enemies:
		if not Targets.matches(sim,enemy,{"vis_flags":1,"vis_bans":256}) or (sim._terrain_flags(enemy.pos)&256)!=0:continue
		if sim.templates[enemy.template].enemy.has("max_blockers") and not enemy.blockers.is_empty():continue
		var distance: float=hero.rally_center.distance_squared_to(enemy.pos)
		if sim.distance(hero.rally_center,enemy.pos)<=float(t.melee.range) and distance<nearest:chosen=enemy;nearest=distance
	if chosen.is_empty():hero.last_block_at=sim.tick
	return chosen

static func choose_attack(sim,hero: Dictionary,target: Dictionary,t: Dictionary) -> int:
	for index: int in hero.attack_order:
		var attack: Dictionary=t.melee.attacks[index]
		var cooldown: float=float(t.melee.cooldown if attack.get("shared_cooldown",false) else attack.get("cooldown",0))*float(t.unit.cooldown_factor)
		if attack.get("disabled",false) or float(sim.tick)/30.0-float(hero.attack_ts[index])/30.0<=cooldown or not Targets.matches(sim,target,attack):continue
		if sim.rng.randf()>=float(attack.chance):hero.attack_ts[index]=sim.tick;continue
		if attack.has("min_count"):
			var count := 0
			for enemy: Dictionary in sim.enemies:
				if Targets.matches(sim,enemy,attack) and sim.distance(hero.pos,enemy.pos)<=float(attack.damage_radius):count+=1
			if count<int(attack.min_count):continue
		return index
	return -1

func attack_step(sim,hero: Dictionary,t: Dictionary) -> void:
	if hero.pending.is_empty():hero.hero_phase="active";return
	var p: Dictionary=hero.pending
	var attack: Dictionary=t.melee.attacks[int(p.index)]
	if not p.resolved and sim.tick>=int(p.at):
		p.resolved=true;hero.attack_ts[int(p.index)]=int(p.started)
		if attack.get("shared_cooldown",false):
			for index in t.melee.attacks.size():
				if t.melee.attacks[index].get("shared_cooldown",false):hero.attack_ts[index]=int(p.started)
		if attack.get("sound_hit","")!="":sim.event.emit("sound",{"id":attack.sound_hit})
		var point: Vector2=hero.pos+sim.vec(attack.get("hit_offset",{"x":0,"y":0}))*Vector2(-1 if hero.flip else 1,1)
		var target: Dictionary=sim.unit_by_id(int(p.target))
		if attack.type=="area":
			for enemy: Dictionary in sim.enemies:
				if Targets.matches(sim,enemy,{"vis_flags":attack.get("damage_flags",0),"vis_bans":attack.get("damage_bans",0)}) and sim.distance(point,enemy.pos)<=float(attack.damage_radius):hit(sim,hero,enemy,attack)
			if attack.has("hit_aura"):
				fissures.append({"template":attack.hit_aura,"pos":point,"target":int(p.target),"source":hero.id,"aura":sim.templates[attack.hit_aura].aura.duplicate(true),"at":sim.tick+1,"spread":0,"paths":[]})
			for key: String in ["hit_fx","hit_decal"]:
				if attack.has(key):sim.add_effect(attack[key],point)
		elif not target.is_empty() and target.hp>0 and hero.id in target.blockers:
			var dodge: Dictionary=sim.templates[target.template].get("dodge",{})
			if dodge.is_empty() or int(target.get("stun_count",0))>0 or not sim.templates[target.template].enemy.get("can_do_magic",true) or sim.rng.randf()>float(dodge.chance):hit(sim,hero,target,attack)
	if sim.tick>=int(hero.busy_until):hero.pending={};hero.hero_phase="active";sim._state(hero,"idle",true)

static func hit(sim,hero: Dictionary,target: Dictionary,attack: Dictionary) -> void:
	var amount: float=(sim.rng.randi_range(int(attack.get("damage_min",0)),int(attack.get("damage_max",0)))+float(sim.templates[hero.template].unit.damage_buff))*sim.attack_factor(hero)
	var applied: float=sim.damage(target,amount,int(attack.damage_type),hero.id)
	hero.hero.xp_queued+=applied*float(attack.get("xp_gain_factor",0))
	if attack.has("mod") and (not attack.has("mod_chance") or sim.rng.randf()<float(attack.mod_chance)):
		sim.modifiers.apply(sim,attack.mod,target,maxi(1,int(attack.get("level",1))),str(hero.id))

static func death_step(sim,hero: Dictionary,t: Dictionary) -> void:
	if hero.hero_phase not in ["death","tombstone","respawn"]:
		hero.hero_phase="death";hero.hero_death_at=sim.tick;hero.health_bar_hidden=true
		hero.can_click=false
		hero.pending={};hero.move_immune=0;hero.vis=t.vis.duplicate(true)
		sim._unblock(hero);sim._state(hero,"death",true)
		var kind: int=int(hero.get("last_damage_types",0))
		if (kind & int(sim.data.hero_rules.death_hide_types))!=0:
			hero.hidden=true
			if (kind & 8192)!=0:sim.add_effect("fx_soldier_desintegrate",hero.pos)
			elif (kind & 32768)!=0:
				sim.add_effect("fx_unit_explode",hero.pos);sim.add_effect("decal_blood_pool",hero.pos,{"state":t.unit.blood_color});sim.event.emit("sound",{"id":"DeathEplosion"})
		else:voice(sim,t,"death")
	if hero.hero_phase=="respawn":
		if sim.tick<int(hero.busy_until):return
		hero.hp=hero.max_hp;hero.dead_at=-1;hero.hidden=false;hero.ignore_damage=false
		hero.last_damage_types=0;hero.health_bar_hidden=false;hero.hero_phase="active";hero.last_hit=sim.tick
		hero.can_click=true
		sim._state(hero,"idle",true);return
	var elapsed: int=sim.tick-int(hero.hero_death_at)
	if hero.hero_phase=="death" and elapsed>=maxi(sim.frames(float(hero.hero.tombstone_show_time)),animation_ticks(sim,hero,"death")):
		hero.hero_phase="tombstone";hero.hidden=true
		sim.effects.append({"template":hero.hero.tombstone_decal,"pos":hero.pos,"at":sim.tick,"duration":sim.frames(float(t.health.dead_lifetime))-elapsed,"hero_tombstone":hero.id})
	if elapsed>=sim.frames(float(t.health.dead_lifetime)):
		sim.effects=sim.effects.filter(func(f):return int(f.get("hero_tombstone",0))!=int(hero.id))
		hero.hidden=false;hero.ignore_damage=true;hero.hero_phase="respawn"
		hero.busy_until=sim.tick+animation_ticks(sim,hero,"respawn");sim._state(hero,"respawn",true);voice(sim,t,"respawn")

static func node_valid(sim,pi: int,ni: int) -> bool:
	if ni<0 or ni>=sim.data.paths.paths[pi][0].size():return false
	var active: Array=sim.data.paths.get("active",[])
	if pi<active.size() and not active[pi]:return false
	if ni<int(sim.data.paths.get("visible_start",{}).get(str(pi+1),1))-1 or ni>int(sim.data.paths.get("visible_end",{}).get(str(pi+1),sim.data.paths.paths[pi][0].size()))-1:return false
	for invalid: Dictionary in sim.data.layout.get("invalid_path_ranges",[]):
		if int(invalid.path_id)==pi+1 and ni+1>=int(invalid.get("from",1)) and ni+1<=int(invalid.get("to",sim.data.paths.paths[pi][0].size())) and (0xffffffff & ~int(invalid.get("flags",0xffffffff)))==0:return false
	return true

static func nearest_nodes(sim,point: Vector2) -> Array:
	var found: Array=[]
	for pi in sim.data.paths.paths.size():
		var best := INF;var index := -1
		var path: Array=sim.data.paths.paths[pi][0]
		for ni in path.size():
			var distance: float=point.distance_squared_to(sim.vec(path[ni]))
			if distance<best and node_valid(sim,pi,ni):best=distance;index=ni
		if index>=0:found.append({"pi":pi,"ni":index,"distance":best})
	found.sort_custom(func(a,b):return a.distance<b.distance)
	return found

static func node_pos(sim,pi: int,spi: int,ni: int) -> Vector2:
	var path: Array=sim.data.paths.paths[pi][spi]
	return sim.vec(path[clampi(ni,0,path.size()-1)])

static func fissure_hit(sim,f: Dictionary,point: Vector2) -> void:
	sim.add_effect(str(f.aura.fx),point)
	var t: Dictionary=sim.templates[f.template]
	for enemy: Dictionary in sim.enemies:
		if not Targets.matches(sim,enemy,f.aura) or sim.distance(point,enemy.pos)>float(f.aura.damage_radius):continue
		sim.damage(enemy,sim.rng.randi_range(int(f.aura.damage_min),int(f.aura.damage_max)),int(f.aura.damage_type))
		if sim.modifiers.flags_match(sim,enemy,t.stun):sim.modifiers.apply(sim,t.stun.mod,enemy,1,str(f.source))

func step_auras(sim) -> void:
	for f: Dictionary in fissures.duplicate():
		if sim.tick<int(f.at):continue
		if f.paths.is_empty():
			fissure_hit(sim,f,f.pos)
			var target: Dictionary=sim.unit_by_id(int(f.target))
			var closest: Array=nearest_nodes(sim,f.pos) if target.is_empty() else [{"pi":int(target.path),"ni":int(target.node)}]
			if closest.is_empty():fissures.erase(f);continue
			f.paths=[{"pi":int(closest[0].pi),"ni1":int(closest[0].ni),"ni2":int(closest[0].ni)}]
			f.at=wait_until(sim.tick,float(f.aura.spread_delay));continue
		var first: Dictionary=f.paths[0]
		var step_nodes: int=int(f.aura.spread_nodes)
		for ni: int in [int(first.ni1)+step_nodes,int(first.ni2)-step_nodes]:
			var nodes: Array=nearest_nodes(sim,node_pos(sim,int(first.pi),0,ni))
			if nodes.size()>1 and not f.paths.any(func(p):return p.pi==nodes[1].pi):
				f.paths.append({"pi":int(nodes[1].pi),"ni1":int(nodes[1].ni),"ni2":int(nodes[1].ni)})
		f.spread+=1
		for path: Dictionary in f.paths:
			path.ni1+=step_nodes;path.ni2-=step_nodes
			for ni: int in [path.ni1,path.ni2]:fissure_hit(sim,f,node_pos(sim,int(path.pi),0,ni))
		if int(f.spread)>1:
			for path: Dictionary in f.paths:
				for spi in [1,2]:
					for ni: int in [int(path.ni1)-step_nodes,int(path.ni2)+step_nodes]:fissure_hit(sim,f,node_pos(sim,int(path.pi),spi,ni))
		if int(f.spread)>=int(f.aura.level):fissures.erase(f)
		else:f.at=wait_until(sim.tick,float(f.aura.spread_delay))

static func wait_until(tick: int,seconds: float) -> int:
	var target: float=tick/30.0+seconds
	var stop := tick+maxi(1,floori(seconds*30))
	while stop/30.0<target:stop+=1
	return stop
