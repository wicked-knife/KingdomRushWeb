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
	root.add_child(app)
	await app.menu_ready
	var menu: Control = app.menu
	await create_timer(0.8).timeout
	var suffix := "%dx%d" % [root.size.x, root.size.y]
	await _capture("menu_" + suffix)
	menu.start_button.pressed.emit()
	check(app.battle != null and not menu.visible, "start opens first campaign")
	app._return_to_menu()
	await process_frame
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
