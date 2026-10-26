extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Replay = preload("res://tests/campaign_playback.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
var failures: Array[String] = []
var checks := 0
var report := {"passed": false, "levels": {}, "failures": []}

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	check(Levels.load_definition(4).is_empty() and Levels.load_definition(2, 2).is_empty(), "only three normal campaigns available")
	for id in [2, 3]:
		var definition := Levels.load_definition(id)
		check(not definition.is_empty(), "valid manifest %d" % id)
		var sim = Sim.new(definition, 42)
		check(sim.gold == {2: 240, 3: 330}[id] and sim.towers.size() == {2: 7, 3: 12}[id] and not sim.unlocked.fire and not sim.unlocked.reinforcements, "source pre-wave state %d" % id)
		Replay.dismiss(sim)
		for type: String in Sim.TYPES: check(not sim.tower_locked("tower_" + type + "_2") and sim.tower_locked("tower_" + type + "_3"), "source level tower limits " + type)
		_timeline(sim)
		var victory = Replay.play(id)
		var defeat = Replay.play(id, false)
		check(victory.result == "victory" and not victory.developer_used, "legal full victory %d" % id)
		check(victory.spawn_log.size() == {2: 154, 3: 329}[id], "all source enemies generated %d" % id)
		check(defeat.result == "defeat" and defeat.lives == 0, "empty defense loses %d" % id)
		report.levels[str(id)] = {"victory": {"result": victory.result, "ticks": victory.tick, "lives": victory.lives, "gold": victory.gold, "kills": victory.kills, "leaks": victory.leaks, "spawned": victory.spawn_log.size()}, "defeat_ticks": defeat.tick}
		for i in range(3):
			victory.reset()
			check(victory.gold == int(definition.waves.cash) and victory.lives == 20 and victory.enemies.is_empty() and victory.effects.is_empty() and victory.alerts.is_empty() and victory.cooldowns.fire == 0 and victory.speed == 1, "fresh restart %d/%d" % [id, i])
		var one = Sim.new(definition, 123); var two = Sim.new(definition, 123)
		Replay.dismiss(one); Replay.dismiss(two); one.command("wave"); two.command("wave")
		one.command("pause"); one.advance(3); check(one.tick == 0, "pause freezes clock")
		one.command("pause"); two.command("speed")
		for i in range(60): one.advance(1.0 / 30); two.advance(1.0 / 60)
		check(one.tick == two.tick and one.spawn_log == two.spawn_log and one.rng.state == two.rng.state, "speed independent state %d" % id)
	_mechanisms()
	var progress := Progress.new(); var path := "user://levels_progress_%d.json" % Time.get_ticks_usec()
	progress.initialize(path)
	for id in [1, 2, 3]:
		check(progress.is_playable(id), "campaign sequential entry %d" % id)
		progress.record_result({"generation": 1, "level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	check(progress.is_unlocked(4) and not progress.is_playable(4) and progress.total_stars() == 9, "fourth flag unlocks as preview")
	var restored := Progress.new(); restored.initialize(path)
	check(restored.total_stars() == 9 and restored.is_playable(3), "three level progress reloads")
	progress.mark_notification_seen("enemy_wolf_small"); restored.initialize(path)
	check(restored.seen_notifications == ["enemy_wolf_small"], "read enemy notifications persist per save")
	var known := Levels.load_definition(3); known.seen_notifications = restored.seen_notifications
	var familiar = Sim.new(known); familiar._spawn_enemy("enemy_wolf_small")
	check(familiar.alerts.is_empty(), "read enemy does not repeat its alert on later levels")
	report.passed = failures.is_empty(); report.failures = failures; report.checks = checks
	var file := FileAccess.open("res://reports/campaign_levels_logic.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("CAMPAIGN_LEVELS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _timeline(sim) -> void:
	var counts := {}
	for group: Dictionary in sim.data.waves.groups:
		check(sim.command("wave"), "manual wave accepted")
		Replay.dismiss(sim)
		var started: int = sim.tick
		var expected: Array = []
		for wave: Dictionary in group.waves:
			var at: int = started + int(wave.delay)
			for index in wave.spawns.size():
				var spawn: Dictionary = wave.spawns[index]
				for n in int(spawn.max):
					at += int(spawn.interval)
					var type: String = spawn.creep
					if spawn.has("creep_aux") and int(spawn.max_same) > 0 and floori(float(n) / int(spawn.max_same)) % 2 == 1: type = spawn.creep_aux
					expected.append({"tick": at, "type": type, "path": int(wave.path_index) - 1, "subpath": int(spawn.path) - 1 if int(spawn.fixed_sub_path) == 1 else -1, "order": expected.size()})
				if int(spawn.max) == 0: at += int(spawn.interval)
				if index + 1 < wave.spawns.size(): at += int(spawn.interval_next)
		expected.sort_custom(func(a, b): return a.tick < b.tick if a.tick != b.tick else a.order < b.order)
		var offset: int = sim.spawn_log.size()
		while not sim.spawn_queue.is_empty():
			sim.enemies.clear(); sim.step()
		var actual: Array = sim.spawn_log.slice(offset)
		check(actual.size() == expected.size(), "wave spawn count")
		for i in expected.size():
			check(actual[i].tick == expected[i].tick and actual[i].type == expected[i].type and actual[i].path == expected[i].path and actual[i].subpath >= 0 and actual[i].subpath < sim.data.paths.paths[actual[i].path].size() and (expected[i].subpath < 0 or actual[i].subpath == expected[i].subpath), "source ordered spawn tick/type/path/subpath")
			counts[actual[i].type] = int(counts.get(actual[i].type, 0)) + 1
		sim.enemies.clear()
	check(counts == ({"enemy_goblin":106,"enemy_fat_orc":26,"enemy_wolf_small":22} if sim.data.level.id == 2 else {"enemy_goblin":224,"enemy_fat_orc":58,"enemy_wolf_small":32,"enemy_shaman":12,"enemy_ogre":3}), "exact source roster counts")

func _mechanisms() -> void:
	var sim = Sim.new(Levels.load_definition(3), 42)
	var ogre: Dictionary = sim._spawn_enemy("enemy_ogre", 0)
	var points: Array = sim.data.paths.paths[0][0]
	ogre.node = points.size() - 1; ogre.pos = Sim.vec(points[-1]); sim._enemy_step(ogre)
	check(sim.lives == 17 and sim.leaks == 1, "ogre costs three lives once")
	sim._enemy_step(ogre); check(sim.lives == 17, "goal cannot charge twice")
	var shaman: Dictionary = sim._spawn_enemy("enemy_shaman", 0)
	shaman.pos = Vector2(600, 340); shaman.hp -= 20
	check(is_equal_approx(sim.damage(shaman, 10, 4), 1.5), "shaman source magic resistance")
	var allies: Array = []
	for i in range(4):
		var ally: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0); ally.pos = shaman.pos + Vector2(10 + i * 10, 0); ally.hp -= 60; allies.append(ally)
	var events: Array = []
	sim.event.connect(func(kind, payload):
		if kind == "healed": events.append(payload))
	sim.tick = 240; check(not sim._healer_step(shaman, sim.templates.enemy_shaman), "shaman cooldown is strictly greater than eight seconds")
	sim.tick = 241; check(sim._healer_step(shaman, sim.templates.enemy_shaman) and shaman.state == "heal", "shaman casts after eight seconds")
	sim.tick += 13; sim._healer_step(shaman, sim.templates.enemy_shaman); check(events.is_empty(), "heal waits for frame fourteen")
	allies[0].pos += Vector2(300, 0)
	sim.tick += 1; sim._healer_step(shaman, sim.templates.enemy_shaman)
	check(events.size() == 3 and events.all(func(e): return e.target != allies[0].id and e.amount == 50), "heal retargets and caps three source heals")
	check(shaman.hp <= shaman.max_hp, "healing never exceeds maximum")
	var dying: Dictionary = sim._spawn_enemy("enemy_shaman", 0); dying.pos = shaman.pos
	sim.tick += 241; sim._healer_step(dying, sim.templates.enemy_shaman)
	var before := events.size(); sim.damage(dying, 9999, 1); sim.tick += 14; sim._enemy_step(dying)
	check(events.size() == before, "dead caster cannot apply pending heal")
	var retry = Sim.new(Levels.load_definition(3), 42)
	var waiting: Dictionary = retry._spawn_enemy("enemy_shaman", 0)
	retry.tick = 241; check(not retry._healer_step(waiting, retry.templates.enemy_shaman), "healthy allies do not start healing")
	waiting.hp -= 1
	retry.tick = 255; check(not retry._healer_step(waiting, retry.templates.enemy_shaman), "empty heal search waits half a second")
	retry.tick = 256; check(retry._healer_step(waiting, retry.templates.enemy_shaman), "empty heal search retries after fifteen ticks")
	var wolf: Dictionary = sim._spawn_enemy("enemy_wolf_small", 0)
	wolf.pos = Vector2(500, 400)
	var soldier: Dictionary = sim._soldier("soldier_militia", "", 0, wolf.pos, wolf.pos)
	var dodged := 0
	for i in range(200):
		soldier.pending = {}; soldier.attack_at = sim.tick
		sim._melee(soldier, wolf, sim.templates.soldier_militia)
		sim.tick += 4; sim._melee(soldier, wolf, sim.templates.soldier_militia)
		if soldier.pending.get("dodged", false): dodged += 1
		soldier.pending = {}
	check(dodged > 35 and dodged < 85, "source 30 percent melee dodge samples")
	check(sim.damage(wolf, 10, 2) == 10, "dodge does not reduce projectile damage")
	# Every primary/subpath reaches its own source endpoint.
	for path in sim.data.paths.paths.size():
		for subpath in sim.data.paths.paths[path].size():
			var enemy: Dictionary = sim._spawn_enemy("enemy_goblin", subpath, path)
			var route: Array = sim.data.paths.paths[path][subpath]
			enemy.node = route.size() - 2; enemy.pos = Sim.vec(route[-1]); var lives: int = sim.lives
			sim._enemy_step(enemy); check(sim.lives == lives - 1, "path endpoint %d/%d" % [path, subpath])
