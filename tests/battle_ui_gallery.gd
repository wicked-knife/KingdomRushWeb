extends SceneTree
const App = preload("res://scenes/app_root.tscn")
var app: Control
var battle: Control
var failures: Array = []
var audit: Dictionary = {}
var suffix := ""
func _init() -> void: call_deferred("_run")
func capture(id: String, wait: float = 0.46) -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	await create_timer(wait).timeout
	if id == "build_hover": battle.hovered = "build" + str({"id": "1", "type": "mage"})
	battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/ui_" + id + "_" + suffix + ".png")
	var records: Array = []
	for item: Dictionary in battle.interface.paint.audit:
		if not item.fits: failures.append(id + ":" + item.id)
		records.append({"id": item.id, "font_size": item.font_size, "font_role": item.font_role, "font_family": item.font_family, "box": str(item.box), "extent": str(item.extent), "lines": item.lines, "fits": item.fits})
	for hit: Dictionary in battle.hits:
		if not Rect2(0, 0, battle.view_width, 768).grow(1).encloses(hit.rect): failures.append(id + ":offscreen:" + hit.action)
	audit[id] = records
func check(value: bool, id: String) -> void:
	if not value: failures.append(id); push_error(id)
func progress() -> float:
	for item: Dictionary in battle.draw_list:
		if item.frame == "buildbar": return item.scale.x
	return -1
func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	app = App.instantiate(); app.settings_path = "user://ui_gallery.json"; app.progress_path = "user://ui_gallery_" + str(Time.get_ticks_usec()) + ".progress"; root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	app.campaign_map._action("level", {"id": 1}); app.campaign_map._action("battle")
	battle = app.battle; battle.set_process(false)
	# Gallery states are scripted; desktop pointer events must not dismiss a state
	# while a screenshot is being collected. Gameplay input has its own replay.
	battle.mouse_filter = Control.MOUSE_FILTER_IGNORE; battle.set_process_input(false)
	suffix = "%dx%d" % [root.size.x, root.size.y]
	for i in range(3):
		await capture("tutorial%d" % (i + 1)); battle._action("confirm")
	await capture("hud")
	battle.developer.toggle(); await capture("developer_prebattle"); battle.developer.close()
	battle.sim.gold = 99999; battle.sim.lives = 999
	await capture("hud_large_values")
	battle.sim.gold = 10000270; battle.sim.lives = 1120
	await capture("hud_extreme_values")
	battle.sim.gold = 270; battle.sim.lives = 20
	battle.selected = "1"; await capture("build_menu")
	battle.hovered = "build" + str({"id": "1", "type": "mage"}); await capture("build_hover")
	battle.sim.gold = 50; await capture("build_disabled")
	battle.sim.gold = 270; battle.hovered = ""
	battle._action("build", {"id": "1", "type": "archer"})
	await capture("construction0", 0.15)
	check(is_equal_approx(progress(), 0), "construction starts empty")
	for i in range(12): battle.sim.step()
	await capture("construction12", 0.05)
	check(is_equal_approx(progress(), 0.5), "construction halfway at 0.4s")
	for i in range(13): battle.sim.step()
	await capture("construction25", 0.15)
	check(progress() < 0, "construction removed on completion")
	battle.selected = "1"; await capture("tower_menu")
	battle.selected = ""
	for id in ["TIP_ARMOR", "TIP_RALLY", "POWER_REINFORCEMENT", "POWER_FIREBALL"]:
		battle.sim.notices.append(id); await capture(id.to_lower()); battle._action("confirm")
	battle._action("wave")
	battle.developer.toggle(); battle._action("dev_add_gold"); battle._action("dev_add_lives")
	await capture("developer_active"); battle.developer.close()
	await capture("debug_hud")
	await capture("powers_unlocked", 0.7)
	battle._action("target", {"power": "fire"})
	await capture("road_hint")
	battle.targeting = ""
	battle.sim.cooldowns.fire = 1200; battle.sim.cooldowns.reinforcements = 150
	await capture("powers_cooldown")
	battle._action("pause"); await capture("pause")
	var old_music: float = app.settings.music_volume
	var old_sfx: float = app.settings.sfx_volume
	for hit: Dictionary in battle.hits:
		if hit.action == "volume" and hit.args.bus == "music":
			battle._set_volume(hit.args, hit.args.track.position.x + hit.args.track.size.x * 0.25)
			check(is_equal_approx(app.settings.music_volume, 0.25), "pause music slider updates shared settings")
			check(is_equal_approx(app.settings.sfx_volume, old_sfx), "music slider preserves sfx")
	app.settings.set_volumes(old_music, old_sfx)
	battle.sim.lives = 0; battle.sim._finish("defeat"); await capture("defeat")
	battle.outcome.clear(); battle.sim.result = ""; battle.sim.lives = 20; battle.sim.kills = 56; battle.sim._finish("victory"); await capture("victory", 2)
	var file := FileAccess.open("res://reports/ui_layout_" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "layouts": audit}, "\t")); file.close()
	var progress_file: String = app.progress_path
	app.queue_free(); await process_frame; await process_frame
	for ending in ["", ".bak", ".tmp"]: if FileAccess.file_exists(progress_file + ending): DirAccess.remove_absolute(progress_file + ending)
	print("BATTLE_UI_GALLERY: ", "PASS" if failures.is_empty() else str(failures), " ", suffix)
	quit(0 if failures.is_empty() else 1)
