extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Arena = preload("res://tests/tower_upgrade_arena.gd")
const ArcherArena = preload("res://tests/archer_upgrade_arena.gd")
const Info = preload("res://scripts/battle/dove_unit_info.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func dismiss(sim) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")
func fresh(kind: String):
	var sim = Sim.new(Arena.definition())
	dismiss(sim)
	check(sim.command("build", {"id": "8", "type": kind}), kind + " build")
	for i in range(25): sim.step()
	return sim
func upgrade(sim, kind: String) -> bool:
	return sim.command("upgrade", {"id": "8", "upgrade_to": "tower_" + kind + "_2"})
func snapshot(sim) -> Array:
	return [sim.gold, sim.towers.duplicate(true), sim.soldiers.duplicate(true), sim.enemies.duplicate(true), sim.projectiles.duplicate(true), sim.effects.duplicate(true), sim.rng.state, sim.next_id]
func denied(sim, args: Dictionary, label: String) -> void:
	var before := snapshot(sim)
	check(not sim.command("upgrade", args), label + " rejected")
	check(before == snapshot(sim), label + " has no side effects")
func enemy_at(sim, point: Vector2) -> Dictionary:
	var e: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	e.pos = point; e.hp = 10000; e.max_hp = 10000
	return e

func transactions(kind: String, price: int, total: int, refund: int) -> void:
	var sim = fresh(kind)
	var args := {"id": "8", "upgrade_to": "tower_" + kind + "_2"}
	sim.gold = price - 1; denied(sim, args, kind + " insufficient gold")
	sim.gold = price
	denied(sim, {"id": "missing", "upgrade_to": args.upgrade_to}, kind + " missing holder")
	denied(sim, {"id": "1", "upgrade_to": args.upgrade_to}, kind + " empty holder")
	denied(sim, {"id": "8"}, kind + " missing target")
	denied(sim, {"id": "8", "upgrade_to": "tower_" + kind + "_3"}, kind + " tier three")
	for other in Sim.TYPES:
		if other != kind: denied(sim, {"id": "8", "upgrade_to": "tower_" + other + "_2"}, kind + " cross family " + other)
	sim.command("pause"); denied(sim, args, kind + " pause"); sim.command("pause")
	sim.notices.append("TIP_ARMOR"); denied(sim, args, kind + " modal"); dismiss(sim)
	for outcome in ["victory", "defeat"]:
		sim.result = outcome; denied(sim, args, kind + " " + outcome)
	sim.result = ""
	var old: Dictionary = sim.tower_by_id("8").duplicate(true)
	check(upgrade(sim, kind) and sim.gold == 0, kind + " exact funds commits")
	var tower: Dictionary = sim.tower_by_id("8")
	check(tower.template == args.upgrade_to and tower.spent == total, kind + " tier and total")
	for key in ["id", "pos", "holder", "rally"]: check(tower[key] == old[key], kind + " retains " + key)
	check(tower.pending.is_empty() and tower.shot_at == -1000 and not tower.has("layers"), kind + " clean attack state")
	check(sim.upgrade_target(tower) == "", kind + " no third tier")
	denied(sim, args, kind + " duplicate")
	check(sim.sell_refund(tower) == total, kind + " full quote")
	check(sim.command("sell", {"id": "8"}) and sim.gold == total, kind + " full refund")
	check(sim.tower_by_id("8").spent == 0 and sim.tower_by_id("8").template == old.holder, kind + " clean holder")
	check(sim.command("build", {"id": "8", "type": kind}), kind + " rebuild")
	denied(sim, args, kind + " construction")
	for i in range(25): sim.step()
	sim.gold = 1000; check(upgrade(sim, kind), kind + " upgrade rebuilt")
	check(sim.command("wave"), kind + " start wave")
	var gold: int = sim.gold
	check(sim.sell_refund(sim.tower_by_id("8")) == refund, kind + " post-wave quote")
	check(sim.command("sell", {"id": "8"}) and sim.gold == gold + refund, kind + " post-wave refund")
	check(sim.soldiers.all(func(s): return s.home != "8" or s.hp <= 0 and s.target == 0 and s.pending.is_empty()), kind + " sale clears garrison combat")
	for i in range(3):
		sim.reset(); dismiss(sim)
		check(sim.gold == 1000 and sim.soldiers.is_empty() and sim.towers.all(func(t): return t.type == "" and t.spent == 0), kind + " arena reset %d" % i)
	var campaign = Sim.new({}, 1, true); dismiss(campaign)
	campaign.command("dev_add_gold"); campaign.command("build", {"id": "8", "type": kind})
	for i in range(25): campaign.step()
	denied(campaign, args, kind + " campaign lock despite debug gold")
	for i in range(3):
		campaign.reset(); dismiss(campaign)
		check(campaign.tower_locked(args.upgrade_to) and campaign.gold == 270, kind + " campaign reset %d" % i)

func garrison() -> void:
	var sim = fresh("barrack")
	for i in range(100): sim.step()
	check(sim.soldiers.size() == 3, "militia fixture")
	var old: Array = sim.soldiers.duplicate(true)
	var soldier: Dictionary = sim.soldiers[0]
	var e := enemy_at(sim, soldier.pos + Vector2(10, 0))
	soldier.hp = 3; soldier.flip = true; soldier.rallying = false
	soldier.target = e.id; e.blockers = [soldier.id]; e.blocker = soldier.id
	sim._melee(soldier, e, sim.templates[soldier.template])
	var started: int = sim.tick
	sim.soldiers[1].hp = 7
	sim.soldiers[1].pos += Vector2(30, 0); sim.soldiers[1].rallying = true
	sim.damage(sim.soldiers[2], 999, 1)
	old = sim.soldiers.duplicate(true)
	var dead_id: int = sim.soldiers[2].id
	check(upgrade(sim, "barrack"), "mixed garrison upgrade")
	var tower: Dictionary = sim.tower_by_id("8")
	check(sim.soldiers.size() == 2 and tower.slots[2] == 0, "only live slots replaced; dead slot immediately eligible")
	for s: Dictionary in sim.soldiers:
		check(s.template == "soldier_footmen" and s.hp == 100 and s.max_hp == 100, "fresh full-health footman")
		check(s.pos == old[s.slot].pos and s.pending.is_empty() and s.rally_pending, "replacement retains position and cancels pending hit")
		check(not old.any(func(o): return o.id == s.id), "replacement has new entity id")
	check(sim.unit_by_id(dead_id).is_empty() and sim.unit_by_id(old[0].id).is_empty(), "old soldiers and corpse removed")
	var replacement: Dictionary = sim.soldiers[0]
	check(replacement.flip and replacement.target == e.id and e.blockers == [replacement.id] and e.blocker == replacement.id, "block references transferred atomically")
	check(replacement.attack_at == started + 42 and replacement.attack_started_at == started, "melee timestamp inherited into 42-tick footman period")
	check(sim.soldiers[1].attack_started_at == 0 and sim.soldiers[1].attack_at == 42, "moving soldier with no prior attack retains source zero timestamp")
	var info: Dictionary = Info.snapshot(replacement, sim.templates, sim.data.ui.strings)
	check(info.hp_max == 100 and info.damage_min == 4 and info.damage_max == 6 and is_equal_approx(info.armor, 0.15), "footman information panel values")
	sim._soldier_step(replacement)
	check(replacement.target == 0 and e.blockers.is_empty() and e.blocker == 0 and replacement.pending.is_empty(), "new rally releases transferred block before moving")
	check(e.hp == 10000, "old pending strike never resolves")
	sim._barrack_step(tower, sim.tower_template(tower))
	check(tower.door_state == "opening", "missing slot starts new door")
	var opened_at: int = sim.tick
	for i in range(4): sim.tick += 1; sim._barrack_step(tower, sim.tower_template(tower))
	check(sim.soldiers.size() == 2, "no new soldier before full five-frame door")
	sim.tick = opened_at + 5; sim._barrack_step(tower, sim.tower_template(tower))
	check(sim.soldiers.size() == 3 and sim.soldiers.all(func(s): return s.template == "soldier_footmen"), "one missing footman exits after open animation")
	for i in range(25): sim.tick += 1; sim._barrack_step(tower, sim.tower_template(tower))
	check(sim.soldiers.size() == 3 and tower.door_state == "closed", "new door closes without duplicate spawning")
	var rally := Vector2.ZERO
	for dx in range(-150, 151):
		for dy in range(-105, 106):
			var point: Vector2 = tower.pos + Vector2(dx, dy)
			var center: Vector2 = tower.pos + Sim.vec(sim.tower_template(tower).tower.range_offset)
			if Sim.distance(point, center) > 145 and Sim.distance(point, center) <= 150 and sim.valid_ground(point): rally = point; break
		if rally != Vector2.ZERO: break
	check(rally != Vector2.ZERO and sim.command("rally", {"id": "8", "pos": rally}), "upgraded rally accepts newly available 145-150 band")
	var outside: Vector2 = tower.pos + Sim.vec(sim.tower_template(tower).tower.range_offset) + Vector2(151, 0)
	var expected: Vector2 = sim.resolve_rally_point(tower, outside)
	check(sim.command("rally", {"id": "8", "pos": outside}) == expected.is_finite() and (not expected.is_finite() or tower.rally.is_equal_approx(expected)), "upgraded rally resolves outside click to the legal edge")
	# Fixed attack samples avoid motion and regeneration masking timing/armor errors.
	replacement.rally_pending = false; replacement.rallying = false; replacement.pending = {}
	sim.tick = started + 41; sim._melee(replacement, e, sim.templates.soldier_footmen)
	check(replacement.pending.is_empty(), "footman strict cooldown at tick 41")
	sim.tick += 1; sim._melee(replacement, e, sim.templates.soldier_footmen)
	check(replacement.pending.at == sim.tick + 5, "footman ready at 42 with five-frame hit")
	var hp: float = e.hp
	for i in range(4): sim.tick += 1; sim._melee(replacement, e, sim.templates.soldier_footmen)
	check(e.hp == hp, "footman no early damage")
	sim.tick += 1; sim._melee(replacement, e, sim.templates.soldier_footmen)
	check(hp - e.hp >= 2.8 - 0.001 and hp - e.hp <= 4.2 + 0.001, "footman 4-6 physical damage through orc armor")
	check(is_equal_approx(sim.damage(replacement, 10, 2), 8.5), "footman 15 percent armor")
	sim.damage(replacement, 999, 1)
	var death: int = sim.tick
	for i in range(299): sim.tick += 1; sim._barrack_step(tower, sim.tower_template(tower))
	check(tower.slots[0] < 0, "footman ten-second replacement wait")
	sim.tick = death + 300
	for i in range(7): sim._barrack_step(tower, sim.tower_template(tower)); sim.tick += 1
	check(sim.unit_by_id(tower.slots[0]).template == "soldier_footmen", "dead footman replenishes as footman")
	# Upgrading before initial deployment still produces exactly one new garrison.
	sim = fresh("barrack"); check(upgrade(sim, "barrack"), "upgrade during first door opening")
	for i in range(100): sim.step()
	check(sim.soldiers.size() == 3 and sim.soldiers.all(func(s): return s.template == "soldier_footmen"), "initial deployment upgrade has no militia leftovers")

func ranged(kind: String, period: int, release: int, bullet_name: String) -> void:
	var sim = fresh(kind)
	var tower: Dictionary = sim.tower_by_id("8")
	var e := enemy_at(sim, tower.pos + Vector2(80, 0))
	sim._tower_step(tower)
	check(not tower.pending.is_empty(), kind + " old pending attack")
	var old_bullet: String = sim.tower_template(tower).attacks.list[0].bullet
	sim._projectile(old_bullet, e.id, tower.pos + Vector2(0, 50), e.pos, 1)
	var airborne: Dictionary = sim.projectiles[0].duplicate(true)
	check(upgrade(sim, kind), kind + " upgrade mid attack")
	tower = sim.tower_by_id("8")
	check(sim.projectiles[0] == airborne and tower.pending.is_empty(), kind + " preserves airborne old projectile and cancels windup")
	var at: int = sim.tick
	for i in range(period - 1): sim.tick += 1; sim._tower_step(tower)
	check(tower.pending.is_empty(), kind + " new full cooldown boundary")
	sim.tick += 1; sim._tower_step(tower)
	check(sim.tick == at + period and tower.pending.at == sim.tick + release, kind + " source attack and release timing")
	for i in range(release - 1): sim.tick += 1; sim._tower_step(tower)
	check(sim.projectiles.size() == 1, kind + " no premature projectile")
	sim.tick += 1; sim._tower_step(tower)
	check(sim.projectiles.size() == 2 and sim.projectiles[1].template == bullet_name, kind + " old and new projectiles coexist")
	var shot_at: int = tower.shot_at
	sim.tick = shot_at + period - 1; sim._tower_step(tower)
	check(tower.shot_at == shot_at, kind + " repeated cooldown boundary")
	sim.tick += 1; sim._tower_step(tower)
	check(tower.shot_at == shot_at + period, kind + " repeated interval")
	tower.pending = {}; tower.attack_at = sim.tick
	var range_center: Vector2 = tower.pos + Sim.vec(sim.tower_template(tower).tower.range_offset)
	e.pos = range_center + Vector2(160.1, 0); sim._tower_step(tower)
	check(tower.pending.is_empty(), kind + " outside range")
	e.pos = range_center + Vector2(160, 0); sim._tower_step(tower)
	check(not tower.pending.is_empty(), kind + " inclusive range 160")
	if kind == "mage":
		var saved: Vector2 = e.pos
		e.pos = range_center + Vector2(177, 0)
		sim.tick = tower.pending.at; sim._tower_step(tower)
		check(sim.projectiles[-1].target == 0 and sim.projectiles[-1].to == saved, "mage escaped windup fires toward saved point without target")
	else:
		var saved: Vector2 = tower.pending.aim
		e.hp = 0; sim.tick = tower.pending.at; sim._tower_step(tower)
		check(sim.projectiles[-1].to == saved, "artillery dead windup target keeps saved ground point")

func bullets() -> void:
	for name in ["bolt_1", "bolt_2"]:
		var sim = fresh("mage")
		var e := enemy_at(sim, Vector2(500, 400))
		sim.templates.enemy_fat_orc.health.magic_armor = 0.25
		var hit: Vector2 = e.pos + Sim.vec(sim.templates[e.template].unit.hit_offset)
		sim._projectile(name, e.id, hit - Vector2(100, 0), hit, 1)
		var p: Dictionary = sim.projectiles[-1]
		sim._bullet_step(p); check(p.speed == 30 and p.pos == p.from, name + " source initial speed and yield")
		sim.tick += 1; sim._bullet_step(p)
		check(p.speed == 60 and p.pos == p.from + Vector2(2, 0), name + " quantized acceleration")
		e.pos += Vector2(3, 5); sim.tick += 1; sim._bullet_step(p)
		check(p.to == e.pos + Sim.vec(sim.templates[e.template].unit.hit_offset), name + " tracks moving hit offset")
		var hp: float = e.hp
		for i in range(80):
			if p.done: break
			sim.tick += 1; sim._bullet_step(p)
		var b: Dictionary = sim.templates[name].bullet
		check(p.done and p.pos == p.to and p.speed <= 300, name + " reaches endpoint with capped speed")
		check(hp - e.hp >= b.damage_min * 0.75 and hp - e.hp <= b.damage_max * 0.75, name + " magical damage through magic armor")
		check(sim.effects.any(func(f): return f.template == "fx_bolt_hit"), name + " hit effect")
		for reason in ["dead", "teleport", "removed"]:
			sim.projectiles.clear(); sim.effects.clear(); e.pos = Vector2(500, 400); e.hp = 10000
			hit = e.pos + Sim.vec(sim.templates[e.template].unit.hit_offset)
			sim._projectile(name, e.id, hit - Vector2(50, 0), hit, 1); p = sim.projectiles[-1]
			if reason == "dead": e.hp = 0
			elif reason == "teleport": e.pos.x += 129
			else: sim.enemies.erase(e)
			hp = e.hp
			for i in range(80):
				if p.done: break
				sim.tick += 1; sim._bullet_step(p)
			check(p.done and e.hp == hp and p.pos == hit, name + " " + reason + " ends at saved point without damage")
			check(sim.effects.size() == 1, name + " " + reason + " still emits impact")
			if reason == "teleport": check(p.target_invalid, name + " permanent tracking cutoff")
	for name in ["bomb", "bomb_dynamite"]:
		var sim = fresh("engineer")
		var center := Vector2(500, 400)
		var a := enemy_at(sim, center)
		# Vector2 is float32; sample immediately inside the source radius.
		var b := enemy_at(sim, center + Vector2(62.399, 0))
		var outside := enemy_at(sim, center + Vector2(62.5, 0))
		sim._projectile(name, a.id, center + Vector2(0, 53), center, 31.0 / 30.0)
		var p: Dictionary = sim.projectiles[-1]
		for i in range(30): sim.tick += 1; sim._bullet_step(p)
		check(not p.done and a.hp == 10000, name + " no explosion before 31 frames")
		sim.tick += 1; sim._bullet_step(p)
		var t: Dictionary = sim.templates[name].bullet
		check(is_equal_approx(10000 - a.hp, float(t.damage_max) * 0.862), name + " center damage with explosion protection")
		check(absf(10000 - b.hp - float(t.damage_min) * 0.862) < 0.001 and outside.hp == 10000, name + " edge falloff and outside radius")
		check(sim.effects.any(func(f): return f.template == "fx_explosion_small") and sim.effects.any(func(f): return f.template == "decal_bomb_crater"), name + " explosion and crater")

func _run() -> void:
	var definition := Arena.definition()
	var sim = Sim.new(definition)
	definition.layout.level_mode_overrides[0].locked_towers.append("tower_mage_2")
	check(not sim.tower_locked("tower_mage_2") and sim.gold == 1000, "arena rules deeply copied")
	check(ArcherArena.definition().waves.cash == 270 and "tower_mage_2" in ArcherArena.definition().layout.level_mode_overrides[0].locked_towers, "original archer arena unchanged")
	for kind in Sim.TYPES:
		check(not sim.tower_locked("tower_" + kind + "_2") and Sim.new().tower_locked("tower_" + kind + "_2"), kind + " independent arena unlock")
	denied(sim, {"id": "8", "upgrade_to": "tower_barrack_2"}, "tutorial")
	transactions("barrack", 110, 180, 108)
	transactions("engineer", 220, 345, 207)
	transactions("mage", 160, 260, 156)
	garrison()
	ranged("mage", 46, 8, "bolt_2")
	ranged("engineer", 90, 12, "bomb_dynamite")
	bullets()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	var file := FileAccess.open("res://reports/tower_upgrade_logic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TOWER_UPGRADES: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
