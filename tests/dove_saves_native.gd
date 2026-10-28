extends SceneTree
## Native integration: physical mouse chooses the slot, both restarts, map and preview.
const App = preload("res://scenes/app_root.tscn")
const Fixture = preload("res://tests/slot_fixture.gd")
const Replay = preload("res://tests/level05_playback.gd")
var temporary := "user://dove_native_%d" % Time.get_ticks_usec()
var failures: Array[String] = []
var checks := 0
var app: Control
var captures := []
func _init() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func state(stage: String) -> void:
	var f := FileAccess.open("res://reports/dove_saves_native_state.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"stage": stage, "checks": checks, "failures": failures})); f.close()
	print("DOVE_NATIVE_STAGE: ", stage)
func capture(label: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	var path := "res://reports/dove_saves_" + label + ".png"
	root.get_texture().get_image().save_png(path); captures.append(path)
func replay(battle: Control, defend: bool) -> void:
	battle.set_process(false); battle.sim.reset(42)
	if not defend:
		while not battle.sim.notices.is_empty(): battle._action("confirm")
		battle._action("wave")
	for i in range(60000):
		if defend: Replay.commands(battle.sim, func(kind, args): battle._action(kind, args))
		elif not battle.sim.notices.is_empty(): battle._action("confirm")
		battle.sim.step()
		if battle.sim.result != "": break
		if i % 64 == 0: battle.queue_redraw(); await process_frame
	battle.queue_redraw(); await process_frame
func _run() -> void:
	create_timer(600).timeout.connect(func(): push_error("Dove native timeout"); quit(1))
	root.title = "Dove saves native check"
	DirAccess.make_dir_recursive_absolute(temporary)
	app = App.instantiate(); app.settings_path = temporary + "/settings.json"; app.slots_path = temporary + "/saves"
	root.add_child(app); await app.menu_ready
	# Content-entry fixture only; all three battles below use normal economy/public commands.
	var slot: RefCounted = app.slots.select_slot(1)
	for id in range(1, 5): Fixture.complete(slot, {"generation": 1, "level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	state("choose_slot"); await app.map_ready
	check(app.slots.active_slot == 1 and app.settings.last_slot_idx == 1 and app.campaign.is_playable(5), "physical slot selection opens settled campaign")
	await capture("fifth_map"); state("enter_fifth")
	while app.battle == null: await process_frame
	var battle: Control = app.battle
	await replay(battle, true)
	check(battle.outcome.result == "victory" and app.campaign.total_stars() == 12 and app.campaign.summary().stars == 14, "native victory persists pending two-star fifth result")
	check(not app.campaign.is_unlocked(6) and app.campaign.data.last_victory.level_idx == 5, "native next flag waits for map")
	await capture("pending_victory"); state("restart_after_victory")
	while not battle.outcome.is_empty(): await process_frame
	check(app.campaign.data.has("last_victory") and app.campaign.data.seen.get("enemy_marauder", false), "physical restart retains pending result and flushes encounters")
	await replay(battle, false)
	check(battle.outcome.result == "defeat" and not app.campaign.data.has("last_victory") and app.campaign.total_stars() == 12, "native defeat discards unsettled victory")
	await capture("discarded_victory"); state("restart_after_defeat")
	while not battle.outcome.is_empty(): await process_frame
	await replay(battle, true)
	check(battle.outcome.result == "victory" and Replay.failures.is_empty(), "native legal fifth replay wins again")
	state("return_to_map"); await app.map_ready
	check(app.battle == null and app.campaign.total_stars() == 14 and app.campaign.record(5)[1] == 2, "physical map return settles numeric mode record")
	check(app.campaign.is_unlocked(6) and app.campaign.is_playable(6) and not app.campaign.data.has("last_victory"), "native sixth campaign unlocked exactly once")
	check(not "tower_ranger" in app.campaign.data.locked_towers and not "tower_elf" in app.campaign.data.locked_towers, "native map settles tower unlocks")
	await capture("settled_map"); state("open_sixth_entry")
	while app.campaign_map.overlay != "level" or app.campaign_map.selected_level != 6: await process_frame
	await capture("sixth_entry")
	check(app.battle == null and app.campaign.is_playable(6), "physical sixth flag click shows playable entry before confirmation")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures, "physical_mouse": true, "resolution": [root.size.x, root.size.y], "legal_fifth_replays": 2, "empty_defense": true, "temporary": temporary}
	var f := FileAccess.open("res://reports/dove_saves_native.json", FileAccess.WRITE); f.store_string(JSON.stringify(report)); f.close()
	state("complete"); app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
