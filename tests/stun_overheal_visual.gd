extends "res://tests/feedback_visual.gd"
## Render the affected states in the native Godot window and sample actual pixels.
var pixel_samples: Array = []

func enemy_frame(enemy: Dictionary) -> String:
	var sprite: Dictionary = battle.sim.templates[enemy.template].render.sprites[0]
	var prefix: String = battle.sim.animations[Anim.key(sprite, enemy.state)].prefix
	for item: Dictionary in battle.draw_list:
		if item.pos.is_equal_approx(enemy.pos) and item.frame.begins_with(prefix + "_"): return item.frame
	return ""

func bar_pixels(soldier: Dictionary, expected: Color, label: String) -> void:
	await draw_frame()
	var p: Vector2 = battle.world(soldier.pos + battle.sim.vec(battle.sim.templates[soldier.template].health_bar.offset))
	var image: Image = root.get_texture().get_image()
	var samples: Array = []
	for x in [-8, 0, 8]:
		var point: Vector2 = root.get_screen_transform() * battle.get_global_transform_with_canvas() * ((p + Vector2(x, 0)) * battle.zoom)
		var color := image.get_pixelv(Vector2i(point))
		samples.append(color.to_html())
		check(color.is_equal_approx(expected), "native health-bar pixel " + label + " x=" + str(x) + " actual=" + color.to_html())
	if expected == Color.CYAN:
		var outside: Vector2 = root.get_screen_transform() * battle.get_global_transform_with_canvas() * ((p + Vector2(14, 0)) * battle.zoom)
		check(not image.get_pixelv(Vector2i(outside)).is_equal_approx(Color.CYAN), "overflow bar stays within normal width " + label)
	pixel_samples.append({"state":label, "expected":expected.to_html(), "pixels":samples})

func _run() -> void:
	create_timer(80).timeout.connect(func(): push_error("Stun/overheal native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	temporary = "user://stun_overheal_%d" % Time.get_ticks_usec()
	app = AppScene.instantiate(); app.settings_path = temporary + "_settings.json"; app.slots_path = temporary + "_slots.json"; root.add_child(app)
	await app.menu_ready; app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in range(1, 6): Fixture.complete(app.campaign, {"generation":1, "level_id":id, "mode":1, "difficulty":2, "result":"victory", "lives":20})
	check(app.campaign.select_hero("hero_malik"), "load actual Malik stun resources")
	await open_stage(6); await dismiss()
	var sim = battle.sim
	sim.soldiers.clear(); sim.enemies.clear(); sim.spawn_queue.clear(); sim.alerts.clear(); battle.message_time = 0
	for name in ["enemy_goblin", "enemy_ogre"]:
		var enemy: Dictionary = sim._spawn_enemy(name, 0)
		enemy.node = 70; enemy.pos = sim.vec(sim.data.paths.paths[0][0][70])
		for frame in 7: sim.step()
		await capture(name + "_walking")
		check(sim.modifiers.apply(sim, "mod_malik_stun", enemy, 1, "hero"), "native source stun applies " + name)
		var expires: int = sim.modifiers.active[-1].expires
		sim.step()
		var position: Vector2 = enemy.pos
		await capture(name + "_stunned")
		var idle: String = Anim.frame(sim.templates[name].render.sprites[0], sim.animations, {"state":"idle", "elapsed":sim.tick - enemy.state_at})
		check(enemy_frame(enemy) == idle, "render queue uses source idle instead of walking " + name)
		for frame in 9: sim.step()
		await draw_frame()
		check(enemy.pos == position and enemy_frame(enemy) == Anim.frame(sim.templates[name].render.sprites[0], sim.animations, {"state":"idle", "elapsed":sim.tick - enemy.state_at}), "native later stun frame remains idle " + name)
		sim.tick = expires - 1; sim.step(); await capture(name + "_resumed")
		check(enemy.pos != position and str(enemy.state).begins_with("walking"), "native movement resumes " + name)
		sim.enemies.clear(); sim.modifiers.clear(sim)
	await make_tower("1", "barrack", ["tower_barrack_2", "tower_barrack_3", "tower_paladin"])
	for rank in 3: check(sim.command("upgrade_power", {"id":"1", "power":"healing"}), "native healing rank " + str(rank + 1))
	for frame in 100: sim.step()
	var soldier: Dictionary = sim.soldiers.filter(func(s): return s.home == "1")[0]
	sim.soldiers = [soldier]; soldier.pos = soldier.dest; soldier.rallying = false; soldier.hp = 170
	sim.tick = maxi(400, sim.tick); sim._soldier_step(soldier)
	for frame in 17: sim.step()
	var healed: float = soldier.hp
	check(healed > soldier.max_hp, "native actual healing cast produces overflow")
	await click(battle.world(soldier.pos + Vector2(0, 8)))
	check(battle.selected_unit == soldier.id, "native click selects overhealed soldier")
	await capture("paladin_overheal_cyan")
	await bar_pixels(soldier, Color.CYAN, "overflow")
	expect_text("%d / %d" % [int(healed), int(soldier.max_hp)])
	for frame in 180: sim.step()
	check(soldier.hp == healed, "native idle regeneration keeps overflow")
	await bar_pixels(soldier, Color.CYAN, "after_idle_regen")
	sim.damage(soldier, soldier.hp - soldier.max_hp, 1)
	await capture("paladin_exact_max_hidden")
	var bar_point: Vector2 = battle.world(soldier.pos + sim.vec(sim.templates[soldier.template].health_bar.offset))
	var screen: Vector2 = root.get_screen_transform() * battle.get_global_transform_with_canvas() * (bar_point * battle.zoom)
	check(not root.get_texture().get_image().get_pixelv(Vector2i(screen)).is_equal_approx(Color.CYAN), "exactly full HP hides cyan bar")
	sim.damage(soldier, 20, 1)
	await capture("paladin_normal_health_green")
	await bar_pixels(soldier, Color("67ce26"), "below_max")
	expect_text("230 / 250")
	var hashes := {}
	for path in ["tests/stun_overheal_visual.gd", "scripts/battle/battle_view.gd", "scripts/battle/level01_sim.gd", "scripts/battle/dove_paladin.gd"]: hashes[path] = FileAccess.get_sha256("res://" + path)
	preload("res://tests/report_writer.gd").json_file("res://reports/stun_overheal_native_" + suffix + ".json", {"passed":failures.is_empty(), "checks":checks, "independent_scenarios":3, "captures":captures, "health_bar_pixels":pixel_samples, "source_hashes":hashes, "failures":failures})
	print("STUN_OVERHEAL_NATIVE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	app.queue_free(); await process_frame
	for ending in ["_settings.json", "_slots.json"]: DirAccess.remove_absolute(temporary + ending)
	quit(0 if failures.is_empty() else 1)
