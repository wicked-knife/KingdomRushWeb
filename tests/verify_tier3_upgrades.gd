extends "res://tests/verify_tower_upgrades.gd"
const Tier3Arena = preload("res://tests/tier3_upgrade_arena.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")

func fresh(kind: String):
	var sim = Sim.new(Tier3Arena.definition(), 42)
	dismiss(sim)
	check(sim.command("build", {"id":"03", "type":kind}), kind + " build fixture")
	for i in range(25): sim.step()
	check(sim.command("upgrade", {"id":"03", "upgrade_to":"tower_" + kind + "_2"}), kind + " tier two fixture")
	return sim

func tier3(kind: String, price: int, total: int) -> void:
	var sim = fresh(kind)
	var args := {"id":"03", "upgrade_to":"tower_" + kind + "_3"}
	sim.gold = price - 1; denied(sim, args, kind + " insufficient")
	sim.gold = price
	denied(sim, {"id":"missing", "upgrade_to":args.upgrade_to}, "missing holder")
	denied(sim, {"id":"02", "upgrade_to":args.upgrade_to}, "empty holder")
	denied(sim, {"id":"03"}, "missing target")
	for other in Sim.TYPES:
		if other != kind: denied(sim, {"id":"03", "upgrade_to":"tower_" + other + "_3"}, "cross family")
	denied(sim, {"id":"03", "upgrade_to":"tower_" + kind + "_1"}, "downgrade")
	sim.command("pause"); denied(sim, args, "paused"); sim.command("pause")
	sim.notices.append("TIP_ARMOR"); denied(sim, args, "notice"); dismiss(sim)
	for result in ["victory", "defeat"]:
		sim.result = result; denied(sim, args, result)
	sim.result = ""
	var old: Dictionary = sim.tower_by_id("03").duplicate(true)
	check(sim.command("upgrade", args) and sim.gold == 0, kind + " exact funds")
	var tower: Dictionary = sim.tower_by_id("03")
	for key in ["id", "pos", "holder", "rally"]: check(tower[key] == old[key], kind + " retained " + key)
	check(tower.template == args.upgrade_to and tower.spent == total and sim.upgrade_target(tower) == "", kind + " final tier")
	denied(sim, args, kind + " duplicate")
	denied(sim, {"id":"03", "upgrade_to":"tower_" + kind + "_4"}, kind + " unsupported fourth tier")
	check(tower.pending.is_empty() and tower.shot_at == -1000, kind + " pending attack reset")
	check(sim.sell_refund(tower) == total, kind + " setup quote")
	check(sim.command("sell", {"id":"03"}) and sim.gold == total, kind + " full refund")
	check(sim.tower_by_id("03").spent == 0 and sim.tower_by_id("03").type == "", kind + " restores holder")
	var battle = fresh(kind)
	check(battle.command("wave") and battle.command("upgrade", args), kind + " upgrades during wave")
	var gold: int = battle.gold
	check(battle.sell_refund(battle.tower_by_id("03")) == roundi(total * 0.6), kind + " combat quote")
	check(battle.command("sell", {"id":"03"}) and battle.gold == gold + roundi(total * 0.6), kind + " combat refund")
	var base = Sim.new(Tier3Arena.definition()); dismiss(base)
	base.command("build", {"id":"03", "type":kind})
	denied(base, args, kind + " construction")
	for i in range(25): base.step()
	denied(base, args, kind + " skip tier two")
	for level in [2, 3]:
		var locked = Sim.new(Levels.load_definition(level), 1, true); dismiss(locked)
		locked.command("dev_add_gold")
		var id: String = locked.towers[0].id
		locked.command("build", {"id":id, "type":kind})
		for i in range(25): locked.step()
		locked.command("upgrade", {"id":id, "upgrade_to":"tower_" + kind + "_2"})
		denied(locked, {"id":id, "upgrade_to":args.upgrade_to}, "prior campaign remains locked")
	for i in range(3):
		sim.reset(); check(sim.gold == 2500 and sim.soldiers.is_empty() and sim.projectiles.is_empty() and sim.towers.all(func(t): return t.spent == 0), kind + " reset")

func knights() -> void:
	var sim = fresh("barrack")
	for i in range(100): sim.step()
	check(sim.soldiers.size() == 3, "three footmen")
	var s: Dictionary = sim.soldiers[0]
	var enemy := enemy_at(sim, s.pos + Vector2(10, 0))
	s.hp = 3; s.flip = true; s.target = enemy.id; enemy.blockers = [s.id]; enemy.blocker = s.id
	sim._melee(s, enemy, sim.templates.soldier_footmen)
	sim.soldiers[1].pos += Vector2(30, 0); sim.soldiers[1].rallying = true
	sim.damage(sim.soldiers[2], 999, 1)
	var before: Array = sim.soldiers.duplicate(true)
	var started: int = sim.tick
	check(sim.command("upgrade", {"id":"03", "upgrade_to":"tower_barrack_3"}), "replace garrison")
	check(sim.soldiers.size() == 2 and sim.tower_by_id("03").slots[2] == 0, "dead slot available")
	for knight: Dictionary in sim.soldiers:
		check(knight.template == "soldier_knight" and knight.hp == 150 and knight.max_hp == 150 and knight.pending.is_empty(), "full health knight, old hit canceled")
		check(knight.pos == before[knight.slot].pos and knight.rally_pending and not before.any(func(o): return o.id == knight.id), "position preserved, new entity")
	check(sim.soldiers[0].flip and enemy.blocker == sim.soldiers[0].id and enemy.blockers == [sim.soldiers[0].id], "blocker references replaced")
	check(sim.soldiers[0].attack_at == started + 42 and sim.soldiers[0].attack_started_at == started, "strict knight attack timestamp")
	check(before.all(func(o): return sim.unit_by_id(o.id).is_empty()), "old corpses and soldiers removed")
	var info: Dictionary = Info.snapshot(sim.soldiers[0], sim.templates, sim.data.ui.strings)
	check(info.hp_max == 150 and info.damage_min == 8 and info.damage_max == 12 and is_equal_approx(info.armor, 0.3), "knight information")
	for i in range(100): sim.step()
	check(sim.soldiers.size() == 3 and sim.soldiers.all(func(k): return k.template == "soldier_knight"), "door refills missing slot")
	check(sim.command("rally", {"id":"03", "pos":sim.tower_by_id("03").rally}), "knights rally normally")
	check(sim.command("sell", {"id":"03"}) and sim.soldiers.all(func(k): return k.hp <= 0 and k.pending.is_empty() and k.target == 0), "sale retires knights")
	var opening = fresh("barrack")
	for i in range(2): opening.step()
	check(opening.command("upgrade", {"id":"03", "upgrade_to":"tower_barrack_3"}), "upgrade during door opening")
	for i in range(100): opening.step()
	check(opening.soldiers.size() == 3 and opening.soldiers.all(func(k): return k.template == "soldier_knight"), "opening door leaves no old soldier")

func ranged3(kind: String, period: int, shoot: int, bullet: String) -> void:
	var sim = fresh(kind)
	var old: Dictionary = sim.tower_by_id("03")
	var enemy := enemy_at(sim, old.pos + Vector2(50, 0))
	old.attack_at = sim.tick; sim._tower_step(old)
	check(not old.pending.is_empty(), kind + " old attack staged")
	check(sim.command("upgrade", {"id":"03", "upgrade_to":"tower_" + kind + "_3"}), kind + " upgrade cancels old windup")
	var tower: Dictionary = sim.tower_by_id("03")
	check(tower.attack_at == sim.tick + period and tower.pending.is_empty(), kind + " new cooldown")
	sim.tick = tower.attack_at - 1; sim._tower_step(tower)
	check(tower.pending.is_empty() and sim.projectiles.is_empty(), kind + " waits full cooldown")
	sim.tick += 1; sim._tower_step(tower)
	check(tower.pending.at == sim.tick + shoot, kind + " source release frame")
	sim.tick += shoot - 1; sim._tower_step(tower); check(sim.projectiles.is_empty(), kind + " windup no early shot")
	sim.tick += 1; sim._tower_step(tower)
	check(sim.projectiles.size() == 1 and sim.projectiles[0].template == bullet, kind + " tier three bullet")
	var center: Vector2 = tower.pos + Sim.vec(sim.tower_template(tower).tower.range_offset)
	enemy.pos = center + Vector2(180, 0); check(sim._target(center, 180).id == enemy.id, kind + " range inclusive")
	enemy.pos.x += 0.1; check(sim._target(center, 180).is_empty(), kind + " outside range")
	var coexist = fresh(kind)
	old = coexist.tower_by_id("03"); enemy = enemy_at(coexist, old.pos + Vector2(50, 0))
	old.attack_at = coexist.tick; coexist._tower_step(old); coexist.tick += shoot; coexist._tower_step(old)
	var p: Dictionary = coexist.projectiles[0]; var name: String = p.template
	coexist.command("upgrade", {"id":"03", "upgrade_to":"tower_" + kind + "_3"})
	check(coexist.projectiles.size() == 1 and p.template == name, kind + " old projectile persists")
	var hp: float = enemy.hp
	for i in range(100):
		coexist.tick += 1; coexist._bullet_step(p)
		if p.done: break
	check(p.done and enemy.hp < hp, kind + " old projectile still damages")

func impacts() -> void:
	var sim = fresh("engineer")
	var center := Vector2(500, 400)
	var a := enemy_at(sim, center); var edge := enemy_at(sim, center + Vector2(67.199, 0)); var outside := enemy_at(sim, center + Vector2(67.3, 0))
	sim._projectile("bomb_black", a.id, center + Vector2(0, 57), center, 31.0 / 30)
	var p: Dictionary = sim.projectiles[-1]
	sim.tick += 10; sim._bullet_step(p)
	var tangent: float = (p.velocity + Vector2(0, float(sim.templates.bomb_black.bullet.g) * 10 / 30.0)).angle()
	check(is_equal_approx(p.rotation, tangent), "black bomb aligns with trajectory")
	sim.tick += 20; sim._bullet_step(p); check(not p.done, "black bomb waits 31 ticks")
	sim.tick += 1; sim._bullet_step(p)
	check(is_equal_approx(10000 - a.hp, 72 * 0.862) and absf(10000 - edge.hp - 36 * 0.862) < 0.001 and outside.hp == 10000, "black bomb falloff and armor")
	for name in ["arrow_3", "bolt_3"]:
		sim = fresh("mage")
		var e := enemy_at(sim, center)
		var point: Vector2 = e.pos + Sim.vec(sim.templates[e.template].unit.hit_offset)
		sim._projectile(name, e.id, point - Vector2(50, 0), point, 20.0 / 30)
		p = sim.projectiles[-1]
		for i in range(80):
			sim.tick += 1; sim._bullet_step(p)
			if p.done: break
		var amount: float = 10000 - e.hp
		check(p.done and amount >= (11 * 0.7 if name == "arrow_3" else 47) and amount <= (20 * 0.7 if name == "arrow_3" else 82), name + " damage and armor")
		if name == "arrow_3": check(sim.tick - p.at == 20, "third arrow flight 20 frames")
	# The source fourth-stage grid has no WATER cells. Isolate the optional bomb
	# dependency in a synthetic water cell without changing campaign terrain.
	sim = fresh("engineer"); center = Vector2(552, 385)
	var terrain: Dictionary = sim.data.terrain
	var x := ceili((center.x - float(terrain.ox)) / 16.0) - 1
	var y := ceili((center.y - float(terrain.oy)) / 16.0) - 1
	terrain.grid[x][y] = 2
	check((sim._terrain_flags(center) & 2) != 0, "isolated water fixture")
	var sounds: Array = []
	sim.event.connect(func(kind, payload):
		if kind == "sound": sounds.append(payload.id))
	sim._projectile("bomb_black", 0, center + Vector2(0, 57), center, 31.0 / 30)
	p = sim.projectiles[-1]; sim.tick += 31; sim._bullet_step(p)
	check(sim.effects.any(func(e): return e.template == "fx_explosion_water") and not sim.effects.any(func(e): return e.template == "decal_bomb_crater"), "water explosion has no dry crater")
	check(sounds.has("RTWaterExplosion"), "water impact sound")

func new_enemies() -> void:
	var sim = fresh("barrack")
	var brigand: Dictionary = sim._spawn_enemy("enemy_brigand", 0)
	check(brigand.max_hp == 264 and sim.templates.enemy_brigand.health.armor == 0.5, "brigand source health and armor")
	check(is_equal_approx(sim.damage(brigand, 10, 2), 5) and is_equal_approx(sim.damage(brigand, 10, 4), 10), "brigand physical and magic protection")
	var bandit: Dictionary = sim._spawn_enemy("enemy_bandit", 0)
	check(bandit.max_hp == 115 and sim.templates.enemy_bandit.dodge.chance == 0.5 and sim.templates.enemy_bandit.dodge.silent, "bandit source dodge")
	var soldier: Dictionary = sim._soldier("soldier_knight", "", 0, bandit.pos, bandit.pos)
	bandit.hp = 10000
	var dodged := 0
	for i in range(200):
		soldier.pending = {}; soldier.attack_at = sim.tick
		sim._melee(soldier, bandit, sim.templates.soldier_knight)
		sim.tick += 4; sim._melee(soldier, bandit, sim.templates.soldier_knight)
		if soldier.pending.get("dodged", false): dodged += 1
		sim.tick += 1; sim._melee(soldier, bandit, sim.templates.soldier_knight)
	check(dodged > 70 and dodged < 130 and bandit.hp < 10000, "bandit dodges roughly half of knight hits")
	check(sim.alerts.count("enemy_bandit") == 1 and sim.alerts.count("enemy_brigand") == 1, "new enemy alerts emitted")
	sim._spawn_enemy("enemy_bandit", 0); check(sim.alerts.count("enemy_bandit") == 1, "alert emitted only once")

func _run() -> void:
	for kind in Sim.TYPES: tier3(kind, {"archer":160,"barrack":150,"mage":240,"engineer":320}[kind], {"archer":340,"barrack":330,"mage":500,"engineer":665}[kind])
	knights(); ranged3("archer", 15, 5, "arrow_3"); ranged3("mage", 46, 8, "bolt_3"); ranged3("engineer", 90, 12, "bomb_black"); impacts(); new_enemies()
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures}
	var file := FileAccess.open("res://reports/tier3_upgrade_logic.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TIER3_UPGRADES: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
