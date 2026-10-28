extends SceneTree
## Focused source parity, rejected-cast side effects and invalid-click feedback.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var native := false

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func prepare(sim: RefCounted) -> void:
	sim.notices.clear(); sim.wave = 1
	sim.unlocked = {"fire":true, "reinforcements":true}

func click(battle: Control, point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button; event.pressed = true; event.position = battle.world(point) * battle.zoom
	battle._gui_input(event)

func capture(battle: Control, label: String) -> void:
	battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var path := "skill_placement_" + label + ".png"
	root.get_texture().get_image().save_png("res://reports/" + path); captures.append(path)

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Skill placement timeout"); quit(1))
	native = DisplayServer.get_name() != "headless"
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/skill_placement_reference.json"))
	for level in [1, 2, 3]:
		var sim := Sim.new(Levels.load_definition(level), 11)
		check(sim.data.source.commit == reference.source_commit, "frozen reference commit level %d" % level)
		var mismatches: Array[String] = []
		for point: Dictionary in reference.levels[str(level)]:
			var pos := Vector2(point.x, point.y)
			for power: String in ["fire", "reinforcements"]:
				if sim.valid_power_point(power, pos) != bool(point[power]): mismatches.append("%s (%s,%s)" % [power, point.x, point.y])
		check(mismatches.is_empty(), "source GUI/grid/path parity level %d, %d points: %s" % [level, reference.levels[str(level)].size(), str(mismatches)])
		prepare(sim)
		var tower: Dictionary = sim.towers[0]
		check(sim.command("build", {"id":tower.id, "type":"barrack"}), "adjacent barrack build level %d" % level)
		sim.tick = tower.ready
		check(sim.command("rally", {"id":tower.id, "pos":tower.rally}), "source default rally remains legal level %d" % level)
		# Each path gets a real deployment/interception, including both routes in 3.
		for pi in range(sim.data.paths.paths.size()):
			sim.reset(11); prepare(sim)
			var nodes: Array = sim.data.paths.paths[pi][0]
			var ni := nodes.size() / 2
			var point := Sim.vec(nodes[ni])
			check(sim.command("cast", {"power":"reinforcements", "pos":point}), "road deployment level %d path %d" % [level, pi])
			var enemy: Dictionary = sim._spawn_enemy("enemy_goblin", 0, pi)
			enemy.pos = point; enemy.node = ni; enemy.progress = ni
			for tick in range(45): sim.step()
			check(enemy.blocker != 0 and sim.soldiers.any(func(s): return s.target == enemy.id), "troops intercept on level %d path %d" % [level, pi])
	# Isolate boundary and terrain cases that the first three maps do not all use.
	var boundary := Sim.new(Levels.load_definition(2), 11)
	boundary.data.paths.paths = [[[ {"x":300, "y":300} ]]]
	boundary.data.paths.active = [true]
	for column: Array in boundary.data.terrain.grid: column.fill(1)
	check(boundary.valid_power_point("reinforcements", Vector2(341.99,300)) and not boundary.valid_power_point("reinforcements", Vector2(342,300)), "troops strictly within 42 of main path nodes")
	check(boundary.valid_power_point("fire", Vector2(359.99,300)) and not boundary.valid_power_point("fire", Vector2(360,300)), "fire strictly within 60 of main path nodes")
	check(boundary.valid_ground(Vector2(300,341)) and not boundary.valid_ground(Vector2(330,330)), "deployment distance is circular, not the combat ellipse")
	for terrain in [0, 1, 2, 4, 257, 1025, 2048, 2049]:
		for column: Array in boundary.data.terrain.grid: column.fill(terrain)
		check(boundary.valid_ground(Vector2(300,300)) == (terrain in [0,1,2048,2049]), "source cell_is_only terrain %d" % terrain)
		check(boundary.valid_power_point("fire", Vector2(300,300)) == (terrain not in [4,1025]), "fire excludes cliff/faerie but accepts other nearby terrain %d" % terrain)
		check(boundary.valid_power_point("fire", Vector2(600,500)) == (terrain == 2), "water permits fire away from paths terrain %d" % terrain)
	for column: Array in boundary.data.terrain.grid: column.fill(1)
	boundary.data.paths.active = [false]
	check(not boundary.valid_ground(Vector2(300,300)), "inactive paths cannot receive troops")
	boundary.data.paths.active = [true]
	boundary.data.layout.invalid_path_ranges = [{"path_id":1, "from":1, "to":1, "flags":1}]
	check(not boundary.valid_ground(Vector2(300,300)) and boundary.valid_power_point("fire", Vector2(300,300)), "invalid path ranges respect rally/fire node flags")
	check(not boundary.valid_power_point("fire", Vector2(NAN,0)) and not boundary.valid_ground(Vector2(INF,0)), "nonfinite positions rejected")
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://skill_placement_settings_" + token + ".json"
	app.slots_path = "user://skill_placement_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
	for level in [1,2,3]:
		var battle := Battle.new(); app.add_child(battle)
		battle.initialize(app.loader, app.audio, Levels.load_definition(level))
		battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var grass: Dictionary = reference.levels[str(level)].filter(func(p): return p.terrain == 1 and not p.fire and not p.reinforcements and p.x > 80 and p.x < 944 and p.y > 120 and p.y < 650)[0]
		var invalid := Vector2(grass.x, grass.y)
		for power: String in ["fire", "reinforcements"]:
			battle._action("restart"); prepare(battle.sim); battle.message_time = 0; battle.message = ""
			battle._action("target", {"power":power}); battle.hits.clear()
			var rng_before: int = battle.sim.rng.state
			click(battle, invalid)
			check(battle.targeting == power and battle.message_time == 0 and battle.message == "", "invalid click retains target mode without text level %d %s" % [level,power])
			check(battle.sim.cooldowns[power] == 0 and battle.sim.soldiers.is_empty() and battle.sim.projectiles.is_empty() and battle.sim.rng.state == rng_before, "invalid click consumes no cooldown, units, projectiles or RNG level %d %s" % [level,power])
			check(battle.target_pointer_frame() == "error_feedback_0001", "invalid click starts original red cross level %d %s" % [level,power])
			battle.advance_target_feedback(0.2)
			check(battle.target_pointer_frame() == "error_feedback_0007", "cross advances on UI time level %d %s" % [level,power])
			click(battle, invalid)
			check(battle.target_pointer_frame() == "error_feedback_0001", "repeat rejection restarts cross level %d %s" % [level,power])
			if native and level == 2 and power == "reinforcements":
				battle.advance_target_feedback(0.14)
				await capture(battle, "invalid_cross")
			battle.advance_target_feedback(Battle.INVALID_POINT_DURATION)
			check(battle.target_pointer_frame().begins_with("pointer_point_orange_" if power == "reinforcements" else "pointer_fireball_"), "animated source pointer returns after 14/30 seconds level %d %s" % [level,power])
			for frame in range(1,15):
				check(not battle._frame("error_feedback_%04d" % frame).is_empty(), "cross art %d loads level %d" % [frame, level])
			click(battle, battle.sim.towers[0].rally)
			check(battle.targeting == "" and battle.invalid_point_time == 0 and battle.sim.cooldowns[power] > 0, "valid retry casts and clears feedback level %d %s" % [level,power])
		battle.sim.cooldowns.reinforcements = 0
		battle._action("target", {"power":"reinforcements"}); battle.hits.clear(); click(battle, invalid)
		click(battle, invalid, MOUSE_BUTTON_RIGHT)
		check(battle.targeting == "" and battle.invalid_point_time == 0, "cancel clears red cross level %d" % level)
		battle._action("restart")
		check(battle.invalid_point_time == 0, "restart clears feedback level %d" % level)
		prepare(battle.sim)
		var tower: Dictionary = battle.sim.towers[0]
		battle.sim.command("build", {"id":tower.id, "type":"barrack"}); battle.sim.tick = tower.ready
		battle.selected = tower.id; battle._action("target", {"power":"rally"}); battle.hits.clear()
		# No direction toward a road: the tower's own center remains invalid even
		# after Dove's new directional fallback, unlike an arbitrary grass click.
		click(battle, tower.pos + Sim.vec(battle.sim.tower_template(tower).tower.range_offset))
		check(battle.message_time == 0 and battle.targeting == "rally" and battle.target_pointer_frame() == "error_feedback_0001", "adjacent invalid rally also uses source cross level %d" % level)
		battle._action("restart")
		if native and level == 2:
			prepare(battle.sim); battle._action("target", {"power":"reinforcements"}); battle.hits.clear()
			battle.pointer = battle.world(invalid); await capture(battle, "placement_mode")
		battle.queue_free(); await process_frame
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures, "native":native, "source_samples":820, "captures":captures, "scope":"skill placement, rejected-cast side effects, cursor feedback and adjacent rally path filter"}
	var file := FileAccess.open("res://reports/skill_placement_" + ("native" if native else "logic") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("SKILL_PLACEMENT: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
