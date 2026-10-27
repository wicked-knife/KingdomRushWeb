extends SceneTree
const Fixture = preload("res://tests/slot_fixture.gd")
const App = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var label_checks := 0
var app: Control
var map: Control
var suffix := ""
var temporary := "user://map_visual_" + str(Time.get_ticks_usec())

func _init() -> void: call_deferred("_run")
func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(temporary)
	app = App.instantiate(); app.settings_path = temporary + "/settings.json"; app.slots_path = temporary + "/campaign.json"
	root.add_child(app); await app.menu_ready
	if "--interactive" in OS.get_cmdline_user_args(): return
	create_timer(60).timeout.connect(func(): push_error("Map visual timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	map = app.campaign_map
	await create_timer(0.7).timeout
	check(app.audio.music_player.playing and app.audio.music_player.get_playback_position() > 0, "map music playback advances in native audio")
	await capture("map_initial")
	var position: Vector2 = map.world_to_screen(Vector2(294, 803))
	await click(position)
	check(map.overlay == "level" and map.selected_level == 1, "native input opens flag one")
	await capture("map_level01")
	check(map.paint.audit.any(func(row): return row.id == "level_history"), "Chinese source history drawn")
	await hover("battle", {}, "map_battle_hover")
	var old: Dictionary = map.snapshot()
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true; wheel.position = map.view_size / 2 * map.zoom
	map._gui_input(wheel)
	check(map.snapshot() == old, "popup prevents wheel penetration")
	var key := InputEventKey.new(); key.keycode = KEY_ESCAPE; key.pressed = true; map._input(key)
	await process_frame
	check(map.overlay == "", "Escape closes selection")
	map._input(key); await process_frame
	check(map.overlay == "options", "Escape opens map settings")
	await capture("map_options")
	var hit: Dictionary = map.hits.filter(func(row): return row.action == "volume" and row.args.bus == "music")[0]
	await click(hit.rect.position + hit.rect.size * Vector2(0.4, 0.5))
	check(app.settings.music_volume > 0.1 and app.settings.music_volume < 0.6, "native slider input applies inherited volume")
	map.close_overlay()
	# Presentation fixtures unlock later panels without adding game-facing shortcuts.
	for id in range(1, 13): Fixture.complete(app.campaign, {"level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	map._action("level", {"id": 2}); await capture("map_level02_unavailable")
	check(map.hits.any(func(row): return row.action == "battle" and not row.enabled), "second battle disabled")
	await click(map.view_size / 2, MOUSE_BUTTON_RIGHT)
	check(map.overlay == "", "right click closes selection")
	map._action("level", {"id": 1}); await process_frame
	await hover("mode", {"mode": 2}, "map_mode_heroic_hover")
	var mode_hit: Dictionary = map.hits.filter(func(row): return row.action == "mode" and row.args.mode == 2)[0]
	await click(mode_hit.rect.get_center()); check(map.mode == 2, "heroic banner input selects its own panel")
	await capture("map_heroic")
	await hover("mode", {"mode": 3}, "map_mode_iron_hover")
	mode_hit = map.hits.filter(func(row): return row.action == "mode" and row.args.mode == 3)[0]
	await click(mode_hit.rect.get_center()); check(map.mode == 3, "iron banner input selects its own panel")
	await capture("map_iron")
	for id in [1, 2, 12, 13, 26, 1000]:
		# Directly select hidden future fixtures to verify their real source texts and thumbnails.
		map.selected_level = id; map.mode = 1; await capture("map_detail_%d" % id, false)
	map.close_overlay(); map.set_map_zoom(2.5, map.view_size / 2); map.pan(Vector2(-100000, -100000)); await capture("map_zoom_bounds")
	check(map.camera_offset.x <= 0 and map.camera_offset.y <= 0, "camera bounded")
	# Cover the widest valid star count with this test's isolated campaign only.
	for stage: Dictionary in map.definition.levels:
		map.progress.levels[int(stage.id)] = {1: 2, "stars": 3, 2: 2, 3: 2}
	await capture("map_stars_maximum")
	await click(map.view_size / 2, MOUSE_BUTTON_RIGHT)
	app._return_to_menu(); await process_frame
	check(app.menu.visible and app.campaign_map == null, "settings can return to menu")
	app.queue_free(); await process_frame; await process_frame
	for name: String in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary + "/" + name)
	DirAccess.remove_absolute(temporary)
	var report := {"passed": failures.is_empty(), "resolution": suffix, "text_boxes_checked": label_checks, "failures": failures}
	var f := FileAccess.open("res://reports/map_visual_" + suffix + ".json", FileAccess.WRITE); f.store_string(JSON.stringify(report)); f.close()
	print("MAP_VISUAL: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var down := InputEventMouseButton.new(); down.position = point * map.zoom; down.button_index = button; down.pressed = true
	map._gui_input(down)
	var up := InputEventMouseButton.new(); up.position = down.position; up.button_index = button
	map._gui_input(up)
	await process_frame

func hover(action: String, args: Dictionary, name: String) -> void:
	var hit: Dictionary = map.hits.filter(func(row): return row.action == action and (args.is_empty() or row.args.mode == args.mode))[0]
	var motion := InputEventMouseMotion.new(); motion.position = hit.rect.get_center() * map.zoom
	map._gui_input(motion); await capture(name)

func capture(name: String, save_image: bool = true) -> void:
	map.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	for row: Dictionary in map.paint.audit:
		label_checks += 1
		check(row.fits, "text fits " + name + "/" + str(row.id))
		check(Rect2(Vector2.ZERO, map.view_size).grow(1).encloses(row.box), "text stays on screen " + name + "/" + str(row.id))
	if save_image: root.get_texture().get_image().save_png("res://reports/" + name + "_" + suffix + ".png")
