extends SceneTree
const Fixture = preload("res://tests/slot_fixture.gd")
const Settings = preload("res://scripts/services/menu_settings.gd")
const Slots = preload("res://scripts/services/save_slots.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const App = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var checks := 0
var temporary := "user://playtest_tools_" + str(Time.get_ticks_usec())

func _init() -> void: call_deferred("_run")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)
func write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(value)); f.close()
func win(lives: int = 20) -> Dictionary:
	return {"level_id": 1, "mode": 1, "difficulty": 2, "result": "victory", "lives": lives}
func clear_notices(sim: RefCounted) -> void:
	while not sim.notices.is_empty(): check(sim.command("confirm"), "confirm source tutorial")

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Playtest tools timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(temporary)
	_test_saves()
	_test_developer()
	await _test_route()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "web_tested": false}
	var f := FileAccess.open("res://reports/playtest_tools_logic.json", FileAccess.WRITE); f.store_string(JSON.stringify(report)); f.close()
	print("PLAYTEST_TOOLS: ", JSON.stringify(report))
	_remove_tree(temporary)
	quit(0 if failures.is_empty() else 1)

func _test_saves() -> void:
	var preferences := Settings.new(); preferences.initialize(temporary + "/preferences.json")
	var slots := Slots.new(); slots.initialize(temporary + "/slots", preferences)
	check(slots.status(1) == "empty" and slots.status(2) == "empty" and slots.status(3) == "empty", "new storage has three empty slots")
	var first := slots.select_slot(1); Fixture.complete(first, win(17))
	var second := slots.select_slot(2)
	check(second.total_stars() == 0 and second.unlocked == [1], "new second slot starts clean")
	Fixture.complete(second, win(20))
	check(first.total_stars() == 2 and second.total_stars() == 3, "slot scores isolated")
	var third := slots.select_slot(3); Fixture.complete(third, win(5))
	var reloaded := Slots.new(); reloaded.initialize(slots.directory, preferences)
	check(reloaded.last_slot == 3, "last selected slot persists")
	check(reloaded.select_slot(1).total_stars() == 2 and reloaded.select_slot(2).total_stars() == 3 and reloaded.select_slot(3).total_stars() == 1, "all three campaigns reload independently")
	check(reloaded.delete_slot(1) and reloaded.status(1) == "empty", "delete clears campaign and backup together")
	reloaded.initialize(slots.directory, preferences)
	check(reloaded.status(1) == "empty", "deleted slot stays deleted after reload")
	check(reloaded.select_slot(1).total_stars() == 0, "deleted slot can start a fresh campaign")
	check(reloaded.select_slot(0) == null and not reloaded.delete_slot(4), "invalid slot identifiers rejected")
	var path := reloaded.slot_path(2)
	var second_again := reloaded.select_slot(2); second_again.save()
	write(path, "corrupt")
	reloaded.initialize(slots.directory, preferences)
	check(reloaded.status(2) == "used" and reloaded.select_slot(2).total_stars() == 3, "corrupt primary recovers a valid backup")
	DirAccess.remove_absolute(path)
	reloaded.initialize(slots.directory, preferences)
	check(reloaded.select_slot(2).total_stars() == 3, "missing primary also recovers backup")
	write(path, "corrupt"); write(path + ".bak", "corrupt")
	reloaded.initialize(slots.directory, preferences)
	check(reloaded.status(2) == "corrupt" and reloaded.select_slot(2) == null, "unrecoverable slot cannot be overwritten as empty")
	write(path, {"schema_version": 99}); reloaded.initialize(slots.directory, preferences)
	check(reloaded.status(2) == "future" and reloaded.select_slot(2) == null, "future schema protected")
	check(reloaded.delete_slot(2) and reloaded.status(2) == "empty", "corrupt/future slot can be explicitly deleted")
	var readonly := Slots.new()
	write(temporary + "/not_a_directory", "file")
	readonly.initialize(temporary + "/not_a_directory/slots")
	var session := readonly.select_slot(1); Fixture.complete(session, win())
	check(session.total_stars() == 3 and not session.notice.is_empty(), "write failure preserves session progress")
	check(readonly.select_slot(1) == session, "unsaved session survives selection round trip")
	var failure := Slots.new(); failure.initialize(temporary + "/delete_failure")
	Fixture.complete(failure.select_slot(1), win())
	var before: String = FileAccess.get_file_as_string(failure.slot_path(1))
	# Holding an open file denies directory removal on Windows.
	if OS.get_name() == "Windows":
		var held := FileAccess.open(failure.slot_path(1), FileAccess.READ)
		check(not failure.delete_slot(1) and failure.status(1) == "used", "failed delete retains the slot")
		check(FileAccess.get_file_as_string(failure.slot_path(1)) == before, "failed delete preserves bytes")
		held.close()

	preferences.free()

func _test_developer() -> void:
	var production := Sim.new()
	for command in ["dev_add_gold", "dev_add_lives", "dev_skip_wave"]:
		check(not production.command(command), "production simulation rejects " + command)
	check(production.gold == 270 and production.lives == 20, "rejected debug commands leave state intact")
	var sim := Sim.new({}, 1, true)
	check(not sim.command("dev_skip_wave"), "cannot skip before first wave")
	sim.paused = true
	check(sim.command("dev_add_gold") and sim.command("dev_add_lives") and sim.gold == 10270 and sim.lives == 120, "debug increments work while paused/tutorial visible")
	sim.command("dev_add_gold"); sim.command("dev_add_lives")
	check(sim.gold == 20270 and sim.lives == 220, "repeat increments accumulate")
	sim.paused = false; clear_notices(sim); sim.command("wave")
	for i in range(55): sim.step()
	check(sim.enemies.size() == 1 and sim.spawn_queue.size() == 2, "skip fixture contains live and queued enemies")
	var enemy: Dictionary = sim.enemies[0]
	var soldier: Dictionary = sim._soldier("soldier_militia", "1", 0, enemy.pos, enemy.pos)
	soldier.target = enemy.id; soldier.pending = {"at": sim.tick + 1}; enemy.blockers = [soldier.id]; enemy.blocker = soldier.id
	sim._projectile("arrow_1", enemy.id, enemy.pos + Vector2(50, 50), enemy.pos, 1.0)
	var expected_gold := sim.gold + int(sim.templates[enemy.template].enemy.gold)
	sim.cooldowns.fire = 450
	var source_tick := sim.tick; var source_lives := sim.lives
	check(sim.command("dev_skip_wave"), "skip accepts active wave")
	check(sim.wave == 2 and sim.gold == expected_gold and sim.kills == 1, "only spawned enemies award gold; no early-wave reward")
	check(sim.enemies.all(func(e): return e.hp <= 0) and sim.projectiles.is_empty() and soldier.target == 0 and soldier.pending.is_empty(), "skip clears enemies, projectiles and blocking references")
	check(sim.tick == source_tick and sim.lives == source_lives and sim.cooldowns.fire == 450 and sim.soldiers.size() == 1, "skip retains simulation time, lives, cooldowns and soldiers")
	check(sim.command("dev_skip_wave") and sim.wave == 3 and "POWER_REINFORCEMENT" in sim.notices, "third-wave teaching still appears")
	check(not sim.command("dev_skip_wave") and not sim.unlocked.reinforcements, "teaching confirmation cannot be bypassed by skip")
	clear_notices(sim)
	check(sim.unlocked.reinforcements, "reinforcements unlock on confirmation")
	for i in range(4): sim.command("dev_skip_wave")
	check(sim.wave == 7 and "POWER_FIREBALL" in sim.notices and not sim.unlocked.fire, "seventh-wave fire teaching preserved")
	clear_notices(sim); check(sim.unlocked.fire, "fire unlocks on confirmation")
	var outcomes := []
	sim.event.connect(func(kind, payload):
		if kind == "finished": outcomes.append(payload)
	)
	check(sim.command("dev_skip_wave") and sim.result == "victory", "last wave skips to victory")
	check(not sim.command("dev_skip_wave") and not sim.command("dev_add_lives") and outcomes.size() == 1, "result emitted once and post-result debug commands disabled")
	sim.reset()
	check(not sim.developer_used and sim.lives == 20 and sim.gold == 270 and sim.speed == 1 and sim.wave == 0, "restart clears debug state")

func _test_route() -> void:
	var app := App.instantiate(); app.settings_path = temporary + "/settings.json"; app.slots_path = temporary + "/route.json"
	root.add_child(app); await app.menu_ready
	var fonts: RefCounted = app.loader.fonts
	for entry in [["h", "JIMOJW"], ["button", "JIMOJW"], ["body", "Microsoft YaHei"], ["numbers", "Comic Book"], ["numbers_bold", "Toonish"]]:
		check(fonts.font_for(entry[0]).get_font_name() == entry[1], "font role resolves " + entry[0])
	check(fonts.font_for("button").has_char(0x90ca) and not fonts.font_for("button").allow_system_fallback, "explicit Chinese glyphs without host fallback")
	app.menu.start_button.pressed.emit()
	check(app.menu.slots_open and app.campaign_map == null, "Start expands save panel before entering map")
	app.menu._select_slot(1); await app.map_ready
	app._start_level(1, 1, 2)
	var battle: Control = app.battle
	battle.set_process(false)
	battle.sim.developer_enabled = false; battle.developer.toggle()
	check(not battle.developer.opened and not battle.sim.command("dev_add_gold"), "disabled developer capability blocks both view and simulation")
	battle.sim.developer_enabled = true
	battle.developer.toggle()
	check(battle.developer.opened and battle.sim.paused, "developer menu pauses battle")
	battle._action("dev_add_gold"); battle._action("dev_add_lives")
	battle._action("wave")
	check(battle.sim.wave == 0, "developer overlay rejects underlying actions")
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true; battle._input(esc)
	check(not battle.developer.opened and not battle.sim.paused, "Escape closes developer menu before tutorial and restores play state")
	battle.sim.paused = true; battle.developer.toggle(); battle.developer.close()
	check(battle.sim.paused, "existing pause preserved")
	battle.sim.paused = false; clear_notices(battle.sim); battle._action("wave")
	for wave in range(7):
		clear_notices(battle.sim); battle.developer.toggle(); battle._action("dev_skip_wave")
	check(battle.outcome.get("developer_used", false) and app.campaign.summary().stars == 3 and not app.campaign.is_unlocked(2), "debug victory follows pending-result path")
	app._return_to_map(); await app.map_ready
	check(app.campaign_map.progress.total_stars() == 3, "return map shows same saved score")
	app.campaign_map.set_map_zoom(2, app.campaign_map.view_size / 2)
	app._return_to_menu(); await process_frame
	app.menu._confirm_delete(1); app.menu.close_modal()
	check(app.slots.status(1) == "used", "cancel deletion preserves campaign")
	app.menu._confirm_delete(3)
	check(app.menu.slot_panel.get_node("Slot1").focus_mode == Control.FOCUS_NONE, "modal removes underlying slot keyboard focus")
	app.menu._select_slot(2)
	check(app.campaign_map == null, "modal blocks underlying slot selection")
	app.menu.close_modal()
	app.menu._select_slot(2); await app.map_ready
	check(app.campaign.total_stars() == 0 and app.campaign_map.magnification == 1, "switching slot resets score and camera")
	app._return_to_menu(); await process_frame
	app.menu._select_slot(1); await app.map_ready
	check(app.campaign.total_stars() == 3 and app.campaign_map.magnification == 2, "original slot restores its own camera and progress")
	app.queue_free(); await process_frame; await process_frame

func _remove_tree(path: String) -> void:
	# Only this test's unique directory may be removed, never a player save root.
	assert(path.begins_with(temporary))
	for name in DirAccess.get_directories_at(path): _remove_tree(path + "/" + name)
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path + "/" + name)
	DirAccess.remove_absolute(path)
