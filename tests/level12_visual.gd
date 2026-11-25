extends "res://tests/level09_visual.gd"
## Bounded native fixtures for Stage 12 (The Dark Tower): foregrounds, taunts, tower lock click/timeout,
## portals, soul drain, demon transform, souls death + white circle, hide_gui, challenges and settlement.

func enter(id: int, mode: int) -> void:
	app.campaign_map.camera_offset = Vector2.ZERO
	await map_action("level", {"id": id})
	await map_action("mode", {"mode": mode, "reason": "战役获得三星后开放挑战"})
	await map_capture("level%d_mode%d" % [id, mode])
	await map_action("battle")
	battle = app.battle
	check(battle != null and battle.sim.data.level.id == id and battle.sim.data.level.mode == mode, "native actual identity %d/%d" % [id, mode])
	battle.set_process(false)
	await dismiss()

func settle12(result: String = "victory") -> void:
	battle.sim._finish(result)
	battle.set_process(true)
	await create_timer(4.2).timeout
	battle.set_process(false)
	await capture("twelfth_" + result + "_mode%d" % battle.sim.data.level.mode)
	await action("map")
	await app.map_ready

func actors12() -> void:
	var sim = battle.sim
	var boss: Dictionary = sim.controller._boss(sim)
	check(not boss.is_empty(), "campaign Veznan present")
	# 1. Verify castle opening + taunt shoutbox + foreground masks + burners
	for _i in 35: sim.step()
	sim.command("wave"); sim.spawn_queue.clear()
	for _i in 10: sim.step()
	await capture("twelfth_castle_taunt")
	check(not sim.veznan.shoutboxes.is_empty(), "native taunt shoutbox active")
	check(battle.draw_list.any(func(d): return d.frame == "stage_12_0009"), "stage12 foreground mask drawn")
	check(battle.draw_list.any(func(d): return "burner" in d.frame), "stage12 burners drawn")
	check(battle.draw_list.any(func(d): return "infernalPortal" in d.frame), "veznan portals drawn")
	# 2. Build tower & verify real click release of mod_veznan_tower
	var tw: Dictionary = sim.tower_by_id("4")
	await menu("4"); await action("build", {"id": "4", "type": "mage"})
	for _i in 35: sim.step()
	sim.veznan.lock_tower(sim, tw, boss.id)
	for _i in 34: sim.step()
	await capture("twelfth_tower_lock")
	check(tw.get("blocked", false) and battle.draw_list.any(func(d): return "veznan" in d.frame and int(d.get("draw_order", 1)) >= 10), "tower lock overlay draws above tower")
	for _c in 3:
		await click(battle.world(tw.pos))
		sim.step()
	for _i in 15: sim.step()
	check(not tw.get("blocked", false) and sim.veznan.tower_locks.is_empty(), "3 native clicks release mod_veznan_tower")
	# 3. Portal activation
	sim.veznan.portals[0].spawn_signal = true
	for _i in 20: sim.step()
	await capture("twelfth_portal_active")
	check(sim.veznan.portals[0].phase == "active", "portal enters active phase")
	# 4. Descend + battle + soul drain + demon transform
	boss.veznan.phase = "battle"; boss.veznan.action = {}; boss.veznan.melee_job = {}
	boss.pos = Vector2(520, 320); boss.ignore_damage = false; boss.health_bar_hidden = false; boss.vis.bans = 0
	boss.veznan.ba.disabled = true; boss.veznan.pa.disabled = true; boss.veznan.sda.ts = sim.tick - 300
	var guard: Dictionary = sim._soldier("soldier_militia", "", 0, boss.pos + Vector2(60, 0), boss.pos + Vector2(60, 0))
	guard.rallying = false; guard.hp = 100.0; guard.max_hp = 100.0
	for _i in 15: sim.step()
	await capture("twelfth_soul_drain")
	check(guard.hp <= 0 and not sim.veznan.souls.is_empty(), "native soul drain spawns flying soul")
	# Trigger demon transform
	sim.damage(boss, 99999.0, 1)
	for _i in 45:
		sim.step()
		if boss.veznan.phase == "demon": break
	check(boss.veznan.phase == "demon", "native demon transform completes")
	var tank: Dictionary = sim._soldier("soldier_militia", "", 0, boss.pos + Vector2(50, 0), boss.pos + Vector2(50, 0))
	tank.rallying = false; tank.hp = 50000.0; tank.max_hp = 50000.0
	boss.blocker = tank.id; boss.blockers = [tank.id]; tank.target = boss.id
	tank.pos = sim.melee_slot(tank, boss)
	boss.veznan.melee_ts = [-100, -100]
	for _i in 24: sim.step()
	await capture("twelfth_demon_fire")
	check(battle.draw_list.any(func(d): return "boss_veznan" in d.frame), "demon sprite rendered")
	check(battle.draw_list.any(func(d): return "demonFire" in d.frame), "demon fire fx rendered")
	# 5. Demon death -> hide_gui -> souls -> white circle -> victory
	sim.damage(boss, 99999.0, 1)
	for _i in 125: sim.step()
	await capture("twelfth_death_souls")
	check(battle.gui_hidden and not sim.veznan.souls.is_empty(), "death hides GUI and emits souls")
	for _i in 170: sim.step()
	await capture("twelfth_white_circle")
	check(not sim.veznan.white_circles.is_empty(), "white circle expands on deathEnd")
	for _i in 120:
		sim.step()
		if sim.result == "victory": break
	check(sim.result == "victory", "natural Veznan death completes stage 12 victory")

func _run() -> void:
	create_timer(45).timeout.connect(func(): root.get_texture().get_image().save_png("res://output/level12_native_debug.png"))
	create_timer(180).timeout.connect(func(): push_error("Twelfth native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	app = AppScene.instantiate()
	app.settings_path = "res://output/level12_native_settings.json"
	app.slots_path = "res://output/level12_native_%d.progress" % Time.get_ticks_usec()
	root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit()
	app.menu._select_slot(1)
	await app.map_ready
	for id in range(1, 12):
		Fixture.complete(app.campaign, {"generation": 1, "level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	for id: String in app.campaign.selected_hero_ids().duplicate():
		app.campaign.deselect_hero(id)
	check(app.campaign.select_hero("hero_malik"), "selected Malik saved")
	await enter(12, 1)
	await capture("twelfth_opening")
	check(battle.sim.gold == 1300 and battle.sim.towers.size() == 13, "native campaign opening")
	check(battle.sim.soldiers.any(func(s): return s.template == "hero_malik"), "native campaign Malik enters")
	await actors12()
	battle.set_process(true)
	await create_timer(4.2).timeout
	battle.set_process(false)
	await capture("twelfth_victory_natural")
	await action("restart")
	check(battle.sim.wave == 0 and not battle.gui_hidden and battle.sim.veznan.tower_locks.is_empty(), "native restart clears Veznan & restores GUI")
	await settle12()
	check(app.campaign.is_playable(12, 2) and app.campaign.is_playable(12, 3) and not app.campaign.is_playable(13), "settlement opens twelfth challenges and thirteenth preview")
	for mode in [2, 3]:
		await enter(12, mode)
		await capture("twelfth_mode%d" % mode)
		check(battle.sim.gold == [1600, 2800][mode - 2] and battle.sim.lives == 1, "native challenge economy %d" % mode)
		check(battle.draw_list.any(func(d): return d.frame == "stage12_forsale"), "challenge displays stage12_forsale %d" % mode)
		check(battle.sim.soldiers.any(func(s): return s.template == "hero_malik"), "native challenge Malik allowed %d" % mode)
		if mode == 3:
			await menu("1")
			var kinds: Array = battle.hits.filter(func(h): return h.action == "build").map(func(h): return h.args.type)
			check(kinds.size() == 3 and "engineer" not in kinds, "iron bans engineer tower")
		await settle12()
		check(app.campaign.record(12).get(mode, 0) == 2, "native challenge persists %d" % mode)
	await enter(12, 3)
	await settle12("defeat")
	check(app.campaign.record(12).get(3, 0) == 2, "defeat preserves settled best score")
	var hashes: Dictionary = {}
	for path: String in [
		"tests/level12_visual.gd", "scripts/battle/battle_view.gd",
		"scripts/battle/dove_veznan.gd", "scripts/battle/controllers/level12.gd",
		"scripts/battle/dove_unit_info.gd", "scripts/battle/level01_sim.gd",
		"data/level12/definition.json",
	]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level12_native_%s.json" % suffix, {
		"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"captures": captures, "source_hashes": hashes, "full_replays": false,
		"native_input": true, "native_audio": true,
		"scope": "stage 12 three modes, foregrounds/forsale, taunt shoutbox, native 3-click tower lock release, portal, soul drain, demon fire, death souls/white circle/hide_gui, restart and settlement",
	})
	print("LEVEL12_NATIVE: ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
