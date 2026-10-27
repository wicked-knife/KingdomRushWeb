extends SceneTree
const Fixture = preload("res://tests/slot_fixture.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Animations = preload("res://scripts/map/map_animations.gd")
const App = preload("res://scenes/app_root.tscn")
const Loader = preload("res://scripts/services/map_loader.gd")
var failures: Array[String] = []
var checks := 0
var temporary := "user://map_test_" + str(Time.get_ticks_usec())

func _init() -> void: call_deferred("_run")
func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); push_error(name)
func write(path: String, value: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(value)); f.close()
func outcome(id: int, lives: int) -> Dictionary:
	return {"generation": 1, "level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": lives}

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Map tests timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(temporary)
	var map_loader := Loader.new(); root.add_child(map_loader)
	check(not await map_loader.initialize("res://data/absent_map.json") and not map_loader.error_message.is_empty(), "missing map manifest fails with retryable error")
	write(temporary + "/bad_manifest.json", {"schema_version": 1, "resources": ["res://data/map_kr1/absent.png"]})
	check(not await map_loader.initialize(temporary + "/bad_manifest.json"), "missing map dependency fails")
	check(await map_loader.initialize() and map_loader.loaded, "map loader retries successfully")
	map_loader.queue_free(); await process_frame
	var p := Progress.new(); p.initialize(temporary + "/progress.json")
	check(p.unlocked == [1] and p.total_stars() == 0, "new progress exposes only flag one")
	for lives in [0, 1, 5, 6, 17, 18, 20]: check(Progress.stars_for(lives) == {0: 0, 1: 1, 5: 1, 6: 2, 17: 2, 18: 3, 20: 3}[lives], "source star threshold %d" % lives)
	check(not Fixture.complete(p, outcome(2, 20)), "locked result rejected")
	check(Fixture.complete(p, outcome(1, 5)) and p.is_unlocked(2), "first win unlocks second flag")
	check(p.total_stars() == 1 and p.is_playable(2) and not p.is_playable(3) and not p.is_playable(2, 2), "availability requires unlock and implemented mode")
	check(Fixture.complete(p, outcome(1, 17)) and p.total_stars() == 2, "best score improves")
	check(not Fixture.complete(p, outcome(1, 1)) and p.total_stars() == 2, "lower score does not reduce progress")
	check(not Fixture.complete(p, outcome(1, 17)), "duplicate result is idempotent")
	var restored := Progress.new(); restored.initialize(p.path)
	check(restored.total_stars() == 2 and restored.is_unlocked(2), "progress survives reload")
	var defeated := outcome(1, 0); defeated.result = "defeat"
	check(not Fixture.complete(p, defeated), "defeat gives no progress")
	var invalid := outcome(1, 20); invalid.mode = 2
	check(not Fixture.complete(p, invalid), "unimplemented challenge gives no progress")
	check(p.record_result(outcome(1, 20)) and p.total_stars() == 2, "victory first persists pending result")
	var changes: Dictionary = p.enter_map()
	check(changes.stars["1"].before == 2 and changes.stars["1"].after == 3 and changes.unlocked.is_empty(), "map animates only this settlement")
	check(p.enter_map().stars.is_empty(), "map consumes presentation once")
	write(p.path, "broken")
	restored.initialize(p.path)
	check(restored.total_stars() == 2 and not restored.notice.is_empty(), "corrupt primary recovers backup")
	write(temporary + "/future.json", {"schema_version": 99, "generation": 1})
	restored.initialize(temporary + "/future.json"); Fixture.complete(restored, outcome(1, 20))
	check(not restored.save_allowed and JSON.parse_string(FileAccess.get_file_as_string(restored.path)).schema_version == 99, "future save remains intact")
	restored.initialize(temporary + "/absent_parent/progress.json"); Fixture.complete(restored, outcome(1, 20))
	check(restored.total_stars() == 3 and not restored.notice.is_empty(), "save failure retains session progress")
	# Fixtures exercise source branch heads without exposing a player unlock shortcut.
	for id in range(2, 13): check(Fixture.complete(p, outcome(id, 20)), "campaign progression %d" % id)
	for id in [13, 14, 15, 16, 18, 20, 22, 23, 1000]: check(p.is_unlocked(id), "post campaign branch %d" % id)
	for id in [17, 19, 21, 24, 25, 26]: check(not p.is_unlocked(id), "branch continuation stays locked %d" % id)
	for id in [13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 1000]: Fixture.complete(p, outcome(id, 20))
	check(p.unlocked.size() == 27 and p.total_stars() == 81, "all 27 source nodes supported")
	var definition: Dictionary = p.definition
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_kr1/atlas.json"))
	var player := Animations.new(definition.animations, 41)
	check(player.entries.size() == 124, "all map instances expanded")
	for step in range(300):
		player.advance(0.31)
		for layer in range(1, 4):
			for item: Dictionary in player.items(layer): check(atlas.lookup.has(item.image), "sampled frame resolves " + item.image)
	# Full app route, legitimate victory, empty-defense defeat, and repeated scene disposal.
	var app := App.instantiate(); app.settings_path = temporary + "/settings.json"; app.slots_path = temporary + "/route.json"
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	check(app.campaign_map != null and app.battle == null and not app.menu.visible, "menu enters map")
	var map: Control = app.campaign_map
	for point in [Vector2(294, 803), Vector2(1704, 669), Vector2(1800, 100)]:
		check(map.screen_to_world(map.world_to_screen(point)).distance_to(point) < 0.01, "camera invertible")
	map.set_map_zoom(2, map.view_size / 2); map.pan(Vector2(-200, -100))
	var camera: Dictionary = map.snapshot()
	map._action("level", {"id": 1}); var old: Vector2 = map.camera_offset
	map.pan(Vector2(100, 100)); map.set_map_zoom(3, Vector2.ZERO)
	check(map.camera_offset == old and map.magnification == 2, "modal blocks map pan and zoom")
	map.close_overlay(); app._start_level(2, 1, 2)
	check(app.battle == null and app.campaign_map == map, "router rejects unavailable level")
	# Touches use the same camera inverse transform, and never click after a pinch.
	var first := InputEventScreenTouch.new(); first.index = 0; first.position = map.view_size / 2 * map.zoom; first.pressed = true
	var second := InputEventScreenTouch.new(); second.index = 1; second.position = first.position + Vector2(80, 0); second.pressed = true
	map._gui_input(first); map._gui_input(second)
	var drag := InputEventScreenDrag.new(); drag.index = 1; drag.position = second.position + Vector2(80, 0)
	map._gui_input(drag)
	check(map.magnification == 3, "pinch clamps at three times")
	first.pressed = false; second.pressed = false; map._gui_input(first); map._gui_input(second)
	check(map.overlay == "" and map.touches.is_empty(), "pinch release cannot open a flag")
	map.set_map_zoom(camera.magnification, map.view_size / 2)
	map._action("level", {"id": 1}); map._action("battle")
	await process_frame
	check(app.battle != null and app.campaign_map == null and app.map_loader == null, "map enters battle and releases map")
	play(app.battle.sim, true)
	check(app.battle.outcome.result == "victory" and app.campaign.total_stars() == 0 and app.campaign.data.has("last_victory"), "legal full battle persists pending victory")
	var won: Dictionary = app.battle.outcome.duplicate()
	app.battle._action("restart")
	check(app.battle.outcome.is_empty() and app.battle.sim.speed == 1 and app.campaign.data.has("last_victory"), "restart retains pending victory without settling")
	play(app.battle.sim, false)
	check(app.battle.outcome.result == "defeat" and app.campaign.total_stars() == 0 and not app.campaign.data.has("last_victory"), "defeat clears unsettled victory")
	app.battle._action("restart"); play(app.battle.sim, true)
	app.battle._action("map"); await app.map_ready
	check(app.campaign.is_unlocked(2) and app.campaign_map.changes.unlocked == [2], "return animates newly unlocked level")
	var counts := app.get_child_count()
	for round in range(3):
		app.campaign_map._action("level", {"id": 1}); app.campaign_map._action("battle"); await process_frame
		app.battle._action("map"); await app.map_ready; await process_frame
		check(app.get_child_count() == counts and app.campaign_map.fx.size() == 4, "scene lifecycle stable %d" % round)
		check(app.campaign_map.magnification == camera.magnification, "camera scale retained %d" % round)
	app._return_to_menu(); await process_frame
	check(app.menu.visible and app.battle == null and app.campaign_map == null, "map returns to menu")
	app.queue_free(); await process_frame; await process_frame
	for name: String in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary + "/" + name)
	DirAccess.remove_absolute(temporary)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "victory": won, "nodes": 27, "animation_instances": 124}
	write("res://reports/map_kr1_logic.json", report)
	print("MAP_KR1_LOGIC: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func play(sim, defend: bool) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")
	if defend:
		for pair in [["1", "archer"], ["6", "mage"], ["4", "archer"]]: check(sim.command("build", {"id": pair[0], "type": pair[1]}), "legal starting defense")
	sim.command("wave")
	for tick in range(30000):
		while not sim.notices.is_empty(): sim.command("confirm")
		if defend:
			for id in ["8", "3", "7", "5", "2"]:
				if sim.gold >= 70 and sim.tower_by_id(id).type == "": sim.command("build", {"id": id, "type": "archer"})
			if sim.unlocked.reinforcements and sim.cooldowns.reinforcements == 0:
				var target: Dictionary = sim._target(Vector2(478, 228), 120)
				if not target.is_empty(): sim.command("cast", {"power": "reinforcements", "pos": target.pos})
			if sim.unlocked.fire and sim.cooldowns.fire == 0:
				var target: Dictionary = sim._target(Vector2(400, 440), 400)
				if not target.is_empty(): sim.command("cast", {"power": "fire", "pos": target.pos})
		sim.step()
		if sim.result != "": return
	check(false, "battle completed within timeout")
