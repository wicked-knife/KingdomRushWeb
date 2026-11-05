extends SceneTree
## Copied into a project with no source assets or scripts before execution.
var failures: Array[String] = []
var checks := 0
var app: Control
var captures := ""
var url := ""
var background_transfers: Array[String] = []

func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func wait_for(condition: Callable, seconds: float = 30.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < until: await process_frame
	return condition.call()

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(name + ".png"))

func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	event.position = root.get_final_transform() * point
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await process_frame

func _run() -> void:
	create_timer(165.0).timeout.connect(func(): push_error("Isolated native acceptance timed out"); quit(1))
	var args := OS.get_cmdline_user_args()
	url = args[1]; captures = args[2]
	check(ProjectSettings.load_resource_pack(args[0]), "boot PCK mounts")
	check(not FileAccess.file_exists("res://data/level01/manifest.json"), "boot excludes first-level data")
	check(not FileAccess.file_exists("res://data/map_kr1/atlas.json"), "boot excludes map artwork")
	check(FileAccess.file_exists("res://data/map_kr1/definition.json") and FileAccess.file_exists("res://data/heroes/definition.json"), "save preview definitions remain in boot")
	app = load("res://scenes/app_root.tscn").instantiate()
	app.settings_path = "user://pack_acceptance_%d/settings.json" % Time.get_ticks_usec()
	app.slots_path = app.settings_path + ".slots"
	root.add_child(app)
	if not await wait_for(func(): return app.menu != null): check(false, "cold menu opens"); quit(1); return
	check(app.packs.network_requests == 0 and app.packs.mounted.is_empty(), "menu makes no deferred requests")
	await capture("menu")
	app.menu.start_button.pressed.emit()
	app.menu._select_slot(1)
	if not await wait_for(func(): return app.campaign_map != null): check(false, "downloaded map opens"); quit(1); return
	check(not FileAccess.file_exists("res://data/heroes/atlas.json"), "map does not load hero room artwork")
	await capture("map")
	app.campaign_map._action("heroes")
	var room: Control = app.campaign_map.hero_room
	if not await wait_for(func(): return room.loader.loaded): check(false, "downloaded hero room opens"); quit(1); return
	await capture("heroes")
	app.campaign_map.close_overlay()
	await process_frame
	await RenderingServer.frame_post_draw
	var map: Control = app.campaign_map
	await click(map.world_to_screen(Vector2(294, 803)) * map.zoom)
	check(map.overlay == "level" and map.selected_level == 1, "native pointer opens first flag")
	await process_frame
	var buttons: Array = map.hits.filter(func(hit): return hit.action == "battle" and hit.enabled)
	check(not buttons.is_empty(), "battle control is available")
	app.packs.transfer_started.connect(func(id: String, background: bool):
		if background: background_transfers.append(id)
	)
	if not buttons.is_empty(): await click(buttons[0].rect.get_center() * map.zoom)
	if not await wait_for(func(): return app.battle != null): check(false, "native click enters downloaded first level"); quit(1); return
	check(background_transfers.is_empty(), "prefetch does not start during foreground entry")
	await capture("level01")
	await create_timer(3.6).timeout
	check(not background_transfers.is_empty(), "next-level prefetch starts after three seconds")
	check(not FileAccess.file_exists("res://data/level02/manifest.json"), "prefetch does not mount the next level")
	check(app.audio.music_player.playing and app.audio.music_player.get_playback_position() > 0, "native music playback advances")
	app._return_to_map()
	if not await wait_for(func(): return app.campaign_map != null): check(false, "return to map"); quit(1); return
	app.campaign.data.levels[3] = {1: 2, "stars": 3}
	app.packs.base_url = url + "missing/"
	app._start_level(3, 1, 2)
	check(await wait_for(func(): return app.retry.visible), "download error exposes retry")
	check(app.battle == null and app.campaign_map != null and app.back.visible, "failed download retains map and return control")
	await capture("download_failure")
	app.back.pressed.emit()
	check(not app.loading.visible and app.campaign_map.visible, "return control restores original map")
	app._start_level(3, 1, 2)
	await wait_for(func(): return app.retry.visible)
	app.packs.base_url = url
	app.retry.pressed.emit()
	if not await wait_for(func(): return app.battle != null): check(false, "retry loads third level"); quit(1); return
	check(not app.loading.visible, "successful retry dismisses error overlay")
	for number: int in [7, 11]:
		app._return_to_map()
		await wait_for(func(): return app.campaign_map != null)
		app.campaign.data.levels[number] = {1: 2, "stars": 3}
		app.campaign.data.heroes.selected = ["hero_malik"]
		app._start_level(number, 1, 2)
		if not await wait_for(func(): return app.battle != null): check(false, "representative level %d loads" % number); quit(1); return
		check(app.battle.sim.soldiers.any(func(soldier): return soldier.template == "hero_malik"), "selected hero bundle loads for level %d" % number)
		await capture("level%02d" % number)
	app._return_to_map(); await wait_for(func(): return app.campaign_map != null)
	app._return_to_menu(); await process_frame
	check(app.menu.visible and app.packs._background.is_empty(), "return to menu stops prefetch")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "independent_scenarios": 8, "native_window": true, "native_input": true, "native_audio_playback": true, "browser_tested": false, "boot_sha256": FileAccess.get_sha256(args[0]), "manifest_sha256": FileAccess.get_sha256("res://data/web_packs.json"), "test_sha256": FileAccess.get_sha256(get_script().resource_path), "network_requests": app.packs.network_requests, "mounted_packs": app.packs.mounted.size(), "background_transfers": background_transfers.size()}
	var output := FileAccess.open(captures.path_join("report.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t")); output.close()
	print("WEB_PACKS_NATIVE: ", JSON.stringify(report))
	app.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
