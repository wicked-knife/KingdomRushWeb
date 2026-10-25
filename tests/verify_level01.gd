extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
var failures: Array[String] = []
var report := {}

func _init() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)

func dismiss(sim) -> void:
	while not sim.notices.is_empty(): check(sim.command("confirm"), "notification confirmation")

func _run() -> void:
	var sim = Sim.new()
	check(sim.lives == 20 and sim.gold == 270 and sim.towers.size() == 8, "initial state")
	check(sim.data.source.commit == "e29ece82939fd73fb69bfc4b469d484a72e4dfd2", "frozen source")
	for path in sim.data.paths.paths[0]: check(path.size() == 218, "original 218-node subpaths")
	check(not sim.command("build", {"id": "1", "type": "archer"}), "tutorial blocks battlefield commands")
	dismiss(sim)
	check(sim.command("build", {"id": "1", "type": "mage"}), "build")
	check(not sim.command("build", {"id": "1", "type": "archer"}), "duplicate build rejected")
	check(not sim.command("build", {"id": "2", "type": "mage_2"}), "tier two locked")
	check(sim.command("build", {"id": "2", "type": "engineer"}), "artillery build")
	check(not sim.command("build", {"id": "3", "type": "archer"}), "insufficient gold rejected")
	check(not sim.command("cast", {"power": "fire", "pos": Vector2(400, 230)}), "power locked")
	var e: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	check(e.hp == 132, "normal orc health")
	check(is_equal_approx(sim.damage(e, 10, 2), 7), "physical armor")
	check(is_equal_approx(sim.damage(e, 10, 4), 10), "magic bypasses physical armor")
	check(is_equal_approx(sim.damage(e, 10, 8), 8.62), "Dove explosion armor curve")
	var previous_gold: int = sim.gold
	sim.damage(e, 999, 1); sim.damage(e, 999, 1)
	check(sim.gold == previous_gold + 9 and sim.kills == 1, "kill reward only once")
	sim._projectile("arrow_1", e.id, e.pos + Vector2(0, 50), e.pos, 0.2)
	for i in range(9): sim.step()
	check(sim.kills == 1 and sim.projectiles.is_empty(), "projectile target already dead")
	sim.reset(); dismiss(sim)
	var a: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	var b: Dictionary = sim._spawn_enemy("enemy_fat_orc", 1)
	a.pos = Vector2(400, 440); b.pos = Vector2(410, 445)
	sim._projectile("bomb", a.id, Vector2(400, 490), Vector2(400, 440), 0.1)
	for i in range(4): sim.step()
	check(a.hp < a.max_hp and b.hp < b.max_hp, "bomb damages multiple targets")
	for type in Sim.TYPES:
		sim.reset(); dismiss(sim)
		check(sim.command("build", {"id": "8", "type": type}), "single tower " + type)
		sim.command("wave")
		for i in range(1800): sim.step()
		check(sim.kills > 0, "tower actually kills " + type)
	sim.reset(); dismiss(sim)
	sim.command("build", {"id": "1", "type": "mage"})
	for i in range(25): sim.step()
	check(sim.command("sell", {"id": "1"}) and sim.gold == 230, "60 percent sell refund")
	check(not sim.command("sell", {"id": "1"}), "empty holder sell rejected")
	for subpath in range(3):
		sim.reset(); dismiss(sim)
		e = sim._spawn_enemy("enemy_goblin", subpath)
		for i in range(2000): sim.step()
		check(sim.lives == 19 and sim.leaks == 1, "subpath %d reaches goal exactly once" % subpath)
	sim.reset(); dismiss(sim)
	check(sim.command("build", {"id": "4", "type": "barrack"}), "barrack build")
	for i in range(180): sim.step()
	check(sim.soldiers.size() == 3, "three militia")
	check(not sim.command("rally", {"id": "4", "pos": Vector2(-200, 0)}), "invalid rally")
	check(sim.command("rally", {"id": "4", "pos": Vector2(478, 228)}), "valid rally")
	e = sim._spawn_enemy("enemy_goblin", 0); e.pos = Vector2(478, 228); e.node = 110
	for i in range(45): sim.step()
	check(e.blocker != 0, "militia blocks")
	var soldier := sim.unit_by_id(e.blocker)
	sim.damage(soldier, 999, 1)
	check(not soldier.id in e.blockers, "death releases blocker")
	for i in range(330): sim.step()
	check(sim.soldiers.filter(func(s): return s.hp > 0).size() == 3, "soldier replenishment")
	sim.reset(); dismiss(sim); sim.command("wave")
	var t: int = sim.tick
	sim.command("pause"); sim.advance(4)
	check(sim.tick == t, "pause does not advance")
	sim.command("pause")
	var normal = Sim.new(); var fast = Sim.new()
	dismiss(normal); dismiss(fast); normal.command("wave"); fast.command("wave"); fast.command("speed")
	for i in range(300): normal.advance(1.0 / 60.0)
	for i in range(150): fast.advance(1.0 / 60.0)
	check(normal.tick == fast.tick and normal.enemies == fast.enemies, "1x/2x deterministic equivalence")
	# All wave schedules: no combat shortcuts; keep advancing until all waves spawn.
	sim.reset(); dismiss(sim); sim.command("wave")
	var timeline: Array = []
	for group_index in range(7):
		if group_index > 0:
			while not sim.can_send_wave(): sim.step()
			check(sim.command("wave"), "manual next wave")
		if sim.wave == 3: check(not sim.unlocked.reinforcements, "reinforcements wait for confirmation")
		if sim.wave == 7: check(not sim.unlocked.fire, "fire waits for confirmation")
		dismiss(sim)
		var started: int = sim.tick
		while not sim.spawn_queue.is_empty():
			sim.step()
			# Move existing creeps away from goal only in this schedule-specific fixture.
			for enemy in sim.enemies: enemy.blocker = -1; enemy.pos = Vector2(486, 770); enemy.node = 0
			if sim.result != "": break
		var expected_tick: int = started
		var count := 0
		for w in sim.data.waves.groups[group_index].waves:
			for index in range(w.spawns.size()):
				var spawn = w.spawns[index]
				for j in range(int(spawn.max)):
					expected_tick += int(spawn.interval)
					var actual = sim.spawn_log[sim.spawn_log.size() - sim.data.waves.groups[group_index].waves[0].spawns.reduce(func(total, s): return total + int(s.max), 0) + count]
					check(actual.tick == expected_tick and actual.type == spawn.creep, "wave %d spawn %d timing/order" % [group_index + 1, count])
					count += 1
				if index + 1 < w.spawns.size(): expected_tick += int(spawn.interval_next)
		timeline.append({"wave": sim.wave, "count": count, "start": started, "end": sim.tick})
	check(sim.spawn_log.size() == 56, "56 total spawned")
	check(not sim.command("cast", {"power": "reinforcements", "pos": Vector2(-20, 20)}), "invalid spell point rejected")
	check(sim.command("cast", {"power": "reinforcements", "pos": Vector2(478, 228)}), "legal reinforcement cast")
	check(not sim.command("cast", {"power": "reinforcements", "pos": Vector2(478, 228)}), "cooldown prevents repeat cast")
	report.timeline = timeline
	# Full games only use legal player commands and normal cash, HP and damage.
	var win = _campaign(true)
	check(win.result == "victory", "legitimate full campaign victory")
	report.victory = {"result": win.result, "lives": win.lives, "gold": win.gold, "kills": win.kills, "leaks": win.leaks, "ticks": win.tick, "spawned": win.spawn_log.size()}
	var lose = _campaign(false)
	check(lose.result == "defeat" and lose.lives == 0, "empty defense defeat")
	report.defeat = {"result": lose.result, "lives": lose.lives, "ticks": lose.tick}
	for i in range(3):
		win.reset(); check(win.enemies.is_empty() and win.soldiers.is_empty() and win.projectiles.is_empty() and win.tick == 0 and win.speed == 1 and win.gold == 270 and win.towers.size() == 8, "restart %d clears state" % i)
	report.passed = failures.is_empty(); report.failures = failures
	var file := FileAccess.open("res://reports/level01_logic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("LEVEL01_LOGIC: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _campaign(defend: bool):
	var sim = Sim.new({}, 42); dismiss(sim)
	if defend:
		sim.command("build", {"id": "1", "type": "archer"})
		sim.command("build", {"id": "6", "type": "mage"})
		sim.command("build", {"id": "4", "type": "archer"})
	sim.command("wave")
	for i in range(30000):
		dismiss(sim)
		if defend:
			for id in ["8", "3", "7", "5", "2"]:
				if sim.gold >= 70 and sim.tower_by_id(id).type == "": sim.command("build", {"id": id, "type": "archer"})
			if sim.unlocked.reinforcements and sim.cooldowns.reinforcements == 0:
				var target := sim._target(Vector2(478, 228), 120)
				if not target.is_empty(): sim.command("cast", {"power": "reinforcements", "pos": target.pos})
			if sim.unlocked.fire and sim.cooldowns.fire == 0:
				var target := sim._target(Vector2(400, 440), 400)
				if not target.is_empty(): sim.command("cast", {"power": "fire", "pos": target.pos})
		sim.step()
		if sim.result != "": return sim
	return sim
