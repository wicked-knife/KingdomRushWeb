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
	for m: Dictionary in active:
		if m.target == target_id: factor *= float(sim.templates[m.template].get("slow", {}).get("factor", 1.0))
	return factor

func clear(sim: RefCounted) -> void:
	for m: Dictionary in active: _release(sim, m)
	active.clear()

func _release(sim: RefCounted, m: Dictionary) -> void:
	if m.get("silence", false):
		var unit: Dictionary = sim.unit_by_id(m.target)
		if not unit.is_empty():
			unit.silence_count = maxi(0, int(unit.get("silence_count", 0)) - 1)
			if unit.silence_count == 0:
				var duration: int = sim.tick - int(unit.silence_at)
				unit.heal_at += duration
				if unit.has("ranged_at"): unit.ranged_at += duration
	if m.get("special", "") == "teleport":
		var target: Dictionary = sim.unit_by_id(m.target)
		if not target.is_empty(): target.hidden = false; target.stun_count = maxi(0, int(target.get("stun_count", 0)) - 1)
	if m.template != "mod_thorn": return
	var target: Dictionary = sim.unit_by_id(m.target)
	if not target.is_empty(): target.stun_count = maxi(0, int(target.get("stun_count", 0)) - 1)

func apply(sim: RefCounted, template: String, target: Dictionary, level: int, source: String, duration: float = -1, damage_factor: float = 1.0) -> bool:
	if target.is_empty() or target.hp <= 0 or level <= 0 or not sim.templates.has(template): return false
	var t: Dictionary = sim.templates[template]
	if sim.behaviors.role(template) in ["arcane_damage", "disintegrate", "teleport"]: return sim.Behaviors.Arcane.apply(sim, template, target, level, source, damage_factor)
	var rule: Dictionary = t.modifier
	if not flags_match(sim, target, rule): return false
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
				m.expires = sim.tick + sim.frames(duration if duration >= 0 else float(rule.duration))
				return false
	for m: Dictionary in active.duplicate():
		if m.target == target.id and m.template == template and level > m.level:
			_release(sim, m); active.erase(m)
		elif m.target == target.id and m.template == template:
			m.visible = false
	var size_index := clampi(int(sim.templates[target.template].unit.size) - 1, 0, 2)
	var m := {"template":template, "target":target.id, "level":level, "source":source, "born":sim.tick,
		"at":sim.tick, "expires":sim.tick + sim.frames(duration if duration >= 0 else float(rule.duration)), "next_hit":sim.tick + 1,
		"state":"", "prefix":"", "scale":Vector2.ONE, "phase":"loop", "visible":true}
	if damage_factor != 1.0: m.damage_factor = damage_factor
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
	if template == "mod_paladin_silence":
		m.silence = true
		if int(target.get("silence_count", 0)) == 0: target.silence_at = sim.tick
		target.silence_count = int(target.get("silence_count", 0)) + 1
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
			if sim.tick >= m.expires: _release(sim, m); active.erase(m); continue
			if t.has("dps") and sim.tick >= m.next_hit:
				m.next_hit += sim.frames(t.dps.damage_every)
				var amount := float(t.dps.damage_min) + float(t.dps.damage_inc) * int(m.level)
				sim.damage(target, amount * float(m.get("damage_factor",1.0)), int(t.dps.damage_type))
				if t.dps.get("fx","") != "":
					var unit: Dictionary = sim.templates[target.template].unit
					var size: String = "small" if int(unit.size) == 1 else "big"
					sim.add_effect(t.dps.fx,target.pos,{"target":target.id,"state":size + "_" + str(unit.blood_color),"flip":target.flip if t.dps.get("fx_target_flip",false) else false})
		if target.hp <= 0: _release(sim, m); active.erase(m)

func remaining(target_id: int, sim: RefCounted) -> float:
	var ticks := 0
	for m: Dictionary in active:
		if m.target == target_id and m.template == "mod_thorn": ticks = maxi(ticks, int(m.get("remove_at", m.expires)) - sim.tick)
	return ticks / 30.0
