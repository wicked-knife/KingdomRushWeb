extends SceneTree
const App = preload("res://scenes/app_root.tscn")
var failures: Array[String] = []
var app: Control
var battle: Control
var suffix: String

func _init() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var input := InputEventMouseButton.new()
	input.position = point * battle.zoom; input.button_index = button; input.pressed = true
	battle._gui_input(input)

func action(id: String, args: Dictionary = {}) -> void:
	battle.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	await create_timer(0.15).timeout
	battle.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	for hit in battle.hits:
		if hit.action == id and (hit.args == args or (id == "wave" and args.is_empty())):
			click(hit.rect.get_center()); return
	check(false, "missing UI action " + id + str(args))
	quit(1)

func capture(label: String) -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	await create_timer(0.45).timeout
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/level01_" + label + "_" + suffix + ".png")

func _run() -> void:
	create_timer(95).timeout.connect(func(): quit(1))
	app = App.instantiate(); app.settings_path = "user://battle_smoke.json"; app.progress_path = "user://battle_smoke_" + str(Time.get_ticks_usec()) + ".progress"; root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1)
	await app.map_ready
	app.campaign_map._action("level", {"id": 1}); app.campaign_map._action("battle")
	battle = app.battle; suffix = "%dx%d" % [root.size.x, root.size.y]
	check(battle != null and not app.menu.visible, "menu enters battle")
	var f8 := InputEventKey.new(); f8.keycode = KEY_F8; f8.pressed = true
	Input.parse_input_event(f8); await process_frame
	check(battle.developer.opened and battle.sim.paused, "F8 opens developer overlay over tutorial")
	await action("dev_add_gold"); await action("dev_add_lives")
	check(battle.sim.gold == 10270 and battle.sim.lives == 120, "native developer controls apply increments")
	var dev_escape := InputEventKey.new(); dev_escape.keycode = KEY_ESCAPE; dev_escape.pressed = true
	Input.parse_input_event(dev_escape); await process_frame
	check(not battle.developer.opened and not battle.sim.paused and battle.sim.notices.size() == 3, "Escape closes developer overlay without confirming tutorial")
	battle.sim.reset()
	await capture("tutorial")
	click(battle.world(battle.sim.tower_by_id("1").pos))
	check(battle.selected == "" and battle.sim.gold == 270, "tutorial blocks click-through")
	for i in range(3): await action("confirm")
	await capture("map")
	click(battle.world(battle.sim.tower_by_id("1").pos))
	await capture("build_menu")
	await action("build", {"id": "1", "type": "archer"})
	for entry in [{"id": "6", "type": "mage"}, {"id": "4", "type": "barrack"}]:
		await process_frame; await RenderingServer.frame_post_draw
		click(battle.world(battle.sim.tower_by_id(entry.id).pos))
		await action("build", entry)
	for i in range(80): battle.sim.step()
	await action("wave")
	for i in range(1200): battle.sim.step()
	await capture("combat")
	check(battle.sim.kills > 0, "tower kills in native window")
	check(battle.sim.soldiers.size() == 3, "barrack visible soldiers")
	click(battle.world(battle.sim.tower_by_id("4").pos))
	await action("target", {"power": "rally"})
	click(Vector2(0, 0), MOUSE_BUTTON_RIGHT)
	check(battle.targeting == "", "right-click cancels targeting")
	click(battle.world(battle.sim.tower_by_id("4").pos))
	await action("target", {"power": "rally"})
	click(battle.world(Vector2(478, 228)))
	check(battle.targeting == "", "rally click accepted")
	await action("speed")
	check(battle.sim.speed == 2, "2x HUD control")
	await action("speed")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	battle._input(escape)
	check(battle.sim.paused, "Esc pauses")
	battle._input(escape)
	check(not battle.sim.paused, "Esc resumes")
	await action("pause")
	var paused_tick: int = battle.sim.tick
	await create_timer(0.1).timeout
	check(battle.sim.tick == paused_tick, "native paused")
	await capture("pause")
	await action("restart")
	for i in range(3): await action("confirm")
	await action("wave")
	for i in range(6000):
		while not battle.sim.notices.is_empty(): battle.sim.command("confirm")
		battle.sim.step()
		if battle.sim.result != "": break
	await capture("defeat")
	check(battle.sim.result == "defeat", "native loss result")
	await action("map"); await app.map_ready
	check(app.battle == null and app.campaign_map != null, "result returns map")
	app.campaign_map._action("level", {"id": 1}); app.campaign_map._action("battle"); battle = app.battle
	await process_frame
	check(battle.sim.tick == 0 and battle.sim.gold == 270, "fresh battle on reentry")
	battle.set_process(false)
	for i in range(3): await action("confirm")
	for entry in [{"id": "1", "type": "archer"}, {"id": "6", "type": "mage"}, {"id": "4", "type": "archer"}]:
		await process_frame; await RenderingServer.frame_post_draw
		click(battle.world(battle.sim.tower_by_id(entry.id).pos))
		await action("build", entry)
	await action("wave")
	for i in range(30000):
		while not battle.sim.notices.is_empty():
			if battle.sim.notices[0] == "POWER_FIREBALL": await capture("fire_tutorial")
			await action("confirm")
		for id in ["8", "3", "7", "5", "2"]:
			if battle.sim.gold >= 70 and battle.sim.tower_by_id(id).type == "":
				await process_frame; await RenderingServer.frame_post_draw
				click(battle.world(battle.sim.tower_by_id(id).pos))
				await action("build", {"id": id, "type": "archer"})
		if battle.sim.unlocked.reinforcements and battle.sim.cooldowns.reinforcements == 0:
			var target: Dictionary = battle.sim._target(Vector2(478, 228), 120)
			if not target.is_empty() and battle.sim.valid_ground(target.pos):
				await action("target", {"power": "reinforcements"}); click(battle.world(target.pos))
		if battle.sim.unlocked.fire and battle.sim.cooldowns.fire == 0:
			var target: Dictionary = battle.sim._target(Vector2(400, 440), 400)
			if not target.is_empty() and battle.sim.valid_ground(target.pos):
				await action("target", {"power": "fire"}); click(battle.world(target.pos))
		battle.sim.step()
		if battle.sim.result != "": break
	check(battle.sim.result == "victory", "legal UI command campaign victory")
	await capture("victory")
	for i in range(3):
		await action("restart")
		check(battle.sim.towers.size() == 8 and battle.get_child_count() == 12 and battle.sim.speed == 1 and battle.sim.enemies.is_empty(), "three UI restarts do not retain entities/audio")
		for j in range(3): await action("confirm")
		await action("pause")
	await action("map"); await app.map_ready
	check(app.battle == null and app.campaign_map != null, "pause returns map")
	app._return_to_menu()
	await process_frame
	app.queue_free(); await process_frame; await process_frame
	print("BATTLE_VISUAL_SMOKE: ", "PASS" if failures.is_empty() else str(failures), " ", suffix)
	quit(0 if failures.is_empty() else 1)
