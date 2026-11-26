extends SceneTree
## Native visual, layout, and audio verification for LoadingScreen across all contexts.

const AppScene = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("LOADING_VISUAL_FAIL: " + message)


func _wait_frames(count: int = 4) -> void:
	for _i in range(count):
		await process_frame


func _capture(name: String) -> void:
	await _wait_frames(5)
	var img := root.get_texture().get_image()
	check(img != null and img.get_width() > 0, "capture valid: " + name)
	if img != null:
		img.save_png("res://reports/loading_%s.png" % name)


func _check_within_viewport(ctrl: Control, label: String) -> void:
	if not ctrl.is_visible_in_tree():
		return
	var vp := root.get_visible_rect()
	var rect := ctrl.get_global_rect()
	check(rect.position.x >= -2.0 and rect.position.y >= -2.0 and rect.end.x <= vp.size.x + 2.0 and rect.end.y <= vp.size.y + 2.0,
		"%s stays inside viewport (%s vs %s)" % [label, str(rect), str(vp.size)])


func _run() -> void:
	create_timer(45.0).timeout.connect(func():
		push_error("Loading visual check timed out")
		quit(1)
	)
	var app := AppScene.instantiate()
	var stamp := str(Time.get_ticks_usec())
	app.settings_path = "user://loading_visual_settings_%s.json" % stamp
	app.slots_path = "user://loading_visual_slots_%s" % stamp
	root.add_child(app)

	await app.menu_ready
	check(app.loading != null and not app.loading.visible, "loading hides cleanly after boot")
	check(app.heading == app.loading.heading_label and app.description == app.loading.description_label, "legacy label references preserved")
	check(app.progress == app.loading.progress_bar and app.retry == app.loading.retry_button and app.back == app.loading.back_button, "legacy control references preserved")

	# Load map once so we can verify real level thumbnail extraction
	app._start_campaign(1)
	await app.map_ready
	check(app.campaign_map != null and app.map_loader != null, "campaign map loaded for thumbnail test")
	var level_info: Dictionary = app._level_loading_info(1, 2)
	check(level_info.get("title", "") == "南港", "level 1 Chinese title resolved")
	check(level_info.get("thumbnail_texture") is Texture2D, "level 1 thumbnail texture extracted from map catalog")
	check(level_info.get("frame_texture") is Texture2D, "thumbnail frame texture extracted from map catalog")

	# 1. Boot showcase @ 1280x720
	app.loading.show()
	app.loading.modulate.a = 1.0
	app.move_child(app.loading, app.get_child_count() - 1)
	app.loading.set_context("boot")
	app.loading.set_progress(45, 100, "加载首页画面…")
	app.loading._display_ratio = 0.45
	app.loading._logo_time = 2.0
	app.loading._elapsed = 1.2
	app.loading._spawn_dust()
	await _capture("01_boot_1280x720")
	_check_within_viewport(app.heading, "boot heading")
	_check_within_viewport(app.description, "boot description")

	# 2. Map transition showcase
	app.loading.set_context("map", {"returning": false})
	app.loading.set_progress(68, 100, "加载一代大地图…")
	app.loading._display_ratio = 0.68
	app.loading._elapsed = 2.0
	app.loading._spawn_dust()
	await _capture("02_map_1280x720")

	# 3. Level transition showcase with framed stage thumbnail & Heroic mode badge
	app.loading.set_context("level", level_info)
	app.loading.set_progress(58, 100, "下载游戏资源… 5.8 / 10.0 MB")
	app.loading._display_ratio = 0.58
	app.loading._elapsed = 2.7
	app.loading._spawn_dust()
	await _capture("03_level_1280x720")
	_check_within_viewport(app.loading._thumb_holder, "level thumbnail")
	_check_within_viewport(app.heading, "level heading")

	# 4. Ending showcase
	app.loading.set_context("ending")
	app.loading.set_progress(82, 100, "正在展开终章画卷…")
	app.loading._display_ratio = 0.82
	app.loading._elapsed = 3.4
	await _capture("04_ending_1280x720")

	# 5. Error state with retry + back buttons and click audio check
	app.loading.show_error("资源下载失败（HTTP 503，错误 0），请检查网络后重试。", true)
	await _capture("05_error_1280x720")
	_check_within_viewport(app.retry, "error retry button")
	_check_within_viewport(app.back, "error back button")
	var desc_rect: Rect2 = app.description.get_global_rect()
	var retry_rect: Rect2 = app.retry.get_global_rect()
	check(desc_rect.end.y <= retry_rect.position.y + 2.0, "error description does not overlap retry button")
	app.loading.play_button_click()
	await _wait_frames(2)
	check(app.audio.click_player.stream != null, "button click SFX configured")

	# 6. Check 1024x768 aspect ratio fit
	DisplayServer.window_set_size(Vector2i(1024, 768))
	await _wait_frames(4)
	app.loading.set_context("level", level_info)
	app.loading.set_progress(62, 100, "下载游戏资源… 6.2 / 10.0 MB")
	app.loading._display_ratio = 0.62
	await _capture("06_level_1024x768")
	_check_within_viewport(app.loading._thumb_holder, "1024x768 thumbnail")
	_check_within_viewport(app.heading, "1024x768 heading")
	_check_within_viewport(app.description, "1024x768 description")

	# Verify transient thumbnail textures release on dismiss
	app.loading.dismiss_immediate()
	check(app.loading._thumb_image.texture == null and app.loading._thumb_frame.texture == null, "transient thumbnail textures released on dismiss")

	print("LOADING_VISUAL_RESULT: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " checks=", checks)
	quit(0 if failures.is_empty() else 1)
