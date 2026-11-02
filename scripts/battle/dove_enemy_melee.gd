extends RefCounted
## enemy_mixed melee coroutine for the eighth-stage enemies, including its
## post-hit animation wait. The area keeps source soldier ordering and hit origin.
const Anim = preload("res://scripts/battle/dove_animation.gd")
const Targets = preload("res://scripts/battle/dove_targeting.gd")
const Ranged = preload("res://scripts/battle/dove_enemy_ranged.gd")

static func step(sim, enemy: Dictionary, template: Dictionary) -> bool:
	if not enemy.mixed_melee_job.is_empty():
		var job: Dictionary = enemy.mixed_melee_job
		var attack: Dictionary = template.melee.attacks[0]
		if job.has("sound_at") and not job.get("sound_played",false) and sim.tick>=job.sound_at:
			job.sound_played=true;sim.event.emit("sound",{"id":attack.sound})
		if not job.hit:
			if sim.tick < job.hit_at and int(enemy.get("stun_count",0)) > 0 and not attack.get("ignore_stun",false):
				enemy.mixed_melee_job = {}; return false
			var target: Dictionary = sim.unit_by_id(job.target)
			if not job.dodge_checked and sim.tick >= job.dodge_at:
				job.dodge_checked = true
				if not target.is_empty(): job.dodged = sim.rng.randf() <= float(sim.templates[target.template].get("dodge",{}).get("chance",0))
			if sim.tick >= job.hit_at:
				job.hit = true
				if not job.has("sound_at") and attack.get("sound_args",{}).get("delay",0) > 0: sim.event.emit("sound",{"id":attack.sound})
				if attack.type == "area":
					var count := 0
					for soldier: Dictionary in sim.soldiers:
						if not Targets.matches(sim,soldier,attack) or sim.distance(job.point,soldier.pos) > float(attack.damage_radius): continue
						if count >= int(attack.get("count",sim.soldiers.size())): break
						count += 1
						if soldier.id != job.target or not job.dodged: _damage(sim,enemy,soldier,attack)
				elif not target.is_empty() and enemy.blockers.has(target.id) and not job.dodged:
					_damage(sim,enemy,target,attack)
				for key: String in ["hit_fx","hit_decal"]: sim.add_effect(str(attack.get(key,"")),job.point)
		if sim.tick >= job.end_at:
			enemy.mixed_melee_job = {}; sim._state(enemy,"idle")
		return true
	if int(enemy.get("stun_count",0)) > 0:
		# A stun on the ranged shoot tick still emits; earlier windup stuns cancel.
		if not enemy.get("ranged_cast",{}).is_empty() and not enemy.ranged_cast.fired and sim.tick >= enemy.ranged_cast.at:
			Ranged.step(sim,enemy,template)
		enemy.ranged_cast = {}; return false
	if template.has("ranged"):
		var waiting: bool = not enemy.get("ranged_cast",{}).is_empty()
		var stopped: bool = Ranged.step(sim,enemy,template)
		if waiting and enemy.ranged_cast.is_empty(): sim._state(enemy,"idle"); return true
		return stopped
	return false

static func melee(sim, enemy: Dictionary, target: Dictionary, template: Dictionary) -> void:
	var attack: Dictionary = template.melee.attacks[0]
	if float(sim.tick)/30-float(enemy.get("mixed_melee_ts",0))/30 < float(attack.cooldown):
		sim._state(enemy,"idle"); return
	if not Targets.matches(sim,target,attack): return
	enemy.mixed_melee_ts = sim.tick
	if sim.rng.randf() >= float(attack.chance): return
	enemy.flip = target.pos.x < enemy.pos.x
	var point: Vector2 = enemy.pos + sim.vec(attack.get("hit_offset",{"x":0,"y":0})) * Vector2(-1 if enemy.flip else 1,1)
	var dodge: Dictionary = sim.templates[target.template].get("dodge",{})
	var dodge_time: float = float(attack.get("dodge_time",attack.hit_time))
	if dodge.has("time_before_hit"): dodge_time = float(attack.hit_time) - float(dodge.time_before_hit)
	enemy.mixed_melee_job = {"target":target.id,"point":point,"hit_at":sim.tick+sim.source_wait_ticks(sim.tick,float(attack.hit_time)),
		"end_at":sim.tick+Anim.duration(sim.animations,Anim.key(template.render.sprites[0],attack.animation)),
		"hit":false,"dodged":false,"dodge_checked":dodge.is_empty() or not attack.has("dodge_time"),"dodge_at":sim.tick+sim.source_wait_ticks(sim.tick,dodge_time)}
	sim._state(enemy,attack.animation,true)
	if enemy.has("jt") and float(attack.get("sound_args",{}).get("delay",0))>0:enemy.mixed_melee_job.sound_at=sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(attack.sound_args.delay))
	if attack.has("sound") and attack.get("sound_args",{}).get("delay",0) <= 0: sim.event.emit("sound",{"id":attack.sound})

static func _damage(sim, enemy: Dictionary, soldier: Dictionary, attack: Dictionary) -> void:
	var amount: int = sim.rng.randi_range(int(attack.damage_min)+int(enemy.get("melee_damage_min_bonus",0)),int(attack.damage_max)+int(enemy.get("melee_damage_max_bonus",0)))
	sim.damage(soldier,float(amount)*sim.attack_factor(enemy),int(attack.damage_type),enemy.id)
	if attack.get("side_effect","")=="game_scripts.eb_jt.heal":enemy.hp=minf(enemy.max_hp,enemy.hp+100)
