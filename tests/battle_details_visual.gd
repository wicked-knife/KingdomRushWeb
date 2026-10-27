extends SceneTree
const App = preload("res://scenes/app_root.tscn")
var battle: Control
var failures: Array[String] = []
var audit: Array = []
var suffix: String

func _init() -> void: call_deferred("_run")
func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)

func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point * battle.zoom; event.button_index = button; event.pressed = true
	battle._gui_input(event)

func capture(id: String) -> void:
	battle.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	for entry: Dictionary in battle.interface.paint.audit:
		if str(entry.id).begins_with("unit:"):
			check(entry.fits and entry.font_size >= 8, id + ": legible unit field " + entry.id)
			check(entry.box.position.x >= 0 and entry.box.end.x <= battle.view_width and entry.box.position.y >= 0 and entry.box.end.y <= 770, id + ": unit field within screen")
	root.get_texture().get_image().save_png("res://reports/details_%s_%s.png" % [id, suffix])
	audit.append({"state": id, "tick": battle.sim.tick, "unit_info": battle.unit_info()})

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(1))
	var app = App.instantiate(); app.settings_path = "user://details_visual.json"; app.slots_path = "user://details_visual_" + str(Time.get_ticks_usec()) + ".progress"; root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	app.campaign_map._action("level", {"id": 1}); app.campaign_map._action("battle")
	battle = app.battle; battle.set_process(false)
	battle.mouse_filter = Control.MOUSE_FILTER_IGNORE; battle.set_process_input(false)
	suffix = "%dx%d" % [root.size.x, root.size.y]
	while not battle.sim.notices.is_empty(): battle._action("confirm")
	for entry: Dictionary in [{"id": "4", "type": "barrack"}, {"id": "1", "type": "archer"}, {"id": "8", "type": "engineer"}]: check(battle.sim.command("build", entry), "legal fixture build")
	for at in [24, 26, 29, 44, 46, 49, 100]:
		while battle.sim.tick < at: battle.sim.step()
		await capture("door_%03d" % at)
	check(battle.sim.tower_by_id("4").door_state == "closed", "door stays closed")
	var soldier: Dictionary = battle.sim.soldiers[0]
	click(battle.world(soldier.pos + Vector2(0, 9)))
	check(battle.selected_unit == soldier.id and battle.selected == "", "soldier selected via source hit rect")
	await capture("soldier_info")
	battle.sim.damage(soldier, 19, 4)
	await capture("soldier_wounded")
	check(battle.unit_info().hp == 31, "live health in info panel")
	var panel: Dictionary = battle.hits.filter(func(h): return h.action == "unit_info")[0]
	click(panel.rect.get_center())
	check(battle.selected_unit == soldier.id, "info panel consumes click")
	click(Vector2.ZERO, MOUSE_BUTTON_RIGHT)
	check(battle.selected_unit == 0, "right-click clears unit selection")
	check(battle.sim.command("rally", {"id": "4", "pos": Vector2(435, 228)}), "legal rally")
	await capture("rally_start")
	for i in range(10): battle.sim.step()
	await capture("rally_mid")
	for i in range(35): battle.sim.step()
	await capture("rally_end")
	var enemy: Dictionary = battle.sim._spawn_enemy("enemy_fat_orc", 0)
	enemy.node = 130; enemy.pos = battle.Simulation.vec(battle.sim.data.paths.paths[0][0][130])
	click(battle.world(enemy.pos + Vector2(0, 12)))
	check(battle.selected_unit == enemy.id and battle.unit_info().name == "兽人", "enemy selected via source hit rect")
	await capture("enemy_info")
	battle.sim.damage(enemy, 999, 1); battle._process(0)
	check(battle.selected_unit == 0, "selection clears on death")
	# Source path position in range of the archer and artillery; actual tower state
	# machines launch the bullets. No direct projectile insertion in this replay.
	enemy = battle.sim._spawn_enemy("enemy_fat_orc", 0)
	enemy.node = 60; enemy.pos = battle.Simulation.vec(battle.sim.data.paths.paths[0][0][60])
	var waited := 0
	while not battle.sim.projectiles.any(func(p): return p.template == "bomb") and waited < 180:
		battle.sim.step(); waited += 1
	check(waited < 180, "artillery launches from actual attack")
	for i in range(27):
		await capture("flight_%02d" % i)
		for j in range(2): battle.sim.step()
	check(battle.draw_list.all(func(item): return not battle._frame(item.frame).is_empty()), "every sampled world frame resolves")
	battle.sim.notices.append("POWER_REINFORCEMENT"); battle._action("confirm")
	check(battle.sim.command("cast", {"power": "reinforcements", "pos": Vector2(765, 270)}), "reinforcement unlocked through source notice")
	var farmer: Dictionary = battle.sim.soldiers.filter(func(s): return s.template == "re_farmer")[0]
	click(battle.world(farmer.pos + Vector2(0, 9)))
	check(battle.selected_unit == farmer.id and battle.unit_info().portrait == farmer.portrait, "reinforcement variant portrait and live stats")
	await capture("reinforcement_info")
	click(Vector2.ZERO, MOUSE_BUTTON_RIGHT)
	var sheep: Dictionary = battle.sim.decals.filter(func(d): return d.template.begins_with("decal_sheep"))[0]
	for i in range(7): click(battle.world(sheep.pos + Vector2(0, 5)))
	check(not sheep.removed and sheep.clicks == 7, "sheep seven real clicks")
	await capture("sheep_seven")
	click(battle.world(sheep.pos + Vector2(0, 5)))
	check(sheep.removed, "sheep eighth real click")
	for i in range(3): battle.sim.step()
	await capture("sheep_exploded")
	battle._action("restart")
	check(battle.selected_unit == 0 and battle.sim.decals.all(func(d): return not d.removed), "restart restores selection and sheep")
	var file := FileAccess.open("res://reports/battle_details_visual_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "states": audit}, "\t")); file.close()
	print("DETAILS_NATIVE: ", suffix, " states=", audit.size(), " failures=", JSON.stringify(failures))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
