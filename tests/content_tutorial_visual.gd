extends "res://tests/tower_upgrade_visual.gd"
## Focused native input checks; the debug wave command avoids a full battle replay.
const App = preload("res://scenes/app_root.tscn")

func capture(label: String) -> void:
	await draw_frame(); await create_timer(0.46).timeout
	await super.capture(label)
	check(not battle.interface.paint.audit.is_empty() and battle.interface.paint.audit.all(func(row): return row.fits), "native tutorial text fits " + label)

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Tutorial native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	var app = App.instantiate()
	app.settings_path = "user://content_tutorial_settings.json"
	app.slots_path = "user://content_tutorial_%d.progress" % Time.get_ticks_usec()
	root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	app.campaign_map._action("level", {"id":1}); app.campaign_map._action("battle")
	battle = app.battle; battle.set_process(false)
	for index in range(3):
		check(battle.sim.notices[0] == "TUTORIAL_%d" % (index + 1), "native controller intro order")
		await capture("content_tutorial%d" % (index + 1))
		await action("confirm")
	check(battle.sim.notices.is_empty(), "native intro confirmations consumed")
	await action("wave"); await dismiss()
	check(not battle.sim.unlocked.reinforcements and not battle.sim.unlocked.fire, "first tutorial powers locked")
	for target in [3, 7]:
		while battle.sim.wave < target:
			await dismiss()
			check(battle.sim.command("dev_skip_wave"), "source notification boundary setup")
		var power: String = "reinforcements" if target == 3 else "fire"
		check(not battle.sim.unlocked[power] and not battle.sim.notices.is_empty(), "power awaits tutorial confirmation")
		await capture("content_power%d" % target)
		await dismiss()
		check(battle.sim.unlocked[power], "native power confirmation unlocks " + power)
	var file := FileAccess.open("res://reports/content_tutorial_native.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"full_replay":false}, "\t")); file.close()
	print("CONTENT_TUTORIAL_NATIVE: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " checks=", checks)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
