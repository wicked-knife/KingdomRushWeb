extends SceneTree
const App = preload("res://scenes/app_root.tscn")
var app: Control
var battle: Control
var failures: Array[String] = []
var captures: Array[String] = []
var suffix := ""

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func render(canvas: Control) -> void:
	canvas.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw

func capture(canvas: Control, label: String) -> void:
	await render(canvas)
	var path := "interaction_" + label + "_" + suffix + ".png"
	root.get_texture().get_image().save_png("res://reports/" + path); captures.append(path)
	for hit: Dictionary in canvas.hits:
		check(Rect2(Vector2.ZERO, canvas.size / canvas.zoom).grow(1).encloses(hit.rect), "hit fits screen " + hit.action)
	for item: Dictionary in canvas.paint.audit if canvas == app.campaign_map else canvas.interface.paint.audit:
		check(item.fits, "text fits " + item.id)

func move(canvas: Control, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point * canvas.zoom
	event.global_position = event.position
	# Keep physical desktop motion out of scripted hover captures. Wave clicks
	# below separately exercise the complete viewport input pipeline.
	canvas._gui_input(event)
	await render(canvas)

func click_wave(path: int) -> void:
	await render(battle)
	for hit: Dictionary in battle.hits:
		if hit.action == "wave" and int(hit.args.path) == path and hit.enabled:
			var point: Vector2 = root.get_screen_transform() * battle.get_global_transform_with_canvas() * (hit.rect.get_center() * battle.zoom)
			battle.mouse_filter = Control.MOUSE_FILTER_STOP
			for pressed in [true, false]:
				var event := InputEventMouseButton.new(); event.pressed = pressed; event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point
				Input.parse_input_event(event); await process_frame
			battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return
	check(false, "active entrance has clickable icon")

func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Interaction visual timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	app = App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://interaction_visual_settings_" + token + ".json"; app.progress_path = "user://interaction_visual_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in [1, 2, 3]: app.campaign.record_result({"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	var map: Control = app.campaign_map
	map.set_process(false); map.set_process_input(false); map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await capture(map, "map_normal")
	var hit: Dictionary = map.hits.filter(func(entry): return entry.action == "level" and int(entry.args.id) == 1)[0]
	await move(map, hit.rect.get_center())
	check(map.flag_states[1].hovered and map.flag_states[1].frame() == "map_flag_0181", "pointer entering completed flag highlights")
	await capture(map, "map_hover")
	await move(map, hit.rect.end + Vector2(20, 20))
	check(not map.flag_states[1].hovered and map.flag_states[1].frame() == "map_flag_0090", "pointer exit restarts flag wave")
	map.flag_states[1].advance(1.6)
	await capture(map, "map_after_exit")
	check(map.flag_states[1].frame() == "map_flag_0134", "glow absent after exit")
	map.set_map_zoom(2, hit.rect.get_center()); await render(map)
	hit = map.hits.filter(func(entry): return entry.action == "level" and int(entry.args.id) == 1)[0]
	await move(map, hit.rect.get_center()); map.pan(Vector2(-250, -100)); await render(map); await render(map)
	check(not map.flag_states[1].hovered, "panning flag away from stationary pointer clears hover")
	map._action("level", {"id":1}); map.close_overlay(); await render(map)
	check(map.hovered == "", "closing modal clears previous flag hover")
	for id in [1, 2, 3]:
		app._start_level(id, 1, 2); battle = app.battle
		battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle.sim.notices.clear()
		await capture(battle, "level%d_first_icon" % id)
		if id == 1:
			battle.sim.command("build", {"id":"1", "type":"archer"})
			await capture(battle, "level1_start_hint")
		var flags: RefCounted = battle.interface.wave_flags
		var flag: Dictionary = flags.active[0]
		await move(battle, flags.position(flag)); flags.advance(0.3)
		await capture(battle, "level%d_incoming" % id)
		check(not flags.hovered_flag().is_empty(), "entrance pointer hover activates tooltip level %d (hover=%s pointer=%s)" % [id, battle.hovered, battle.pointer])
		var before: int = battle.sim.wave
		await click_wave(int(flag.path)); flags.sync()
		check(battle.sim.wave == before + 1 and flags.active.is_empty(), "native entrance click sends first wave")
		await capture(battle, "level%d_icon_fade" % id)
		battle.sim.notices.clear(); flags.advance(0.51); flags.sync()
		battle.sim.spawn_queue.clear(); battle.sim.enemies.clear(); battle.sim.alerts.clear()
		battle.sim.next_wave_tick = battle.sim.tick + int(battle.sim.data.waves.groups[1].interval)
		flags.sync()
		await move(battle, Vector2(500, 700)); flags.advance(0.3)
		var interval: int = battle.sim.data.waves.groups[1].interval
		for phase in [0.25, 0.5, 0.75]:
			battle.sim.tick = battle.sim.next_wave_tick - roundi(interval * (1 - phase))
			await capture(battle, "level%d_timer%d" % [id, roundi(phase * 100)])
		battle.selected = "1"; await capture(battle, "level%d_selection_dims_icon" % id)
		check(not flags.enabled() and battle.hits.all(func(entry): return entry.action != "wave"), "tower selection removes wave click regions")
		battle.selected = ""
		if id == 3:
			battle.sim.wave = 3; battle.sim.next_wave_tick = battle.sim.tick + int(battle.sim.data.waves.groups[3].interval)
			flags.sync(); await capture(battle, "dual_entrances")
			check(flags.active.size() == 2, "dual-path group renders two active icons")
			for entry: Dictionary in flags.active:
				await move(battle, flags.position(entry)); flags.advance(0.3)
				await capture(battle, "dual_incoming_path%d" % int(entry.path))
				check(flags.hovered_flag().path == entry.path, "each entrance exposes its own report")
			await click_wave(2); flags.sync()
			check(battle.sim.wave == 4 and flags.active.is_empty(), "either entrance starts both paths once")
			await _soldier_visual()
		battle._action("map"); await app.map_ready
	var file := FileAccess.open("res://reports/interaction_fixes_visual_" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"captures":captures}, "\t")); file.close()
	app.queue_free(); await process_frame; await process_frame
	print("INTERACTION_NATIVE: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " ", suffix); quit(0 if failures.is_empty() else 1)

func _soldier_visual() -> void:
	battle.sim.reset(42); battle.sim.notices.clear(); battle.interface.reset(); battle.pointer = Vector2(-1000, -1000); battle.hovered = ""
	for i in range(2):
		var center := Vector2(532 + i * 170, 439)
		var e: Dictionary = battle.sim._spawn_enemy("enemy_ogre" if i == 1 else "enemy_fat_orc", 0)
		e.pos = center; e.last_dir = Vector2(-1, 0)
		for rank in range(3):
			var s: Dictionary = battle.sim._soldier("soldier_footmen" if i == 0 else "re_farmer", "", rank, center + Vector2(-90, -40), center)
			s.rallying = false; s.attack_at = 10000; s.target = e.id; e.blockers.append(s.id)
		e.blocker = e.blockers[0]
	for step in range(110):
		battle.sim.tick += 1
		for s: Dictionary in battle.sim.soldiers:
			var from: Vector2 = s.pos; battle.sim._soldier_step(s)
			check(s.state != "running" or s.pos != from, "running frame requires movement")
		if step == 5: await capture(battle, "soldiers_approaching")
	await capture(battle, "soldiers_arrived_cooldown")
	check(battle.sim.soldiers.all(func(s): return s.state == "idle"), "soldiers stop walking at melee slot during cooldown")
	for enemy: Dictionary in battle.sim.enemies: battle.sim.damage(enemy, 99999, 1)
	for step in range(110):
		battle.sim.tick += 1
		for s: Dictionary in battle.sim.soldiers:
			var from: Vector2 = s.pos; battle.sim._soldier_step(s)
			check(s.state != "running" or s.pos != from, "post-kill running frame requires movement")
	await capture(battle, "soldiers_returned_idle")
