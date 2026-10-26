extends SceneTree
const Flag = preload("res://scripts/map/dove_map_flag.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const App = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _flags() -> void:
	for won in [false, true]:
		var flag := Flag.new(won, 42)
		var normal := "map_flag_0134" if won else "map_flag_0064"
		var over := "map_flag_0181" if won else "map_flag_0180"
		check(flag.frame() == normal, "map flag starts without glow")
		for i in range(5):
			flag.set_hovered(true); flag.advance(30)
			check(flag.frame() == over, "hover holds glow without random animation")
			flag.set_hovered(false)
			check(flag.frame() == ("map_flag_0090" if won else "map_flag_0024"), "exit restarts normal animation")
			flag.advance(1.6)
			check(flag.frame() == normal, "exit animation stops on normal final frame")
			check(flag.wait >= 1.4 and flag.wait <= 8.4, "random wait remains independent of animation")
		flag.advance(11)
		check(flag.elapsed == 0 and flag.wait >= 3 and flag.wait <= 10.1, "random idle wave restarts source range")

func _soldiers() -> void:
	var definition := Levels.load_definition(3)
	for type: String in ["soldier_militia", "soldier_footmen", "re_farmer"]:
		for enemy_type: String in ["enemy_goblin", "enemy_fat_orc", "enemy_wolf_small", "enemy_shaman", "enemy_ogre"]:
			for right in [false, true]:
				var sim = Sim.new(definition, 42)
				sim.notices.clear()
				var center := Vector2(532, 439)
				var enemy: Dictionary = sim._spawn_enemy(enemy_type, 0)
				enemy.pos = center; enemy.last_dir = Vector2(1 if right else -1, 0.8)
				var units: Array = []
				for rank in range(3):
					var s: Dictionary = sim._soldier(type, "", rank, center + Vector2(-35, -20), center)
					s.rallying = false; s.target = enemy.id; s.attack_at = 10000
					enemy.blockers.append(s.id); units.append(s)
					s.state = "running"
					sim._soldier_step(s)
					enemy.blocker = enemy.blockers[0]
				for s: Dictionary in units:
					for step in range(80): sim._soldier_step(s)
					var at: Vector2 = s.pos
					check(at.is_equal_approx(sim.melee_slot(s, enemy)), "soldier reaches rank/size/heading slot " + type + "/" + enemy_type)
					for step in range(12): sim._soldier_step(s)
					check(s.pos == at and s.state == "idle", "at slot while cooling down never runs in place")
				# A kill clears all blocks; nearby replacement can reuse the exact slot.
				sim.damage(enemy, 99999, 1)
				var next: Dictionary = sim._spawn_enemy(enemy_type, 0)
				next.pos = center; next.last_dir = enemy.last_dir
				for s: Dictionary in units: sim._soldier_step(s)
				for s: Dictionary in units:
					for step in range(80): sim._soldier_step(s)
					check(s.target == next.id and s.state == "idle", "post-kill reacquisition stops during cooldown")
				sim.damage(next, 99999, 1)
				for s: Dictionary in units:
					for step in range(80): sim._soldier_step(s)
					check(s.target == 0 and s.pos == s.dest and s.state == "idle", "no enemies returns to formation then idles")
	# The search center is the shared rally point, even after a distant engagement.
	var sim = Sim.new(definition, 42); sim.notices.clear()
	var s: Dictionary = sim._soldier("soldier_militia", "", 0, Vector2(100, 100), Vector2(532, 439))
	s.rallying = false
	var e: Dictionary = sim._spawn_enemy("enemy_goblin", 0); e.pos = s.rally_center
	sim._soldier_step(s)
	check(s.target == e.id, "target acquisition uses rally center rather than own position")
	# Secondary blockers peel off to a free target; primary keeps the existing one.
	var second: Dictionary = sim._soldier("soldier_footmen", "", 1, e.pos, e.pos)
	second.rallying = false; second.target = e.id; e.blockers.append(second.id)
	var alternate: Dictionary = sim._spawn_enemy("enemy_goblin", 0); alternate.pos = e.pos + Vector2(10, 0)
	sim._soldier_step(second)
	check(second.target == alternate.id and s.target == e.id and not e.blockers.has(second.id), "secondary blocker changes to free enemy")
	# Golden positions from U.melee_slot_position: goblin 18 + soldier 5,
	# secondary ranks subtract 3 on x and offset y by -6/+6.
	var golden = Sim.new(definition, 42)
	var goblin: Dictionary = golden._spawn_enemy("enemy_goblin", 0); goblin.pos = Vector2(500, 300); goblin.last_dir = Vector2.RIGHT
	for rank in range(3):
		var soldier: Dictionary = golden._soldier("soldier_militia", "", rank, goblin.pos, goblin.pos)
		goblin.blockers.append(soldier.id)
		check(golden.melee_slot(soldier, goblin) == [Vector2(523, 300), Vector2(520, 294), Vector2(520, 306)][rank], "Dove golden blocking slot %d" % rank)

func _waves(app: Control) -> void:
	for id in [1, 2, 3]:
		app._start_level(id, 1, 2)
		var battle: Control = app.battle
		battle.set_process(false); battle.sim.notices.clear()
		var flags: RefCounted = battle.interface.wave_flags
		flags.sync()
		check(flags.active.size() == 1, "first wave shows its active entrance only")
		for flag: Dictionary in flags.active:
			var pos: Vector2 = flags.position(flag)
			check(Rect2(60, 60, battle.view_width - 120, 648).has_point(pos) or pos.y == 60, "entrance icon stays inside screen")
			for row: Dictionary in flag.report: check(not row.name.begins_with("ENEMY_"), "incoming enemy name translated")
		battle._action("wave"); flags.sync()
		check(flags.active.is_empty() and flags.fading.size() == 1, "sending wave disables active entrances and fades old icon")
		flags.advance(0.51); flags.sync()
		check(flags.fading.is_empty(), "icon fade releases old flag")
		battle.sim.spawn_queue.clear(); battle.sim.next_wave_tick = battle.sim.tick + int(battle.sim.data.waves.groups[1].interval)
		flags.sync()
		check(not flags.active.is_empty(), "countdown makes next wave entrances available")
		var flag: Dictionary = flags.active[0]
		battle.hovered = "wave" + str({"path":flag.path}); flags.advance(0.3)
		check(flags.tooltip_alpha == 1 and not flags.tooltip.is_empty(), "hover reveals incoming report")
		battle.hovered = ""; flags.advance(0.3)
		check(flags.tooltip.is_empty() and not flag.is_empty() and not flags.active[0].is_empty(), "leaving tooltip never destroys active entrance")
		battle.targeting = "fire"
		check(not flags.enabled() and flags.hovered_flag().is_empty(), "spell targeting suppresses entrance interaction")
		battle.targeting = ""; battle.sim.paused = true
		check(not flags.enabled(), "pause suppresses entrance interaction")
		battle.sim.paused = false
		if id == 3:
			battle.sim.wave = 3; battle.sim.next_wave_tick = battle.sim.tick + int(battle.sim.data.waves.groups[3].interval)
			flags.sync()
			check(flags.active.size() == 2, "dual-path next wave shows both icons")
			for entrance: Dictionary in flags.active:
				var count := 0
				for row: Dictionary in entrance.report: count += int(row.count)
				var expected := 0
				for wave: Dictionary in battle.sim.data.waves.groups[3].waves:
					if int(wave.path_index) == int(entrance.path):
						for spawn: Dictionary in wave.spawns: expected += int(spawn.max)
				check(count == expected, "incoming counts belong to the hovered path")
		var gold: int = battle.sim.gold
		var reward := ceili(roundi((battle.sim.next_wave_tick - battle.sim.tick) / 30.0) * float(battle.sim.data.rules.early_wave_reward_per_second))
		battle._action("wave", {"path":flag.path})
		check(battle.sim.gold == gold + reward, "entrance command preserves early-wave reward")
		flags.sync(); check(flags.active.is_empty(), "one entrance starts the entire group")
		battle._action("map"); await app.map_ready

func _run() -> void:
	_flags(); _soldiers()
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://interaction_settings_" + token + ".json"; app.progress_path = "user://interaction_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in [1, 2, 3]: app.campaign.record_result({"generation":1, "level_id":id, "mode":1, "difficulty":2, "result":"victory", "lives":20})
	await _waves(app)
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures}
	var file := FileAccess.open("res://reports/interaction_fixes_logic.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("INTERACTION_FIXES: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
