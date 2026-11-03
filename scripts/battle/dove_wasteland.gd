extends RefCounted
## Shared demon and skeleton behaviors. Per-battle state, no level IDs.
const Anim = preload("res://scripts/battle/dove_animation.gd")
var blasts:Array=[]

func reset() -> void:blasts.clear()

func died(sim, enemy:Dictionary, damage_type:int) -> void:
	var t:Dictionary=sim.templates[enemy.template]
	if enemy.get("source_corpse",false) and t.unit.get("can_disintegrate",false) and ((damage_type&8192)!=0 or (t.unit.get("disintegrate_when_silenced_death",false) and int(enemy.get("silence_count",0))>0)):
		enemy.hidden=true
		var fx:String=str(t.unit.get("disintegrate_fx",""))
		if not fx.is_empty():
			var sprite:Dictionary=sim.templates[fx].render.sprites[0]
			var states:Array=sprite.get("size_names",[])
			sim.add_effect(fx,enemy.pos,{"state":str(states[int(t.unit.get("size",1))-1]) if not states.is_empty() else str(sprite.name)})
	if not t.has("death_spawns") or (damage_type&(16384|16777216|int(t.death_spawns.get("no_spawn_damage_types",0))))!=0:return
	var spawn:Dictionary=t.death_spawns
	if not str(spawn.get("name","")).begins_with("aura_demon_"):return
	blasts.append({"template":spawn.name,"pos":enemy.pos,"at":sim.tick+1,"factor":sim.DamageFactors.value(enemy,t)})

func step(sim) -> void:
	for blast:Dictionary in blasts.duplicate():
		if sim.tick<blast.at:continue
		var a:Dictionary=sim.templates[blast.template].aura
		for s:Dictionary in sim.soldiers:
			if s.hp<=0 or s.template in a.get("excluded_templates",[]) or not sim.modifiers.flags_match(sim,s,a) or sim.distance(blast.pos,s.pos)>float(a.radius):continue
			sim.damage(s,sim.rng.randi_range(int(a.damage_min),int(a.damage_max))*float(blast.factor),int(a.damage_type))
		blasts.erase(blast)
	for e:Dictionary in sim.enemies:
		if e.template!="enemy_skeleton_big" or e.hp<=0 or sim.tick<int(e.skeleton_aura_at):continue
		var a:Dictionary=sim.templates.aura_skeleton_big.aura
		e.skeleton_aura_at=sim.tick+sim.frames(float(a.cycle_time))
		if int(e.get("silence_count",0))>0:continue
		for target:Dictionary in sim.enemies:
			if target.hp>0 and target.template in a.allowed_templates and sim.distance(e.pos,target.pos)<=float(a.radius):sim.modifiers.apply(sim,a.mod,target,1,str(e.id))

static func inserted(sim, enemy:Dictionary) -> void:
	if enemy.template in ["enemy_demon","enemy_demon_wolf","enemy_demon_mage","enemy_skeleton","enemy_skeleton_big"]:enemy.source_corpse=true
	if enemy.template=="enemy_demon_mage":enemy.shield_at=sim.tick;enemy.shield_job={}
	if enemy.template=="enemy_skeleton_big":enemy.skeleton_aura_born=sim.tick;enemy.skeleton_aura_at=sim.tick+sim.frames(float(sim.templates.aura_skeleton_big.aura.delay))

static func enemy_step(sim, enemy:Dictionary, t:Dictionary) -> bool:
	if enemy.has("raise_until"):
		if sim.tick<int(enemy.raise_until):return true
		enemy.erase("raise_until");enemy.health_bar_hidden=false
	if enemy.has("forced_waypoint"):
		var before:Vector2=enemy.pos
		enemy.pos=enemy.pos.move_toward(enemy.forced_waypoint,float(t.motion.max_speed)*float(sim.data.rules.enemy_speed_factor)/30)
		enemy.last_dir=enemy.pos-before;enemy.flip=enemy.last_dir.x<0
		sim._state(enemy,"walkingRightLeft" if absf(enemy.last_dir.x)>absf(enemy.last_dir.y) else ("walkingUp" if enemy.last_dir.y>0 else "walkingDown"))
		if enemy.pos.is_equal_approx(enemy.forced_waypoint):enemy.erase("forced_waypoint")
		return true
	if not enemy.has("shield_job"):return false
	var a:Dictionary=t.timed_attacks.list[0]
	if int(enemy.get("stun_count",0))>0 or int(enemy.get("silence_count",0))>0:enemy.shield_job={};return false
	var job:Dictionary=enemy.shield_job
	if not job.is_empty():
		if not job.fired and sim.tick>=job.fire:
			job.fired=true
			var count:=0
			for target:Dictionary in sim.enemies:
				if count>=int(a.max_count[int(sim.data.level.difficulty)-1]):break
				if target.hp>0 and target.template in a.allowed_templates and sim.modifiers.flags_match(sim,target,a) and sim.distance(enemy.pos,target.pos)<=float(a.max_range):
					sim.modifiers.apply(sim,a.mod,target,1,str(enemy.id));count+=1
		if sim.tick<job.end:return true
		enemy.shield_job={}
	if float(sim.tick)/30-float(enemy.shield_at)/30<=float(a.cooldown):return false
	var targets:Array=sim.enemies.filter(func(e):return e.hp>0 and e.template in a.allowed_templates and sim.modifiers.flags_match(sim,e,a) and sim.distance(enemy.pos,e.pos)<=float(a.max_range))
	if targets.is_empty():enemy.shield_at=sim.tick-sim.frames(float(a.cooldown))+15;return false
	enemy.shield_at=sim.tick;enemy.pending={};enemy.last_dir=Vector2.ZERO
	sim._state(enemy,a.animation,true);sim.event.emit("sound",{"id":a.sound})
	enemy.shield_job={"fire":sim.tick+sim.frames(float(a.cast_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[0],a.animation)),"fired":false}
	return true

static func shield_damage(sim, target:Dictionary, damage_type:int, source:int) -> bool:
	for m:Dictionary in sim.modifiers.active.duplicate():
		if m.target!=target.id or m.template!="mod_demon_shield":continue
		if (damage_type&(4096|8192|16384|int(sim.data.constants.DAMAGE_IGNORE_SHIELD)))!=0:
			sim.modifiers._release(sim,m);sim.modifiers.active.erase(m);return false
		if (damage_type&int(sim.data.constants.DAMAGE_ONE_SHIELD_HIT))!=0:
			if source not in m.shield_sources:m.shield_sources.append(source);m.shield_hits+=1
		elif (damage_type&int(sim.data.constants.DAMAGE_NO_SHIELD_HIT))==0:m.shield_hits+=1
		if int(m.shield_hits)>=int(sim.templates[m.template].shield_ignore_hits):sim.modifiers._release(sim,m);sim.modifiers.active.erase(m)
		return true
	return false

func queue(view) -> void:
	for e:Dictionary in view.sim.enemies:
		if e.template!="enemy_skeleton_big" or e.hp<=0:continue
		var delay:int=view.sim.frames(float(view.sim.templates.aura_skeleton_big.aura.delay))
		var born:int=int(e.get("skeleton_aura_born",e.state_at))+delay
		if view.sim.tick<born or int(e.get("silence_count",0))>0:continue
		var alpha:float=clampf(float(view.sim.tick-born)/20,0,1)
		# Source starts both alpha tracks after the one-second delay.
		view._queue_template("aura_skeleton_big",e.pos,"",born,false,false,1,false,"",{"layers":{1:{"alpha":alpha},2:{"alpha":alpha}}})
