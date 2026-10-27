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
	if m.template != "mod_thorn": return
	var target: Dictionary = sim.unit_by_id(m.target)
	if not target.is_empty(): target.stun_count = maxi(0, int(target.get("stun_count", 0)) - 1)

func apply(sim: RefCounted, template: String, target: Dictionary, level: int, source: String, duration: float = -1) -> bool:
	if target.is_empty() or target.hp <= 0 or level <= 0 or not sim.templates.has(template): return false
	var t: Dictionary = sim.templates[template]
	var rule: Dictionary = t.modifier
	if not flags_match(sim, target, rule): return false
	var duplicates := 0
	for m: Dictionary in active:
		if m.target != target.id or m.template != template: continue
		if level < m.level: return false
		if level == m.level:
			if rule.has("max_duplicates"):
				duplicates += 1
				# BASE counts *other* copies; max_duplicates=3 admits four in total.
				if duplicates > int(rule.max_duplicates): return false
			else:
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
	else:
		m.state = t.render.sprites[0].size_names[size_index]
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
				sim.damage(target, float(t.damage_min), int(t.damage_type))
		else:
			if sim.tick >= m.expires: active.erase(m); continue
			if sim.tick >= m.next_hit:
				m.next_hit += sim.frames(t.dps.damage_every)
				var amount := float(t.dps.damage_min) + float(t.dps.damage_inc) * int(m.level)
				sim.damage(target, amount, int(t.dps.damage_type))
		if target.hp <= 0: _release(sim, m); active.erase(m)

func remaining(target_id: int, sim: RefCounted) -> float:
	var ticks := 0
	for m: Dictionary in active:
		if m.target == target_id and m.template == "mod_thorn": ticks = maxi(ticks, int(m.get("remove_at", m.expires)) - sim.tick)
	return ticks / 30.0
