extends SceneTree
## Run with a rendering driver, e.g. --path . --script tests/menu_visual_smoke.gd --resolution 1280x720

const App = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var capture_directory := "res://reports"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(15.0).timeout.connect(func():
		push_error("Menu visual smoke test timed out")
		quit(1)
	)
	var app := App.instantiate()
	app.settings_path = "user://menu_visual_test_" + str(Time.get_ticks_usec()) + ".json"
	app.progress_path = app.settings_path + ".progress"
	root.add_child(app)
	await app.menu_ready
	var menu: Control = app.menu
	await create_timer(0.8).timeout
	var suffix := "%dx%d" % [root.size.x, root.size.y]
	await _capture("menu_" + suffix)
	menu.start_button.pressed.emit()
	await create_timer(0.2).timeout
	await _capture("menu_slots_empty_" + suffix)
	check(menu.slots_open and app.campaign_map == null, "Start opens save slots")
	menu._select_slot(1)
	await app.map_ready
	check(app.campaign_map != null and not menu.visible, "start opens generation-one map")
	app._return_to_menu(); await process_frame
	await _capture("menu_slots_zero_" + suffix)
	menu._select_slot(1); await app.map_ready
	app.campaign.record_result({"level_id": 1, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	# Native presentation fixtures cover multi-digit counters beside all three
	# painted icons. No player-facing progress shortcut is introduced.
	var full: RefCounted = app.slots.select_slot(2)
	for stage: Dictionary in full.definition.levels:
		full.levels[str(int(stage.id))] = {"campaign": 2, "stars": 3, "heroic": 2, "iron": 2}
	full.save(); full.changed.emit()
	app.slots.select_slot(1)
	app._return_to_menu()
	await process_frame
	await _capture("menu_slots_used_" + suffix)
	var delete_button: Control = menu.slot_panel.get_node("Slot1/DeleteSlot1")
	var click := InputEventMouseButton.new(); click.position = root.get_final_transform() * delete_button.get_global_rect().get_center(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	Input.parse_input_event(click); await process_frame
	click = click.duplicate(); click.pressed = false; Input.parse_input_event(click); await process_frame
	check(menu.modal_kind == "delete_slot" and app.campaign_map == null, "delete click opens confirmation without entering campaign")
	await _capture("menu_delete_" + suffix)
	menu.close_modal()
	check(app.slots.status(1) == "used", "cancel deletion retains slot")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._input(cancel)
	check(not menu.overlay.visible, "Escape closes modal")
	menu.options_button.pressed.emit()
	check(menu.modal_kind == "options", "options opens")
	menu.music_slider.value = 0.36
	menu.sfx_slider.value = 0.58
	check(is_equal_approx(app.settings.music_volume, 0.36), "slider applies music volume")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.36), "music bus changes")
	await _capture("menu_options_" + suffix)
	menu.close_modal()
	menu.credits_button.pressed.emit()
	check(menu.modal_kind == "message", "credits opens placeholder")
	menu.close_modal()
	menu.show_quit()
	check(menu.modal_kind == "quit", "desktop quit confirmation")
	menu.close_modal()
	if not menu.slots_open: menu.toggle_slots()
	menu._confirm_delete(1)
	for button: TextureButton in menu.overlay.find_children("*", "TextureButton", true, false):
		if button.get_child_count() > 0 and button.get_child(0) is Label and button.get_child(0).text == "删除":
			button.pressed.emit(); break
	check(app.slots.status(1) == "empty" and not menu.overlay.visible, "confirmed deletion removes slot and closes modal")
	app.audio.unlock()
	app.audio.unlock()
	check(app.audio.music_player.playing, "music running without duplicate player")
	var audio: Node = app.audio
	audio.music_player.stop()
	audio.click_player.stop()
	var settings_file: String = app.settings_path
	app.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(settings_file)
	print("MENU_VISUAL_SMOKE: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " ", suffix)
	quit(0 if failures.is_empty() else 1)


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory + "/" + filename + ".png")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
