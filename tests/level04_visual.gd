extends "res://tests/tower_upgrade_visual.gd"
const ThirdScene = preload("res://tests/tier3_upgrade_arena.tscn")
const AppScene = preload("res://scenes/app_root.tscn")
const Replay = preload("res://tests/campaign_playback.gd")
var app: Control

func capture(label: String) -> void:
	# Notices animate from zero opacity on their first draw. Capture settled UI.
	await draw_frame(); await create_timer(0.35).timeout
	await super.capture(label)

func menu(id: String = "03") -> void:
	await draw_frame(); await click(battle.world(battle.sim.tower_by_id(id).pos))
	await create_timer(0.15).timeout; await draw_frame()
	check(battle.selected == id, "native selection " + id)

func crop(point: Vector2 = Vector2.INF) -> Image:
	var picture := root.get_texture().get_image()
	var scale_value := picture.get_height() / 768.0
	var center: Vector2 = battle.world(battle.sim.tower_by_id("03").pos if point == Vector2.INF else point) * scale_value
	return picture.get_region(Rect2i(Vector2i(center - Vector2(75, 115) * scale_value), Vector2i(Vector2(150, 155) * scale_value)))

func third_family(kind: String, price: int, total: int) -> void:
	battle._action("restart"); await dismiss()
	await menu(); await action("build", {"id":"03", "type":kind})
	for i in range(25): battle.sim.step()
	await menu(); await action("upgrade")
	await menu()
	var entry := hit("upgrade")
	check(not entry.is_empty() and entry.args.upgrade_to == "tower_" + kind + "_3", "third tier menu " + kind)
	if entry.is_empty(): return
	await hover(entry.rect.get_center())
	var item: Dictionary = battle.sim.data.ui.upgrade_menus[entry.args.upgrade_to]
	expect_text(battle.sim.data.ui.strings[item.tt_title]); expect_text(str(price))
	await capture("tier3_" + kind + "_menu")
	battle.sim.gold = price - 1; await draw_frame()
	check(not hit("upgrade").enabled, "third upgrade disabled when short")
	await click(hit("upgrade").rect.get_center())
	check(battle.sim.gold == price - 1 and int(battle.sim.tower_template(battle.sim.tower_by_id("03")).tower.level) == 2, "disabled upgrade no effect")
	battle.sim.gold = price; await action("upgrade")
	check(battle.sim.gold == 0 and battle.sim.tower_by_id("03").template == "tower_" + kind + "_3" and battle.selected == "", "native third upgrade commits " + kind)
	check(battle.fx_players.any(func(p): return p.playing and p.stream != null), "upgrade sound played " + kind)
	for i in range(100): battle.sim.step()
	await menu(); check(hit("upgrade").is_empty(), "third tier is final")
	await hover(hit("sell").rect.get_center()); expect_text("返还 %d 金币" % total)
	await capture("tier3_" + kind + "_ready")
	if not OS.get_cmdline_user_args().has("--layout-only"): await sample_actions(kind)
	battle.selected = ""; await action("wave"); await menu()
	await hover(hit("sell").rect.get_center()); expect_text("返还 %d 金币" % roundi(total * 0.6))
	var gold: int = battle.sim.gold
	await action("sell"); check(battle.sim.gold == gold + roundi(total * 0.6), "native third refund " + kind)

func sample_actions(kind: String) -> void:
	battle.selected = ""; battle.hovered = ""; battle.sim.enemies.clear()
	var tower: Dictionary = battle.sim.tower_by_id("03")
	if kind == "barrack":
		check(battle.sim.soldiers.size() == 3, "native knight garrison")
		var knight: Dictionary = battle.sim.soldiers[0]
		battle.selected_unit = knight.id; await capture("tier3_knight_info"); battle.selected_unit = 0
		for state in ["idle", "running", "attack", "death"]:
			var frames: Array = []
			var sprite: Dictionary = battle.sim.templates.soldier_knight.render.sprites[0]
			var duration := Anim.duration(battle.animations, Anim.key(sprite, state))
			var at: int = battle.sim.tick
			knight.state = state; knight.state_at = at
			for i in range(duration): battle.sim.tick = at + i; await draw_frame(); frames.append(crop(knight.pos))
			contact_sheet(frames, "tier3_knight_" + state, 8)
		return
	for up in [false, true]:
		var enemy: Dictionary = battle.sim._spawn_enemy("enemy_brigand", 0)
		enemy.pos = tower.pos + Vector2(50, 110 if up else -35); enemy.hp = 10000; enemy.max_hp = 10000
		tower.attack_at = battle.sim.tick; tower.pending = {}
		battle.sim._tower_step(tower)
		var at: int = battle.sim.tick
		var frames: Array = []
		for i in range(36):
			battle.sim.tick = at + i
			if i == (5 if kind == "archer" else (8 if kind == "mage" else 12)): battle.sim._tower_step(tower)
			await draw_frame(); frames.append(crop())
		contact_sheet(frames, "tier3_" + kind + ("_up" if up else "_down"), 9)
		battle.sim.enemies.clear(); battle.sim.projectiles.clear()

func drive(kind: String, args: Dictionary = {}) -> void:
	# The full campaign uses the native command handler; third_family separately
	# exercises build/upgrade/refund through real engine mouse input.
	battle._action(kind, args)

func campaign() -> void:
	arena.queue_free(); await process_frame; await process_frame
	app = AppScene.instantiate(); app.settings_path = "user://level04_visual_settings.json"; app.progress_path = "user://level04_visual_%d.progress" % Time.get_ticks_usec(); root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in [1, 2, 3]: app.campaign.record_result({"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	check(app.campaign.is_playable(4), "existing three-stage save gains fourth campaign")
	app.campaign_map._action("level", {"id":4}); app.campaign_map._action("battle")
	battle = app.battle; battle.set_process(false)
	battle.sim.reset(42)
	check(battle != null and battle.sim.data.level.id == 4 and battle.sim.notices == ["TOWER_LEVEL3"], "map enters fourth campaign with third tier notice")
	var prep: Dictionary = battle.catalog.get_sound(battle.sim.data.level.prep_music)
	check(battle.audio.music_player.playing and battle.audio.music_player.stream.resource_path == prep.paths[0], "native fourth preparation music")
	await capture("level04_opening"); expect_text("三级防御塔"); await dismiss()
	for path in [1, 2]:
		battle.selected = ""; await draw_frame()
		var entry := hit("wave", {"path":path})
		check(not entry.is_empty(), "native separate entrance " + str(path))
		await hover(entry.rect.get_center())
		check(int(battle.interface.wave_flags.hovered_flag().path) == path, "route hover selects correct path")
		await capture("level04_route_" + str(path))
	for i in range(60000):
		if i % 5 == 0: Replay.commands(battle.sim, drive)
		if not battle.sim.alerts.is_empty():
			var enemy: String = battle.sim.alerts[0]
			battle._action("enemy_notice", {"id":enemy}); await capture("level04_" + enemy); await dismiss()
		if i in [1800, 6000, 12000]: await capture("level04_combat_" + str(i))
		battle.sim.step()
		if battle.sim.result != "": break
	check(battle.sim.result == "victory" and battle.sim.spawn_log.size() == 339 and not battle.sim.developer_used, "native legal fourth campaign victory")
	check(app.campaign.record(4).get("stars", 0) > 0 and app.campaign.is_unlocked(5) and not app.campaign.is_playable(5), "fourth result saved, fifth preview")
	await capture("level04_victory")
	for i in range(3):
		battle._action("restart"); check(battle.sim.gold == 520 and battle.sim.lives == 20 and battle.sim.enemies.is_empty(), "native fourth restart"); await dismiss()
	battle._action("speed"); check(battle.sim.speed == 2, "native fourth speed")
	battle._action("pause"); var before: int = battle.sim.tick; battle.sim.advance(1); check(battle.sim.tick == before, "native fourth pause")
	await capture("level04_pause")
	battle._action("restart"); await dismiss(); battle._action("wave")
	for i in range(12000):
		Replay.dismiss(battle.sim); battle.sim.step()
		if battle.sim.result != "": break
	check(battle.sim.result == "defeat", "native fourth empty defense")
	await capture("level04_defeat")
	var old: WeakRef = weakref(battle); battle._action("map"); await app.map_ready; await process_frame
	check(old.get_ref() == null and app.battle == null and app.campaign.is_playable(4), "native return frees fourth stage")
	app.queue_free(); await process_frame

func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Level four native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	arena = ThirdScene.instantiate(); root.add_child(arena)
	while arena.battle == null: await process_frame
	battle = arena.battle; battle.set_process(false); await draw_frame()
	if OS.get_cmdline_user_args().has("--layout-only"):
		battle.sim.notices.append("TOWER_LEVEL3")
		await capture("tier3_notification"); expect_text("三级防御塔"); await dismiss()
		for enemy: String in ["enemy_bandit", "enemy_brigand"]:
			battle.sim._spawn_enemy(enemy, 0)
			battle._action("enemy_notice", {"id":enemy})
			await capture("tier3_" + enemy + "_notice"); await dismiss()
	for kind in ["archer", "barrack", "mage", "engineer"]: await third_family(kind, {"archer":160,"barrack":150,"mage":240,"engineer":320}[kind], {"archer":340,"barrack":330,"mage":500,"engineer":665}[kind])
	if not OS.get_cmdline_user_args().has("--layout-only") and not OS.get_cmdline_user_args().has("--towers-only"): await campaign()
	else: arena.queue_free(); await process_frame
	var file := FileAccess.open("res://reports/level04_visual_" + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"sampled_frames":sampled_frames}, "\t")); file.close()
	print("LEVEL04_NATIVE: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " ", suffix, " checks ", checks)
	quit(0 if failures.is_empty() else 1)
