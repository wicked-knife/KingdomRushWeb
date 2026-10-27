extends "res://tests/tower_upgrade_visual.gd"
const RangerArena = preload("res://tests/ranger_arena.tscn")
const RangerBehavior = preload("res://scripts/battle/dove_ranger.gd")

func native_button(label: String) -> void:
	var found: Array[Node] = arena.panel.find_children("*","Button",true,false)
	for node: Node in found:
		if node is Button and node.text == label:
			var screen: Vector2 = root.get_screen_transform() * node.get_global_transform_with_canvas() * (node.size / 2)
			for pressed in [true,false]:
				var input := InputEventMouseButton.new(); input.position = screen; input.global_position = screen; input.button_index = MOUSE_BUTTON_LEFT; input.pressed = pressed
				Input.parse_input_event(input); await process_frame
			await draw_frame(); return
	check(false,"missing control " + label)

func skill_menu() -> void:
	await menu("03")
	check(not hit("upgrade_power",{"id":"03","power":"poison"}).is_empty(),"native poison skill button")
	check(not hit("upgrade_power",{"id":"03","power":"thorn"}).is_empty(),"native thorn skill button")

func controlled_animation() -> void:
	await native_button("清场")
	battle.selected = ""; await draw_frame()
	var sim: RefCounted = battle.sim
	var tower: Dictionary = sim.tower_by_id("03")
	var units: Array = []
	for offset in [Vector2(-30,90),Vector2(30,90),Vector2(55,70)]:
		var e: Dictionary = sim._spawn_enemy("enemy_ogre",1,0)
		e.pos = tower.pos + offset; e.hp = 10000; e.max_hp = 10000; units.append(e)
	var images: Array = []
	var saw_poison := false; var saw_large_poison := false; var saw_start := false; var saw_loop := false; var saw_end := false
	var base: int = sim.tick
	tower.ranger.thorn_ts = float(base)
	for dt in range(1,480):
		sim.tick = base + dt; sim.modifiers.step(sim); RangerBehavior.step(sim,tower)
		for bullet: Dictionary in sim.projectiles: sim._bullet_step(bullet)
		sim.projectiles = sim.projectiles.filter(func(p): return not p.done)
		sim.effects = sim.effects.filter(func(e): return sim.tick - e.at < e.duration)
		if dt % 3 != 0: continue
		await draw_frame()
		for d: Dictionary in battle.draw_list: check(not battle._frame(d.frame).is_empty(),"animation frame resolves " + d.frame)
		saw_large_poison = saw_large_poison or battle.draw_list.any(func(d): return d.frame.begins_with("poison_big"))
		for m: Dictionary in sim.modifiers.active:
			if m.template == "mod_ranger_poison": saw_poison = true
			if m.template == "mod_thorn":
				saw_start = saw_start or m.phase == "start"; saw_loop = saw_loop or m.phase == "loop"; saw_end = saw_end or m.phase == "end"
		if dt <= 30 or (dt >= 270 and dt <= 468 and dt % 9 == 0): images.append(crop(tower.pos))
		if dt in [30,288,315,450]: await capture("ranger_effect_%d" % dt)
	check(saw_poison and saw_start and saw_loop and saw_end,"native poison and full thorn animation lifecycle")
	check(saw_large_poison,"large enemies use the large poison animation")
	check(battle.draw_list.any(func(d): return d.frame.begins_with("tower_archer_druid")),"druid visible after purchase")
	contact_sheet(images,"ranger",6)
	# Applied effects retain their own lifetime after the owner is sold.
	sim.command("sell",{"id":"03"}); await draw_frame(); await capture("ranger_sold")
	await native_button("清场")
	check(sim.modifiers.active.is_empty() and sim.enemies.is_empty(),"native clear removes effects")

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Ranger native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x,root.size.y]
	arena = RangerArena.instantiate(); root.add_child(arena)
	while arena.battle == null or arena.panel == null: await process_frame
	battle = arena.battle; battle.set_process(false)
	var initial_rng: int = battle.sim.rng.state
	var initial_decals: Array = battle.sim.decals.duplicate(true)
	await draw_frame(); await capture("ranger_arena_initial")
	check(arena.panel.get_global_rect().position.x >= 0 and arena.panel.get_global_rect().end.x <= arena.size.x,"arena panel fits")
	await menu("03"); await action("build",{"id":"03","type":"archer"})
	for i in range(25): battle.sim.step()
	for i in range(2): await menu("03"); await action("upgrade")
	await menu("03"); await hover(hit("upgrade").rect.get_center()); expect_text("230")
	await capture("ranger_upgrade_ready")
	battle.sim.gold = 229; await draw_frame()
	check(not hit("upgrade").enabled,"native ranger shortage disabled")
	await click(hit("upgrade").rect.get_center()); check(battle.sim.tower_by_id("03").template == "tower_archer_3","disabled upgrade preserves tower")
	battle.sim.gold = 10000; await action("upgrade")
	check(battle.sim.tower_by_id("03").template == "tower_ranger","native upgrade commits")
	await skill_menu()
	for power in ["poison","thorn"]:
		for level in range(1,4):
			var args := {"id":"03","power":power}
			await hover(hit("upgrade_power",args).rect.get_center())
			var text: String = battle.sim.data.ui.power_descriptions[power][level - 1]
			expect_text(text)
			await capture("ranger_%s_level_%d" % [power,level])
			if level == 1:
				battle.sim.gold = 224; await draw_frame()
				check(not hit("upgrade_power",args).enabled,"native skill shortage")
				await click(hit("upgrade_power",args).rect.get_center())
				check(battle.sim.tower_by_id("03").powers[power] == 0,"disabled skill has no effect")
				battle.sim.gold = 10000
			await action("upgrade_power",args)
			battle.message_time = 0
			check(battle.selected == "03" and battle.sim.tower_by_id("03").powers[power] == level,"skill purchase keeps menu")
		await draw_frame(); check(not hit("upgrade_power",{"id":"03","power":power}).enabled,power + " max native disabled")
	await hover(hit("sell").rect.get_center()); expect_text("返还 1720 金币")
	await capture("ranger_maxed")
	battle.selected = ""; await draw_frame()
	await native_button("出怪")
	for i in range(61): battle.sim.step()
	check(battle.sim.spawn_log.size() == 5,"native spawn five")
	await native_button("+10000 金币")
	await native_button("清场"); check(battle.sim.enemies.is_empty(),"native clear input")
	if not "--layout-only" in OS.get_cmdline_user_args(): await controlled_animation()
	for i in range(3):
		await native_button("完整重置")
		check(battle.sim.gold == 10000 and battle.sim.modifiers.active.is_empty() and battle.sim.wave == 0,"native reset " + str(i))
		check(battle.sim.rng.state == initial_rng and battle.sim.decals == initial_decals,"native reset reproduces initial random state " + str(i))
	await capture("ranger_reset")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"resolution":suffix,"input":"Input.parse_input_event","captures":captures,"sampled_frames":sampled_frames}
	var file := FileAccess.open("res://reports/ranger_visual_%s.json" % suffix,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	arena.queue_free(); await process_frame; await process_frame
	print("RANGER_NATIVE: ","PASS" if failures.is_empty() else str(failures)," ",suffix," checks=",checks)
	quit(0 if failures.is_empty() else 1)
