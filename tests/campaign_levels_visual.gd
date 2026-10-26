extends SceneTree
const App = preload("res://scenes/app_root.tscn")
const Replay = preload("res://tests/campaign_playback.gd")
var app: Control
var battle: Control
var failures: Array[String] = []
var captures: Array[String] = []
var suffix := ""

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func capture(label: String) -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	await create_timer(0.46).timeout
	battle.interface.wave_flags.advance(0.46)
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	var filename := "campaign_%d_%s_%s.png" % [int(battle.sim.data.level.id), label, suffix]
	root.get_texture().get_image().save_png("res://reports/" + filename); captures.append(filename)
	for item: Dictionary in battle.interface.paint.audit:
		check(item.fits, label + ": text fits " + item.id)
	for hit: Dictionary in battle.hits:
		check(Rect2(0, 0, battle.view_width, 768).grow(1).encloses(hit.rect), label + ": hit stays in viewport")

func issue(kind: String, args: Dictionary = {}) -> void:
	battle._action(kind, args)

func pointer_action(kind: String, args: Dictionary = {}) -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	await create_timer(0.2).timeout
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	for hit: Dictionary in battle.hits:
		if hit.action == kind and hit.args == args and hit.enabled:
			var event := InputEventMouseButton.new(); event.pressed = true; event.button_index = MOUSE_BUTTON_LEFT; event.position = hit.rect.get_center() * battle.zoom
			battle._gui_input(event); return
	check(false, "missing actionable UI " + kind)

func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Native campaign check exceeded 240 seconds"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	app = App.instantiate(); app.settings_path = "user://campaign_visual_settings.json"; app.progress_path = "user://campaign_visual_%d.progress" % Time.get_ticks_usec(); root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	app.campaign.record_result({"generation":1,"level_id":1,"mode":1,"difficulty":2,"result":"victory","lives":20})
	for id in [2, 3]:
		app.campaign_map._action("level", {"id":id}); app.campaign_map._action("battle")
		battle = app.battle
		check(battle != null and battle.sim.data.level.id == id and app.campaign_map == null, "map routes actual level %d" % id)
		battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle.sim.reset(42)
		await capture("opening")
		var prep: Dictionary = battle.catalog.get_sound(battle.sim.data.level.prep_music)
		check(battle.audio.music_player.playing and battle.audio.music_player.stream.resource_path == prep.paths[0], "native level preparation music")
		if not battle.sim.notices.is_empty(): await pointer_action("confirm")
		await capture("map")
		battle.selected = "1"
		await capture("build_menu")
		await pointer_action("build", {"id":"1","type":"archer"})
		check(battle.sim.gold < int(battle.sim.data.waves.cash), "native click builds")
		check(battle.fx_players.any(func(player): return player.playing and player.stream != null), "native build sound playback")
		for i in range(25): battle.sim.step()
		battle.selected = "1"; await capture("upgrade_menu")
		await pointer_action("upgrade", {"id":"1","upgrade_to":"tower_archer_2"})
		check(battle.sim.tower_by_id("1").template == "tower_archer_2", "native click upgrades")
		await capture("upgraded")
		# Reset to the exact legal seed before the shared command replay.
		battle.sim.reset(42); Replay.dismiss(battle.sim, issue)
		var photographed := {}
		for i in range(60000):
			if battle.tip != "" and not photographed.has(battle.tip):
				photographed[battle.tip] = true; battle._action("tip"); await capture("tip_" + str(battle.sim.notices[0])); await pointer_action("confirm")
			if not battle.sim.alerts.is_empty():
				var alert: String = battle.sim.alerts[0]
				battle._action("enemy_notice", {"id":alert}); await capture(alert); await pointer_action("confirm")
			if id == 3 and not photographed.has("heal"):
				for enemy: Dictionary in battle.sim.enemies:
					if enemy.hp > 0 and enemy.state == "heal": photographed.heal = true; battle.selected_unit = enemy.id; await capture("shaman_heal"); battle.selected_unit = 0; break
			if id == 3 and not photographed.has("healed") and battle.sim.effects.any(func(e): return e.has("target")):
				photographed.healed = true; await capture("healing_effect")
			if i == 1800:
				await capture("combat")
				var music: Dictionary = battle.catalog.get_sound(battle.sim.data.level.music)
				check(battle.audio.music_player.playing and battle.audio.music_player.stream.resource_path == music.paths[0], "native actual level battle music")
			if i % 5 == 0: Replay.commands(battle.sim, issue)
			battle.sim.step()
			if battle.sim.result != "": break
		check(battle.sim.result == "victory" and battle.outcome.level_id == id and not battle.sim.developer_used, "native legal campaign victory %d" % id)
		await capture("victory")
		check(app.campaign.record(id).get("stars", 0) > 0, "actual level result saved")
		for repeat in range(3):
			battle._action("restart")
			check(battle.sim.gold == int(battle.sim.data.waves.cash) and battle.sim.speed == 1 and battle.sim.enemies.is_empty() and battle.sim.effects.is_empty() and battle.get_child_count() == 12, "native clean restart")
			Replay.dismiss(battle.sim, issue)
		battle._action("speed"); check(battle.sim.speed == 2, "native speed control")
		battle._action("pause"); var tick: int = battle.sim.tick
		battle.sim.advance(1); check(battle.sim.tick == tick, "native pause freezes")
		await capture("pause")
		battle._action("restart"); Replay.dismiss(battle.sim, issue); battle._action("wave")
		for i in range(12000):
			Replay.dismiss(battle.sim, issue); battle.sim.step()
			if battle.sim.result != "": break
		check(battle.sim.result == "defeat", "native empty defense defeat")
		await capture("defeat")
		battle._action("map"); await app.map_ready
		check(app.battle == null and app.campaign_map != null, "native return releases battle")
	check(app.campaign.is_playable(4), "level four naturally available")
	# Repeated cross-level entry releases the previous catalogs and audio players.
	for i in range(6):
		app._start_level(2 + i % 2, 1, 2); var old: WeakRef = weakref(app.battle)
		app.battle._action("map")
		check(app.audio.music_player.stream == null, "battle music released while map loads")
		await app.map_ready; await process_frame
		check(old.get_ref() == null, "cross-level scene freed")
	var file := FileAccess.open("res://reports/campaign_levels_visual_" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"captures":captures}, "\t")); file.close()
	app.queue_free(); await process_frame; await process_frame
	print("CAMPAIGN_NATIVE: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " ", suffix)
	quit(0 if failures.is_empty() else 1)
