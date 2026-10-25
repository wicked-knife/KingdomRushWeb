extends SceneTree
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Slots = preload("res://scripts/services/save_slots.gd")
const Loader = preload("res://scripts/services/hero_loader.gd")
const App = preload("res://scenes/app_root.tscn")
var checks := 0
var failures: Array[String] = []
var temporary := "user://hero_test_" + str(Time.get_ticks_usec())
func _init() -> void: call_deferred("_run")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)
func write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
func victory() -> Dictionary: return {"generation": 1, "level_id": 1, "mode": 1, "difficulty": 2, "lives": 20, "result": "victory"}
func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Hero test timeout"); quit(1))
	DirAccess.make_dir_recursive_absolute(temporary)
	var p := Progress.new(); p.initialize(temporary + "/campaign.json")
	check(p.hero_rows.size() == 79 and p.selected_hero_ids().is_empty(), "new save has the full roster and no selected hero")
	check(not p.select_hero("hero_gerald") and not p.select_hero("unknown"), "locked and unknown heroes cannot be selected")
	p.record_result(victory())
	var available: Array = p.hero_rows.keys().filter(func(id): return p.is_hero_unlocked(id))
	check(available.size() == 12 and not p.is_hero_unlocked("hero_malik"), "source stage-one completion unlocks exactly twelve heroes")
	var a: String = available[0]; var b: String = available[1]; var c: String = available[2]
	check(p.select_hero(a) and p.select_hero(b) and p.selected_hero_ids() == [a, b], "two heroes retain insertion order")
	check(not p.select_hero(a) and p.selected_hero_ids() == [a, b], "duplicate selection is a no-op")
	check(p.select_hero(c) and p.selected_hero_ids() == [a, c], "third selection replaces only slot two")
	check(p.deselect_hero(a) and p.selected_hero_ids() == [c], "removing slot one moves slot two forward")
	var restored := Progress.new(); restored.initialize(p.path)
	check(restored.selected_hero_ids() == [c] and restored.total_stars() == 3, "selection and campaign reload together")
	check(restored.deselect_hero(c) and restored.selected_hero_ids().is_empty(), "last selected hero can be removed")
	restored.select_hero(c)
	var improved := victory(); improved.difficulty = 3; p.record_result(improved)
	restored.initialize(p.path); check(restored.selected_hero_ids() == [c], "battle result preserves hero configuration")
	write(p.path, {"schema_version": 1, "generation": 1, "levels": p.levels, "heroes": {"selected": [a, a, "invalid", "hero_gerald", b, c, 1]}})
	restored.initialize(p.path); check(restored.selected_hero_ids() == [a, b], "malformed selections are deduplicated filtered and capped")
	write(p.path, "broken"); restored.initialize(p.path)
	check(restored.selected_hero_ids() == [c] and not restored.notice.is_empty(), "valid backup restores heroes with progress")
	write(p.path, {"schema_version": 1, "generation": 1, "levels": p.levels})
	restored.initialize(p.path); check(restored.selected_hero_ids().is_empty(), "pre-feature schema-one save loads with empty selection")
	write(p.path, {"schema_version": 1, "generation": 1, "levels": p.levels, "heroes": "bad"})
	restored.initialize(p.path); check(restored.selected_hero_ids().is_empty() and restored.total_stars() == 3, "bad hero data does not destroy campaign")
	var slots := Slots.new(); slots.initialize(temporary + "/slots", temporary + "/absent.json")
	var first: RefCounted = slots.select_slot(1); first.record_result(victory()); first.select_hero(a)
	var second: RefCounted = slots.select_slot(2)
	check(second.selected_hero_ids().is_empty() and not second.is_hero_unlocked(a), "new slot has independent unlocks and selection")
	check(slots.select_slot(1).selected_hero_ids() == [a], "returning to first slot restores its selection")
	check(slots.delete_slot(1) and slots.select_slot(1).selected_hero_ids().is_empty(), "deleted slot cannot resurrect heroes from backup")
	restored.initialize(temporary + "/missing_parent/campaign.json"); restored.levels = p.levels.duplicate(true)
	check(restored.select_hero(a) and restored.selected_hero_ids() == [a] and not restored.notice.is_empty(), "failed save keeps session selection and reports failure")
	var loader := Loader.new(); root.add_child(loader)
	check(not await loader.initialize("res://data/absent_hero_manifest.json") and not loader.error_message.is_empty(), "missing manifest produces retryable failure")
	write(temporary + "/bad_manifest.json", {"schema_version": 1, "resources": ["res://data/heroes/missing.png"]})
	check(not await loader.initialize(temporary + "/bad_manifest.json"), "missing dependency fails")
	check(await loader.initialize(), "hero resource loader retries successfully")
	loader.queue_free(); await process_frame
	var app := App.instantiate(); app.settings_path = temporary + "/settings.json"; app.progress_path = temporary + "/route.json"
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	var map: Control = app.campaign_map
	check(map.hero_room == null, "map bootstrap does not construct or load hero-room resources")
	map._action("heroes")
	var room: Control = map.hero_room
	while not room.loader.loaded: await process_frame
	check(map.overlay == "heroes" and room.visible and room.shown == "hero_gerald", "map opens room with source default preview")
	var camera: Dictionary = map.snapshot(); map.pan(Vector2(-100, -100)); map.set_map_zoom(2, Vector2.ZERO)
	check(map.snapshot() == camera, "hero modal prevents map movement")
	app.campaign.record_result(victory()); room.show_hero(a); room._action("select"); room.show_hero(b); room._action("select")
	check(app.campaign.selected_hero_ids() == [a, b], "hero room actions persist two heroes")
	room.tab_focus(); check(room.shown == a and room.scroll.scroll_vertical > 0, "Tab cycles selected heroes and brings their row into view")
	room._action("toggle"); room._action("skill", {"index": 0})
	check(room.details_mode and not room.detail_text.text.is_empty(), "computed skill descriptions are accessible")
	map.close_overlay(); check(not room.visible and map.overlay == "", "closing room clears modal state")
	map._action("level", {"id": 1}); map._action("battle"); await process_frame
	check(app.battle != null and app.campaign.selected_hero_ids() == [a, b] and app.battle.sim.soldiers.is_empty(), "selection retained while existing battle begins without heroes")
	app._return_to_map(); await app.map_ready
	check(app.campaign.selected_hero_ids() == [a, b] and app.campaign_map.hero_room == null, "map return preserves selection and frees room resources")
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "heroes": 79, "failures": failures}
	write("res://reports/heroes_logic.json", report)
	print("HERO_LOGIC: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
