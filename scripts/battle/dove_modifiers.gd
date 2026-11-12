extends RefCounted
## Selected frozen mod_lifecycle/mod_dps/mod_thorn semantics, not a full ECS.
const Anim = preload("res://scripts/battle/dove_animation.gd")
var active: Array = []

func flags_match(sim: RefCounted, target: Dictionary, rule: Dictionary) -> bool:
	var vis: Dictionary = target.get("vis", sim.templates[target.template].get("vis", {}))
	return (int(vis.get("bans", 0)) & int(rule.get("vis_flags", 0))) == 0 and (int(vis.get("flags", 0)) & int(rule.get("vis_bans", 0))) == 0

func has(target_id: int, template: String) -> bool:
	return active.any(func(m): return m.target == target_id and m.template == template)

func count(target_id: int, template: String) -> int:
	return active.filter(func(m): return m.target == target_id and m.template == template).size()

func speed(target_id: int, sim: RefCounted) -> float:
	var factor := 1.0
	var target: Dictionary = sim.unit_by_id(target_id)
	if not target.is_empty(): factor = (float(sim.templates[target.template].motion.max_speed)+float(target.get("speed_bonus",0)))/float(sim.templates[target.template].motion.max_speed)
	for m: Dictionary in active:
		if m.target == target_id: factor *= float(sim.templates[m.template].get("slow", {}).get("factor", 1.0))
	return factor

func clear(sim: RefCounted) -> void:
	for m: Dictionary in active: _release(sim, m)
	active.clear()

func _release(sim: RefCounted, m: Dictionary) -> void:
	if m.template=="mod_skeleton_big":
		var target:Dictionary=sim.unit_by_id(m.target)
		if not target.is_empty():sim.DamageFactors.change(target,sim.templates[target.template],1-float(sim.templates[m.template].health_damage_factor_dec),true,true)
	if m.has("armor_added") and not m.get("rage",false):
		var unit:Dictionary=sim.unit_by_id(m.target)
		if not unit.is_empty():unit.armor=float(unit.get("armor",sim.templates[unit.template].health.armor))-float(m.armor_added)
	if m.has("fast_added"):
		var unit:Dictionary=sim.unit_by_id(m.target)
		if not unit.is_empty():unit.speed_bonus=float(unit.get("speed_bonus",0))-float(m.fast_added);unit.erase("walk_angles")
	if m.get("rage",false):
		var target: Dictionary = sim.unit_by_id(m.target)
		if not target.is_empty():
			var t: Dictionary = sim.templates[m.template]
			target.speed_bonus=float(target.get("speed_bonus",0))-float(t.extra_speed)
			target.melee_damage_min_bonus=float(target.get("melee_damage_min_bonus",0))-float(t.extra_damage_min)
			target.melee_damage_max_bonus=float(target.get("melee_damage_max_bonus",0))-float(t.extra_damage_max)
			target.armor=maxf(0,float(target.get("armor",sim.templates[target.template].health.armor))-float(m.get("armor_added",0)))
	if m.get("silence", false):
		var unit: Dictionary = sim.unit_by_id(m.target)
		if not unit.is_empty():
			unit.silence_count = maxi(0, int(unit.get("silence_count", 0)) - 1)
			if unit.silence_count == 0:
				var duration: int = sim.tick - int(unit.silence_at)
				unit.heal_at += duration
				if unit.has("ranged_at"): unit.ranged_at += duration
				if unit.has("egg_at"): unit.egg_at += duration
	if m.get("special", "") == "teleport":
		var target: Dictionary = sim.unit_by_id(m.target)
		if not target.is_empty(): target.hidden = false; target.stun_count = maxi(0, int(target.get("stun_count", 0)) - 1)
	if m.template != "mod_thorn" and not m.get("stun",false): return
	var target: Dictionary = sim.unit_by_id(m.target)
	if not target.is_empty(): target.stun_count = maxi(0, int(target.get("stun_count", 0)) - 1)

func apply(sim: RefCounted, template: String, target: Dictionary, level: int, source: String, duration: float = -1, damage_factor: float = 1.0, source_damage: Dictionary = {}) -> bool:
	if target.is_empty() or target.hp <= 0 or level <= 0 or not sim.templates.has(template): return false
	var t: Dictionary = sim.templates[template]
	if sim.behaviors.role(template) in ["arcane_damage", "disintegrate", "teleport"]: return sim.Behaviors.Arcane.apply(sim, template, target, level, source, damage_factor)
	var rule: Dictionary = t.modifier
	if t.has("armor_buff") and not sim.templates[target.template].get("enemy",{}).get("can_accept_magic",true):return false
	if sim.behaviors.role(template)=="polymorph":return sim.Behaviors.Sorcerer.polymorph(sim,target,t)
	if t.has("hps") and target.hp==target.max_hp:return false
	if not flags_match(sim, target, rule): return false
	if target.template in rule.get("excluded_templates", []): return false
	if sim.behaviors.role(template) == "instant_damage":
		sim.damage(target, float(t.damage_min) * damage_factor, int(t.damage_type), int(source)); return false
	if template == "mod_slow_curse" and active.any(func(m): return m.target == target.id and sim.templates[m.template].modifier.get("type", "") == "rage"): return false
	var bleeding := -1.0
	if template == "mod_blood_elves":
		if sim.rng.randf() >= float(t.chance): return false
		var same: Array = active.filter(func(m): return m.target == target.id and sim.templates[m.template].modifier.get("type", "") == rule.type)
		if same.size() >= int(rule.max_of_same) or source_damage.is_empty(): return false
		var health: Dictionary = sim.templates[target.template].health
		var armor := 0.0
		if (int(source_damage.type) & 2) != 0: armor = clampf(float(target.get("armor", health.armor)) - float(source_damage.get("reduce_armor",0)), 0, 1)
		elif (int(source_damage.type) & 64) != 0: armor = clampf(float(target.get("armor", health.armor)) - float(source_damage.get("reduce_armor",0)), 0, 1) * 0.7
		bleeding = maxf(1.0, float(source_damage.value) * (1 - armor) * sim.DamageFactors.value(target, sim.templates[target.template], true) * float(t.damage_factor))
		for old: Dictionary in same: old.bleed_fx = false
	for existing: Dictionary in active.duplicate():
		if existing.target != target.id: continue
		var other: Dictionary = sim.templates[existing.template].modifier
		if template in other.get("bans", []): return false
		if rule.get("remove_banned", false) and (existing.template in rule.get("bans", []) or other.get("type", "") in rule.get("ban_types", [])):
			_release(sim, existing); active.erase(existing)
	var duplicates := 0
	for m: Dictionary in active:
		if m.target != target.id or m.template != template: continue
		if level < m.level: return false
		if level == m.level:
			if rule.has("max_duplicates"):
				duplicates += 1
				# BASE counts *other* copies; max_duplicates=3 admits four in total.
				if duplicates > int(rule.max_duplicates): return false
			elif not rule.get("allows_duplicates",false):
				m.expires = sim.tick + sim.frames(minf(30000000,duration if duration >= 0 else float(rule.duration)))
				return false
	for m: Dictionary in active.duplicate():
		if m.target == target.id and m.template == template and level > m.level:
			_release(sim, m); active.erase(m)
		elif m.target == target.id and m.template == template:
			m.visible = false
	var size_index := clampi(int(sim.unit_template(target).unit.size) - 1, 0, 2)
	var m := {"template":template, "target":target.id, "level":level, "source":source, "born":sim.tick,
		"at":sim.tick, "expires":sim.tick + mini(1000000000,sim.frames(minf(30000000,duration if duration >= 0 else float(rule.duration)))), "next_hit":sim.tick + 1,
		"state":"", "prefix":"", "scale":Vector2.ONE, "phase":"loop", "visible":true}
	if damage_factor != 1.0: m.damage_factor = damage_factor
	if bleeding >= 0: m.bleeding = bleeding; m.damage_factor = 1.0; m.bleed_fx = true; m.next_hit = sim.tick + 1; m.last_fx = 0; m.damage_ts = sim.tick / 30.0 - float(t.dps.damage_every)
	if template == "mod_thorn":
		var sprite: Dictionary = t.render.sprites[0]
		m.prefix = sprite.size_prefixes[size_index]; m.scale = sim.vec(sprite.size_scales[size_index])
		m.state = "start"; m.phase = "start"
		m.loop_at = sim.tick + Anim.duration(sim.animations, m.prefix + "_start")
		m.expires += int(m.loop_at) - sim.tick
		m.next_hit = int(m.loop_at) + sim.frames(t.damage_every)
		target.stun_count = int(target.get("stun_count", 0)) + 1
		target.pending = {}; target.casting = {}; target.last_dir = Vector2.ZERO
		sim._state(target, "idle", true)
	elif t.has("render"):
		m.state = t.render.sprites[0].get("size_names",["","",""])[size_index]
	if sim.behaviors.role(template)=="stun_modifier":
		m.stun=true;target.stun_count=int(target.get("stun_count",0))+1
		m.prefix=str(t.render.sprites[0].prefix)+"_"+str(t.render.sprites[0].size_names[size_index]);m.state="loop"
		target.pending={};target.last_dir=Vector2.ZERO
	if template == "mod_paladin_silence":
		m.silence = true
		if int(target.get("silence_count", 0)) == 0: target.silence_at = sim.tick
		target.silence_count = int(target.get("silence_count", 0)) + 1
	if template == "mod_troll_rage":
		m.rage=true
		target.speed_bonus=float(target.get("speed_bonus",0))+float(t.extra_speed)
		target.melee_damage_min_bonus=float(target.get("melee_damage_min_bonus",0))+float(t.extra_damage_min)
		target.melee_damage_max_bonus=float(target.get("melee_damage_max_bonus",0))+float(t.extra_damage_max)
		if target.template not in ["enemy_troll_brute","enemy_troll_chieftain"]:
			var previous:=float(target.get("armor",sim.templates[target.template].health.armor))
			target.armor=clampf(previous+float(t.extra_armor),0,0.99)
			m.armor_added=float(target.armor)-previous
	if t.has("hps"):m.next_heal=sim.tick+1
	if t.has("armor_buff"):
		var armor:float=float(target.get("armor",sim.templates[target.template].health.armor))
		m.armor_added=armor*float(t.armor_buff.factor);target.armor=armor+float(m.armor_added)
	if template=="mod_rocketeer_speed_buff":
		m.fast_added=(float(sim.templates[target.template].motion.max_speed)+float(target.get("speed_bonus",0)))*(float(t.fast.factor)-1)
		target.speed_bonus=float(target.get("speed_bonus",0))+float(m.fast_added);target.already_speed_up=true;target.walk_angles=t.walk_angles
		sim.event.emit("sound",{"id":t.sound_events.insert})
	if template=="mod_demon_shield":m.shield_hits=0;m.shield_sources=[]
	if template=="mod_skeleton_big":sim.DamageFactors.change(target,sim.templates[target.template],1-float(t.health_damage_factor_dec),true)
	if template=="mod_tesla_overcharge" and sim.rng.randf()<float(t.stun_chance) and (int(target.get("vis",sim.templates[target.template].vis).bans)&int(sim.data.constants.F_STUN))==0 and (int(target.get("vis",sim.templates[target.template].vis).flags)&int(sim.data.constants.F_BOSS))==0:
		m.stun=true;target.stun_count=int(target.get("stun_count",0))+1
	active.append(m)
	sim.event.emit("modifier_applied", {"template":template,"target":target.id,"level":level})
	return true

func step(sim: RefCounted) -> void:
	for m: Dictionary in active.duplicate():
		if not active.has(m): continue
		var target: Dictionary = sim.unit_by_id(m.target)
		if target.is_empty() or target.hp <= 0:
			_release(sim, m); active.erase(m); continue
		var t: Dictionary = sim.templates[m.template]
		if sim.Behaviors.Arcane.modifier_step(sim, m, target, t): continue
		if m.template == "mod_thorn":
			if m.phase == "start" and sim.tick >= m.loop_at:
				m.phase = "loop"; m.state = "loop"; m.at = m.loop_at
			if m.phase != "end" and sim.tick > m.expires:
				m.phase = "end"; m.state = "end"; m.at = sim.tick
				m.remove_at = sim.tick + Anim.duration(sim.animations, m.prefix + "_end")
			if m.phase == "end":
				if sim.tick >= m.remove_at: _release(sim, m); active.erase(m)
				continue
			if m.phase == "loop" and sim.tick >= m.next_hit:
				m.next_hit += sim.frames(t.damage_every)
				sim.damage(target, float(t.damage_min) * float(m.get("damage_factor",1.0)), int(t.damage_type))
		else:
			if (sim.tick > m.expires if m.get("rage",false) or t.has("hps") else sim.tick >= m.expires): _release(sim, m); active.erase(m); continue
			if t.has("hps") and float(sim.tick)>=float(m.next_heal):
				var hps:Dictionary=t.hps
				m.next_heal=float(sim.tick)+float(hps.heal_every)*30
				var minimum:=int(hps.heal_min)+int(hps.get("heal_min_inc",hps.get("heal_inc",0)))*int(m.level)
				var maximum:=int(hps.heal_max)+int(hps.get("heal_max_inc",hps.get("heal_inc",0)))*int(m.level)
				target.hp=minf(float(target.max_hp)*float(hps.get("overflow_factor",1)),float(target.hp)+sim.rng.randi_range(minimum,maximum))
			if m.template=="mod_ray_tesla":
				var every:float=float(sim.frames(float(t.dps.damage_every)))/30
				if sim.tick<int(m.born) or float(sim.tick)/30-float(m.damage_ts)<every:continue
				m.damage_ts+=every;m.next_hit=sim.tick
			if t.has("dps") and sim.tick >= m.next_hit:
				if m.has("bleeding"):
					m.damage_ts += float(t.dps.damage_every)
					m.next_hit = maxi(sim.tick + 1, ceili((float(m.damage_ts) + float(t.dps.damage_every)) * 30.0 - 0.0000001))
				else: m.next_hit += sim.frames(t.dps.damage_every)
				var amount := float(int(m.bleeding)) if m.has("bleeding") else float(m.get("damage",t.dps.get("damage_min",0))) + float(t.dps.get("damage_inc",0)) * int(m.level)
				sim.damage(target, amount * float(m.get("damage_factor",1.0)), int(t.dps.damage_type), int(m.source))
				if t.dps.get("fx","") != "" and m.get("bleed_fx", true) and (not m.has("bleeding") or sim.tick - int(m.last_fx) >= sim.frames(t.dps.fx_every)):
					if m.has("bleeding"): m.last_fx = sim.tick
					var unit: Dictionary = sim.templates[target.template].unit
					if unit.get("blood_color"):
						var size: String = "small" if int(unit.size) == 1 else "big"
						sim.add_effect(t.dps.fx,target.pos,{"target":target.id,"state":size + "_" + str(unit.blood_color),"flip":target.flip if t.dps.get("fx_target_flip",false) else false})
		if target.hp <= 0: _release(sim, m); active.erase(m)

func remaining(target_id: int, sim: RefCounted) -> float:
	var ticks := 0
	for m: Dictionary in active:
		if m.target == target_id and m.template == "mod_thorn": ticks = maxi(ticks, int(m.get("remove_at", m.expires)) - sim.tick)
	return ticks / 30.0
