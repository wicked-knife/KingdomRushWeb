extends RefCounted
## The pinned eb_veznan coroutine, portals and tower modifiers share one battle clock.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")
var boss_id := 0
var portals: Array = []
var blocks: Array = []
var souls: Array = []
var soul_aura: Dictionary = {}
var white: Dictionary = {}
var taunt: Dictionary = {}
var hud_hidden := false
var complete := false

func reset(sim) -> void:
	boss_id=0;portals.clear();blocks.clear();souls.clear();soul_aura.clear();white.clear();taunt.clear();hud_hidden=false;complete=false
	if not sim.templates.has("eb_veznan"):return
	for entity:Dictionary in sim.data.layout.entities_list:
		if sim.templates.get(entity.template,{}).get("template_name","")=="veznan_portal":
			portals.append({"template":entity.template,"pos":sim.vec(entity.pos),"index":int(entity.portal_idx),"pi":int(sim.templates[entity.template].pi)-1,"out_nodes":entity.out_nodes,"state":"idle","at":sim.tick,"signal":false,"job":{},"queue":[]})
	if int(sim.data.level.mode)==1:
		var e:Dictionary=sim._spawn_enemy("eb_veznan",0,0,"level_controller")
		boss_id=e.id;e.pos=sim.vec(sim.templates.eb_veznan.pos_castle)

static func initialize(sim,e:Dictionary) -> void:
	e.veznan={"phase":"waiting","at":sim.tick,"signal":false,"job":{},"block_ts":sim.tick,"portal_ts":sim.tick,"soul_ts":sim.tick,"portal_count":0,"portal_max":0,"last_wave":-1,"taunt_ts":sim.tick,"taunt_delay":0,"welcome_index":0,"welcome_next":sim.tick+31,"initial_hp":e.max_hp,"last_lives":sim.lives,"attack_ts":sim.tick}
	e.boss={"death_handled":false};e.mixed_melee_job={};e.ignore_damage=true;e.health_bar_hidden=true
	e.vis=sim.templates[e.template].vis.duplicate(true);e.playback_loop=true;sim._state(e,"idleDown",true)

static func lethal(sim,e:Dictionary,amount:float,type:int) -> bool:
	if e.veznan.phase not in ["battle","demon"]:return false
	if sim.predict_damage(e,amount,type)<e.hp:return false
	e.veznan.signal=true
	return true

static func duration(sim,e:Dictionary,name:String) -> int:
	var sprite:Dictionary=sim.templates[e.template].render.sprites[0].duplicate(true)
	if e.has("prefix"):sprite.prefix=e.prefix
	return Anim.duration(sim.animations,Anim.key(sprite,name))

static func play(sim,e:Dictionary,name:String,loop:bool=false) -> void:
	sim._state(e,name,true);e.playback_loop=loop

func say(sim,e:Dictionary,set_name:String,index:int=-1) -> void:
	var t:Dictionary=sim.templates[e.template]
	var set:Dictionary=t.taunts.sets[set_name]
	if index<0:index=sim.rng.randi_range(int(set.start_idx),int(set.end_idx))
	taunt={"text":sim.data.ui.strings[set.format % index],"pos":sim.vec(t.taunts.pos),"at":sim.tick,"duration":sim.frames(t.taunts.duration)}
	play(sim,e,"laugh",true)
	e.veznan.job={"kind":"taunt","end":sim.tick+sim.frames(t.taunts.duration)}

func tower_click(id:String) -> bool:
	var consumed:=false
	for item:Dictionary in blocks:
		if item.tower==id and item.phase=="preHold":item.clicked=true;consumed=true
	return consumed

func block_tower(sim,tower:Dictionary,source:int) -> void:
	var t:Dictionary=sim.templates.mod_veznan_tower
	blocks.append({"tower":tower.id,"source":source,"phase":"start","at":sim.tick,"next":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"start")),"clicks":0,"clicked":false,"owns_block":false})

func step_blocks(sim) -> void:
	var t:Dictionary=sim.templates.get("mod_veznan_tower",{})
	for b:Dictionary in blocks.duplicate():
		var tower:Dictionary=sim.tower_by_id(b.tower)
		if tower.is_empty():blocks.erase(b);continue
		if b.phase=="start" and sim.tick>=b.next:
			b.phase="preHold";b.at=sim.tick;b.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,t.click_time)
			tower.block_count=int(tower.get("block_count",0))+1;tower.blocked=true;b.owns_block=true
		if b.phase=="preHold":
			if b.clicked and sim.tick<b.next:
				b.clicked=false;b.clicks+=1;sim.event.emit("sound",{"id":t.sound_click})
			if b.clicks>=int(t.required_clicks):_release_block(sim,b,t)
			elif sim.tick>=b.next:
				b.phase="hold";b.at=sim.tick;b.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,t.duration)
				sim.event.emit("sound",{"id":t.sound_blocked})
		elif b.phase=="hold" and sim.tick>=b.next:_release_block(sim,b,t)
		elif b.phase=="remove" and sim.tick>=b.next:
			if b.owns_block:tower.block_count=maxi(0,int(tower.get("block_count",0))-1);tower.blocked=tower.block_count>0
			blocks.erase(b)

func _release_block(sim,b:Dictionary,t:Dictionary) -> void:
	b.phase="remove";b.at=sim.tick;b.next=sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"remove"))
	sim.event.emit("sound",{"id":t.sound_released})

func step_portals(sim) -> void:
	for p:Dictionary in portals:
		var t:Dictionary=sim.templates[p.template]
		if p.state=="idle" and p.signal:
			p.state="start";p.at=sim.tick;p.next=sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"start"))
		elif p.state=="start" and sim.tick>=p.next:
			var roll:float=sim.rng.randf()
			for group:Array in t.spawn_groups[p.index-1]:
				if roll>float(group[0]):continue
				for row:Array in group[1]:
					var count:int=sim.rng.randi_range(int(row[0]),int(row[1])) if row[0]!=row[1] else int(row[0])
					for i in count:p.queue.append(row[2])
				break
			p.state="active";p.at=sim.tick;p.next=sim.tick
		if p.state=="active" and sim.tick>=p.next:
			if not p.queue.is_empty():
				var child:Dictionary=sim._spawn_enemy(p.queue.pop_front(),sim.rng.randi_range(0,2),p.pi,"veznan_portal")
				child.node=int(p.out_nodes[p.pi])-1;child.progress=float(child.node);child.pos=p.pos
				child.forced_waypoint=sim.vec(sim.data.paths.paths[p.pi][child.subpath][child.node])
				p.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,t.spawn_interval)
			else:
				var length:int=Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"active"))
				if sim.tick-int(p.at)>=length:p.state="end";p.at=sim.tick;p.next=sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"end"))
		elif p.state=="end" and sim.tick>=p.next:p.state="idle";p.at=sim.tick;p.signal=false

func _soul(sim,point:Vector2,angle:float,phase:float,speed:float=-1,duration_value:float=-1) -> void:
	var t:Dictionary=sim.templates.veznan_soul
	var velocity:float=sim.rng.randi_range(int(t.speed[0]),int(t.speed[1])) if speed<0 else speed
	var inc:float=float(t.angle_variation)*(1 if sim.rng.randf()>0.5 else -1) if speed<0 else 0.0
	souls.append({"pos":point,"angle":angle,"variation":0.0,"inc":inc,"speed":velocity,"at":sim.tick,"duration":sim.frames(t.duration if duration_value<0 else duration_value),"phase":phase,"particle_next":float(sim.tick)})

func step_souls(sim) -> void:
	if not soul_aura.is_empty() and sim.tick>=soul_aura.next:
		var t:Dictionary=sim.templates.veznan_souls_aura.souls
		if soul_aura.count>=int(t.count) or soul_aura.get("interrupt",false):soul_aura.clear()
		else:
			soul_aura.count+=1
			_soul(sim,soul_aura.pos,sim.rng.randf_range(t.angles[0],t.angles[1]),1.0-float(soul_aura.count)/int(t.count))
			soul_aura.delay=maxi(1,int(soul_aura.delay)-1);soul_aura.next=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(soul_aura.delay)/30)
	for s:Dictionary in souls.duplicate():
		if sim.tick-int(s.at)>=s.duration:souls.erase(s);continue
		if sim.tick>int(s.at):
			s.angle=float(s.angle)+float(s.variation)
			s.pos+=Vector2.from_angle(s.angle)*float(s.speed)/30.0
			s.angle-=float(s.variation);s.variation+=float(s.inc)
			var t:Dictionary=sim.templates.veznan_soul
			if s.variation>=float(t.max_angle):s.inc=-float(t.angle_variation) if s.inc!=0 else 0.0
			elif s.variation<=float(t.min_angle):s.inc=float(t.angle_variation) if s.inc!=0 else 0.0
		var ps:Dictionary=sim.templates.ps_veznan_soul.particle_system
		while float(sim.tick)>=float(s.particle_next):
			var life:float=sim.rng.randf_range(ps.particle_lifetime[0],ps.particle_lifetime[1])*float(s.phase)
			sim.effects.append({"template":"ps_veznan_soul","pos":s.pos+Vector2(sim.rng.randf_range(-3,3),sim.rng.randf_range(-3,3)),"at":sim.tick,"duration":maxi(1,sim.frames(life)),"rotation":sim.rng.randf_range(-PI,PI),"sprite_scale":Vector2.ONE*sim.rng.randf_range(ps.scale_var[0],ps.scale_var[1])})
			s.particle_next+=30.0/float(ps.emission_rate)

func soul_targets(sim,e:Dictionary,attack:Dictionary) -> Array:
	return sim.soldiers.filter(func(s):return Targets.matches(sim,s,attack) and sim.distance(e.pos,s.pos)<=float(attack.range) and not "elemental" in str(s.template).to_lower())

func _start_cast(sim,e:Dictionary,kind:String,attack:Dictionary) -> void:
	var s:Dictionary=e.veznan
	var targets:Array=[]
	if kind=="block":
		targets=sim.towers.filter(func(t):return sim.tower_template(t).tower.get("can_be_mod",false) and not blocks.any(func(b):return b.tower==t.id))
		for i in range(targets.size()-1,0,-1):
			var k:int=sim.rng.randi_range(0,i);var tmp:Dictionary=targets[i];targets[i]=targets[k];targets[k]=tmp
		if not targets.is_empty():e.flip=targets[0].pos.x<e.pos.x
	play(sim,e,str(attack.get("animation_start",attack.animation)))
	s.job={"kind":kind,"at":sim.tick,"hit":false,"attack":attack.duplicate(true),"end":sim.tick+maxi(duration(sim,e,attack.animation),sim.frames(attack.get("attack_duration",0))),"hit_at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(attack.get("hit_time",0)))}
	if kind=="block":s.job.targets=targets.slice(0,int(attack.count))
	if kind=="soul":s.job.drained=[];s.job.last_arrival=sim.tick;s.job.ending=false

func _job(sim,e:Dictionary) -> bool:
	var s:Dictionary=e.veznan;var j:Dictionary=s.job
	if j.is_empty():return false
	if j.kind=="taunt":
		if sim.tick<int(j.end):return true
		if j.get("reschedule",false):
			var taunts:Dictionary=sim.templates[e.template].taunts
			s.taunt_ts=sim.tick;s.last_lives=sim.lives;s.taunt_delay=sim.frames(sim.rng.randi_range(int(taunts.delay_min),int(taunts.delay_max)))
		s.job={};play(sim,e,"idleDown",true);return false
	if j.kind=="melee":
		if int(e.get("stun_count",0))>0 and int(j.index)<j.times.size() and not j.attack.get("ignore_stun",false):s.job={};return false
		var a:Dictionary=j.attack
		var target:Dictionary=sim.unit_by_id(j.target)
		if int(j.index)<j.times.size() and not j.dodge_checked:
			var dodge:Dictionary=sim.unit_template(target).get("dodge",{}) if not target.is_empty() else {}
			var time:float=float(j.times[j.index])-float(dodge.time_before_hit) if dodge.has("time_before_hit") else float(a.get("dodge_time",j.times[j.index]))
			if float(sim.tick)/30-float(j.at)/30>=time:
				j.dodge_checked=true;j.dodged=not dodge.is_empty() and sim.rng.randf()<=float(dodge.get("chance",0))
		while int(j.index)<j.times.size() and float(sim.tick)/30-float(j.at)/30>=float(j.times[j.index]):
			j.hit=true;j.index+=1
			var victims:Array=sim.soldiers.filter(func(v):return Targets.matches(sim,v,a) and sim.distance(j.point,v.pos)<=float(a.damage_radius))
			for victim:Dictionary in victims.slice(0,int(a.count)):
				if victim.id==j.target and j.dodged:continue
				sim.damage(victim,sim.rng.randi_range(int(a.damage_min),int(a.damage_max))*sim.attack_factor(e),int(a.damage_type),e.id)
			if a.has("sound_hit"):sim.event.emit("sound",{"id":a.sound_hit})
			if a.has("hit_decal"):sim.add_effect(a.hit_decal,j.point)
			if a.has("hit_fx") and (not a.get("hit_fx_once",false) or int(j.index)==1):
				sim.add_effect(a.hit_fx,j.point+sim.vec(a.get("hit_fx_offset",{"x":0,"y":0}))*Vector2(-1 if e.flip else 1,1),{"flip":e.flip if a.get("hit_fx_flip",false) else false})
			j.dodge_checked=false;j.dodged=false
		if sim.tick<int(j.end):return true
		s.job={};return true
	var attack:Dictionary=j.attack
	if j.kind=="soul":
		if int(e.get("stun_count",0))>0 or s.signal:s.soul_ts=sim.tick+sim.frames(0.2)-sim.frames(attack.cooldown);s.job={};return true
		var elapsed:float=float(sim.tick)/30-float(j.at)/30
		if elapsed<float(attack.kill_start_time):return true
		if not j.hit:j.hit=true;sim.event.emit("sound",{"id":attack.sound})
		if elapsed<=float(attack.kill_end_time):
			if elapsed>=float(attack.get("loop_start_time",attack.kill_start_time)) and e.state!=attack.animation_hold:play(sim,e,attack.animation_hold,true)
			for target:Dictionary in soul_targets(sim,e,attack):
				if j.drained.has(target.id):continue
				j.drained.append(target.id)
				var from:Vector2=target.pos+sim.vec(sim.unit_template(target).unit.mod_offset)
				var to:Vector2=e.pos+sim.vec(attack.soul_hand_offset)*Vector2(-1 if e.flip else 1,1)
				var travel:float=from.distance_to(to)/float(attack.soul_speed)
				_soul(sim,from,(to-from).angle(),1,float(attack.soul_speed),travel)
				j.last_arrival=maxi(int(j.last_arrival),sim.tick+sim.frames(travel))
				sim.damage(target,target.max_hp+1,int(sim.data.constants.DAMAGE_DISINTEGRATE)|int(sim.data.constants.DAMAGE_INSTAKILL),e.id)
				e.hp=minf(e.max_hp,e.hp+e.max_hp*float(attack.heal_hp_factor))
			return true
		if sim.tick<int(j.last_arrival):return true
		if not j.ending:
			j.ending=true;play(sim,e,attack.animation_end);j.end=sim.tick+duration(sim,e,attack.animation_end)+sim.frames(attack.get("animation_end_extra_time",0));return true
	elif not j.hit and sim.tick>=int(j.hit_at):
		j.hit=true;sim.event.emit("sound",{"id":attack.sound})
		if j.kind=="block":
			for tower:Dictionary in j.targets:block_tower(sim,tower,e.id)
		elif j.kind=="portal":
			s.portal_count+=1
			for portal:Dictionary in portals:
				if portal.index<=attack.portals.size() and int(attack.portals[portal.index-1])==1:portal.signal=true
	if sim.tick<int(j.end):return true
	s[j.kind+"_ts"]=sim.tick;s.job={}
	if s.phase=="castle":play(sim,e,"idleDown",true)
	return true

func melee(sim,e:Dictionary,target:Dictionary) -> void:
	var s:Dictionary=e.veznan
	if not s.job.is_empty():return
	var a:Dictionary=sim.templates[e.template].melee.attacks[1 if s.phase=="demon" else 0]
	if float(sim.tick-int(s.attack_ts))/30<float(a.cooldown):play(sim,e,"idle",true);return
	if not Targets.matches(sim,target,a):return
	s.attack_ts=sim.tick;e.flip=target.pos.x<e.pos.x
	play(sim,e,a.animation)
	s.job={"kind":"melee","attack":a,"at":sim.tick,"end":sim.tick+duration(sim,e,a.animation),"target":target.id,"point":e.pos+sim.vec(a.hit_offset)*Vector2(-1 if e.flip else 1,1),"times":a.get("hit_times",[a.hit_time]),"index":0,"hit":false,"dodge_checked":false,"dodged":false}
	if a.has("sound"):sim.event.emit("sound",{"id":a.sound})

func _clear_enemies(sim,e:Dictionary) -> void:
	for other:Dictionary in sim.enemies.duplicate():
		if other.id==e.id or other.hp<=0:continue
		other.gold_override=0;sim.damage(other,other.hp+other.max_hp,1)
	for item:Dictionary in sim.spawners:item.interrupted=true
	sim.pending_entities.clear()
	for p:Dictionary in portals:p.queue.clear();p.signal=false;p.state="idle"

func step_enemy(sim,e:Dictionary,t:Dictionary) -> bool:
	var s:Dictionary=e.veznan
	if _job(sim,e):return true
	match s.phase:
		"waiting":
			if sim.tick<int(s.welcome_next):return true
			s.phase="welcome";s.at=sim.tick;s.welcome_next=sim.tick+sim.frames(t.taunts.sets.welcome.delays[0])
		"welcome":
			if sim.wave>0:
				if not s.get("welcome_battle",false):
					s.welcome_battle=true;say(sim,e,"welcome",5);return true
				s.phase="castle";s.signal=false;s.last_lives=sim.lives;s.block_ts=sim.tick;s.portal_ts=sim.tick;s.soul_ts=sim.tick;s.taunt_ts=sim.tick;s.taunt_delay=sim.frames(sim.rng.randf_range(t.taunts.delay_min,t.taunts.delay_max))
			elif s.welcome_index<4 and sim.tick>=int(s.welcome_next):
				s.welcome_index+=1;say(sim,e,"welcome",s.welcome_index)
				if s.welcome_index<4:s.welcome_next=sim.tick+sim.frames(t.taunts.duration)+sim.frames(t.taunts.sets.welcome.delays[s.welcome_index])
		"castle", "battle":
			if s.signal:
				if s.phase=="castle":
					s.phase="pre_battle";s.at=sim.tick;s.signal=false;s.stage=0
				else:
					s.phase="transform";s.at=sim.tick;e.health_bar_hidden=true;e.vis.bans=4294967295
					for m:Dictionary in sim.modifiers.active.duplicate():
						if m.target==e.id:sim.modifiers._release(sim,m);sim.modifiers.active.erase(m)
					play(sim,e,"demonTransform");sim.event.emit("sound",{"id":t.demon.transform_sound})
				return true
			if s.phase=="castle" and sim.wave!=int(s.last_wave):
				s.last_wave=sim.wave
				for pair:Array in [["block",0],["portal",1]]:
					var rows:Variant=t.timed_attacks.list[pair[1]].get("data",{})
					var row:Variant=rows.get(str(sim.wave),[]) if rows is Dictionary else rows[sim.wave-1] if sim.wave>0 and sim.wave<=rows.size() else []
					s[pair[0]+"_data"]=row if row is Array else []
				if not s.portal_data.is_empty():s.portal_count=0
			if s.phase=="castle" and sim.tick-int(s.taunt_ts)>=int(s.taunt_delay):
				say(sim,e,"damage" if sim.lives<int(s.last_lives) else "castle");s.job.reschedule=true;return true
			if int(e.get("stun_count",0))>0:play(sim,e,"idle",true);return true
			if int(e.get("silence_count",0))==0:
				for pair:Array in [["block",0],["portal",1],["soul",2]]:
					var kind:String=pair[0];var attack:Dictionary=t.timed_attacks.list[pair[1]].duplicate(true)
					if kind in ["block","portal"]:
						var row:Array=s.get(kind+"_data",[])
						if row.is_empty():continue
						attack.cooldown=row[0]
						if kind=="block":attack.count=row[1]
						else:
							attack.portals=row[2];attack.max_count=row[1]
							if s.phase=="battle":attack.cooldown=t.battle.pa_cooldown;attack.max_count=t.battle.pa_max_count
							if int(s.portal_count)>=int(attack.max_count):continue
						if s.phase=="battle":attack.animation=t.battle["ba_animation" if kind=="block" else "pa_animation"]
					if (float(sim.tick)/30-float(s[kind+"_ts"])/30)<=float(attack.cooldown):continue
					if kind=="block" and not sim.towers.any(func(tower):return sim.tower_template(tower).tower.get("can_be_mod",false) and not blocks.any(func(b):return b.tower==tower.id)):
						s.block_ts=sim.tick+15-sim.frames(attack.cooldown);continue
					if kind=="soul" and soul_targets(sim,e,attack).is_empty():s.soul_ts=sim.tick+6-sim.frames(attack.cooldown);continue
					_start_cast(sim,e,kind,attack);return true
			return s.phase=="castle"
		"pre_battle":
			if int(s.stage)==0 and sim.tick-int(s.at)>=24:s.stage=1;say(sim,e,"pre_battle",30)
			elif int(s.stage)==1 and sim.tick-int(s.at)>=115:s.stage=2;play(sim,e,"walkAway");s.next=sim.tick+duration(sim,e,"walkAway")
			elif int(s.stage)==2 and sim.tick>=int(s.next):
				e.pos=sim.vec(sim.data.paths.paths[0][0][0]);e.node=0;e.progress=0;e.path=0;e.subpath=0;e.ignore_damage=false;e.vis.bans=int(t.vis.bans)&~4294967295;e.health_bar_hidden=false
				s.phase="battle";s.signal=false;s.portal_ts=sim.tick;s.block_ts=sim.tick;s.soul_ts=sim.tick
		"transform":
			if sim.tick-int(s.at)>=duration(sim,e,"demonTransform"):
				e.hp=float(s.initial_hp)*1.5;e.max_hp=e.hp;e.prefix=t.demon.sprites_prefix;e.speed_override=t.demon.speed
				e.click_rect=t.demon.ui_click_rect;e.portrait=t.demon.info_portrait
				e.vis.bans=0;e.health_bar_hidden=false;e.melee_slot_override=sim.vec(t.demon.melee_slot)
				e.combat_template=t.duplicate(true)
				e.combat_template.unit.hit_offset=t.demon.unit_hit_offset
				e.combat_template.unit.mod_offset=t.demon.unit_mod_offset
				e.combat_template.unit.size=t.demon.unit_size
				e.combat_template.motion.max_speed=t.demon.speed
				e.combat_template.melee.attacks=[t.melee.attacks[1]]
				s.phase="demon";s.signal=false;play(sim,e,"idle",true)
		"demon":
			if s.signal:
				s.phase="death";s.at=sim.tick;s.stage=0;e.ignore_damage=true;e.health_bar_hidden=true;e.can_click=false;e.vis.bans=4294967295;hud_hidden=true
				_clear_enemies(sim,e);sim.event.emit("stop_audio",{});sim.event.emit("sound",{"id":t.sound_events.death});play(sim,e,"death")
				for tower:Dictionary in sim.towers:tower.blocked=true
				return true
			if int(e.get("stun_count",0))>0:play(sim,e,"idle",true);return true
			return false
		"death":
			if int(s.stage)==0 and sim.tick-int(s.at)>=110:
				s.stage=1;_clear_enemies(sim,e);soul_aura={"pos":e.pos+Vector2(0,14),"count":0,"delay":int(sim.templates.veznan_souls_aura.souls.delay_frames),"next":sim.tick}
			if int(s.stage)==1 and sim.tick-int(s.at)>=duration(sim,e,"death"):
				s.stage=2;play(sim,e,"deathLoop",true);s.next=sim.tick+90
			elif int(s.stage)==2 and sim.tick>=int(s.next):
				s.stage=3;soul_aura.interrupt=true;_clear_enemies(sim,e);play(sim,e,"deathEnd",true);white={"pos":e.pos+Vector2(6,12),"at":sim.tick};s.next=sim.tick+125
			elif int(s.stage)==3 and sim.tick>=int(s.next):
				s.phase="death-end";e.hidden=true;e.remove_now=true;e.hp=0;e.dead_at=sim.tick;e.boss.death_handled=true;complete=true
	return true

func step(sim) -> void:
	step_blocks(sim);step_portals(sim);step_souls(sim)
	if not taunt.is_empty() and sim.tick-int(taunt.at)>=int(taunt.duration):taunt.clear()

func queue(view) -> void:
	var sim=view.sim
	for p:Dictionary in portals:view._queue_template(p.template,p.pos,p.state,p.at,false,false,1,false,"",{"playback_loop":p.state in ["idle","active"]})
	for b:Dictionary in blocks:
		var tower:Dictionary=sim.tower_by_id(b.tower)
		if not tower.is_empty():view._queue_template("mod_veznan_tower",tower.pos,b.phase,b.at,false,false,1,false,"",{"playback_loop":b.phase=="preHold","layers":{2:{"visible":b.phase=="preHold","state":"","at":b.at,"loop":true}}})
	for s:Dictionary in souls:view._queue_template("veznan_soul",s.pos,"",s.at,false,false,1,false,"",{"rotation":float(s.angle)+float(s.variation)})
	if not white.is_empty():
		view._queue_template("decal_eb_veznan_white_circle",white.pos,"",white.at,false,false,1,false,"",{"playback_loop":false})
