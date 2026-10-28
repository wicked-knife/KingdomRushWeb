extends RefCounted
## Frozen tower_barrack_mercenaries and soldier_barrack ranged behavior.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func power_upgraded(sim, tower: Dictionary) -> void:
	for soldier: Dictionary in sim.soldiers:
		if soldier.home == tower.id and soldier.hp > 0: soldier.powers = tower.powers.duplicate()

static func initialize(tower: Dictionary) -> void:
	tower.type = "barrack"; tower.slots = [0,0,0,0]; tower.hired = 0
	tower.powers = {"bleed":0,"cripple":0}

static func price(sim, tower: Dictionary, type: String) -> int:
	if tower.get("template", "") != "tower_elf" or type != "soldier_elf" or int(tower.get("hired",0)) >= int(sim.tower_template(tower).barrack.max_soldiers): return -1
	return int(sim.templates[type].unit.price)

static func hire(sim, tower: Dictionary) -> void:
	tower.hired += 1
	# Reserve the purchased slot before the door opens; repeated commands remain bounded.
	tower.slots[int(tower.hired) - 1] = 0
	formation(sim, tower)

static func formation(sim, tower: Dictionary) -> void:
	for s: Dictionary in sim.soldiers:
		if s.home == tower.id and s.hp > 0:
			s.dest = sim._formation(tower.rally,s.slot,tower); s.rally_center = tower.rally; s.rally_pending = true

static func inherit(s: Dictionary, tower: Dictionary) -> void:
	s.powers = tower.powers.duplicate(); s.ranged_at = 0; s.ranged_until = 0

static func ranged(sim, s: Dictionary, t: Dictionary) -> bool:
	if s.pending.get("ranged",false):
		if sim.tick < int(s.pending.at): return true
		var pending: Dictionary = s.pending
		var target: Dictionary = sim.unit_by_id(pending.target)
		var attack: Dictionary = t.ranged.attacks[0]
		if not target.is_empty() and target.pos.distance_to(pending.aim) <= float(attack.max_track_distance):
			var bullet: Dictionary = sim.templates[pending.bullet].bullet
			var offset: Vector2 = sim.vec(attack.bullet_start_offset[0]); offset.x *= -1 if s.flip else 1
			var origin: Vector2 = s.pos + offset
			var aim: Vector2 = pending.aim + sim.vec(sim.templates[target.template].unit.hit_offset)
			sim._projectile(pending.bullet,target.id,origin,aim,float(bullet.flight_time))
			var p: Dictionary = sim.projectiles[-1]
			p.elf_level = int(s.powers.cripple) if pending.special else int(s.powers.bleed)
			p.bleed_level = 0 if pending.special else int(s.powers.bleed); p.source = str(s.id)
		s.pending = {}; return true
	if sim.tick < int(s.get("ranged_until",0)): return true
	# The source melee coroutine waits for its full animation before the soldier
	# can start another ranged attack, including after a lethal melee hit.
	if s.pending.is_empty() and s.state == "attack" and sim.tick < int(s.state_at) + Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"attack")): return true
	if not s.pending.is_empty() or sim.tick < int(s.ranged_at): return false
	var attack: Dictionary = t.ranged.attacks[0]
	var target: Dictionary = sim._target(s.pos,float(attack.max_range))
	if target.is_empty() or not sim.modifiers.flags_match(sim,target,attack): return false
	# Source U.attack_order visits the chance attack before the guaranteed attack.
	var cripple := int(s.powers.cripple)
	var special: Dictionary = t.ranged.attacks[1]
	var use_cripple: bool = cripple > 0 and sim.rng.randf() <= float(special.chance) + float(special.chance_inc) * cripple
	s.pending = {"ranged":true,"target":target.id,"at":sim.tick + sim.frames(attack.shoot_time),
		"bullet":special.bullet if use_cripple else attack.bullet,"special":use_cripple,"aim":target.pos}
	s.ranged_at = sim.tick + sim.frames(attack.cooldown)
	s.ranged_until = sim.tick + Anim.duration(sim.animations,Anim.key(t.render.sprites[0],"shoot"))
	s.flip = target.pos.x < s.pos.x
	sim._state(s,"shoot",true)
	return true
