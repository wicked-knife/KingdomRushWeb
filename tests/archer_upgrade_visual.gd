extends SceneTree
const Arena = preload("res://tests/archer_upgrade_arena.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
var arena: Control
var battle: Control
var failures: Array[String] = []
var captures: Array = []
var checks := 0
var suffix: String
var attack_frames: Array = []

func _init() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func draw_frame() -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw

func click(point: Vector2) -> void:
	var input := InputEventMouseButton.new()
	input.position = point * battle.zoom; input.button_index = MOUSE_BUTTON_LEFT; input.pressed = true
	battle._gui_input(input)

func hover(point: Vector2) -> void:
	var input := InputEventMouseMotion.new()
	input.position = point * battle.zoom
	battle._gui_input(input)
	await draw_frame()

func menu(id: String = "8") -> void:
	await draw_frame()
	click(battle.world(battle.sim.tower_by_id(id).pos))
	await create_timer(0.16).timeout
	await draw_frame()

func hit(action: String) -> Dictionary:
	for entry: Dictionary in battle.hits:
		if entry.action == action: return entry
	return {}

func action(id: String) -> void:
	await create_timer(0.16).timeout
	await draw_frame()
	var entry := hit(id)
	check(not entry.is_empty() and entry.get("enabled", false), "enabled native action " + id)
	if not entry.is_empty(): click(entry.rect.get_center())
	await draw_frame()

func capture(label: String) -> void:
	await draw_frame()
	var path := "res://reports/archer_%s_%s.png" % [label, suffix]
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)
	for entry: Dictionary in battle.hits:
		check(entry.rect.position.x >= 0 and entry.rect.end.x <= battle.view_width and entry.rect.position.y >= 0 and entry.rect.end.y <= 768, "native hit region stays visible " + entry.action)
	captures.append({"state": label, "path": path, "gold": battle.sim.gold, "tick": battle.sim.tick})

func expect_text(value: String) -> void:
	var rows: Array = battle.interface.paint.audit.filter(func(row): return row.text == value)
	check(not rows.is_empty() and rows.all(func(row): return row.fits), "native tooltip text fits: " + value)

func crop_tower() -> Image:
	var image := root.get_texture().get_image()
	# The viewport capture already applies the project canvas stretch. Its pixel
	# scale differs from the Control's input-space zoom at non-design resolutions.
	var pixel_scale := image.get_height() / 768.0
	var center: Vector2 = battle.world(battle.sim.tower_by_id("8").pos) * pixel_scale
	return image.get_region(Rect2i(Vector2i(center - Vector2(65, 110) * pixel_scale), Vector2i(Vector2(130, 140) * pixel_scale)))

func dismiss() -> void:
	while not battle.sim.notices.is_empty(): battle.sim.command("confirm")

func _run() -> void:
	create_timer(110).timeout.connect(func(): quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	arena = Arena.instantiate(); root.add_child(arena)
	while arena.battle == null: await process_frame
	battle = arena.battle; battle.set_process(false)
	await menu(); await action("build")
	for i in range(25): battle.sim.step()
	await menu()
	check(battle.selected == "8", "native selection of constructed archer")
	var upgrade := hit("upgrade")
	check(not upgrade.is_empty() and upgrade.args == {"id": "8", "upgrade_to": "tower_archer_2"}, "real upgrade button dispatch")
	await hover(upgrade.rect.get_center()); await capture("upgrade_ready")
	expect_text("射手塔"); expect_text("110")
	battle.sim.gold = 109; await draw_frame()
	upgrade = hit("upgrade")
	check(not upgrade.enabled, "109 gold disables upgrade button")
	click(upgrade.rect.get_center())
	check(battle.sim.gold == 109 and battle.sim.tower_by_id("8").template == "tower_archer_1" and battle.selected == "8", "disabled native click leaves gold and tower intact")
	await capture("insufficient_gold")
	battle.sim.gold = 110; await action("upgrade")
	battle.message_time = 0
	check(battle.sim.gold == 0 and battle.sim.tower_by_id("8").template == "tower_archer_2" and battle.selected == "", "native upgrade commits and closes selection")
	await create_timer(0.16).timeout
	await menu()
	check(hit("upgrade").is_empty() and hit("locked").is_empty(), "tier two offers no tier three action")
	check(battle.draw_list.any(func(d): return d.frame == "archer_tower_0002"), "tier two body reaches native draw list")
	check(battle.draw_list.filter(func(d): return d.frame == "tower_archer_lvl2_shooter_0001").size() == 2, "two tier two idle shooters rendered")
	await hover(hit("sell").rect.get_center()); await capture("tier_two_refund_180")
	expect_text("返还 180 金币")
	await action("sell")
	check(battle.sim.gold == 180 and battle.sim.tower_by_id("8").spent == 0, "native pre-wave refund is 180")
	await menu(); await action("build")
	for i in range(25): battle.sim.step()
	await menu(); await action("upgrade")
	await action("wave")
	await menu(); await hover(hit("sell").rect.get_center()); await capture("tier_two_refund_108")
	expect_text("返还 108 金币")
	await action("sell")
	check(battle.sim.gold == 108 and battle.sim.tower_by_id("8").template == "tower_holder_grass", "native post-wave refund is 108")

	# Reset through the UI; preserve the independent fixture rules for real combat.
	await action("pause"); await action("restart"); dismiss()
	battle.message_time = 0
	await menu(); await action("build")
	for i in range(25): battle.sim.step()
	await menu(); await action("upgrade")
	for i in range(20): battle.sim.step()
	await create_timer(0.16).timeout
	var tower: Dictionary = battle.sim.tower_by_id("8")
	var target: Dictionary = battle.sim._spawn_enemy("enemy_fat_orc", 0)
	target.hp = 10000; target.max_hp = 10000
	for direction in ["Down", "Up"]:
		target.pos = tower.pos + Vector2(-60 if direction == "Up" else 60, 90 if direction == "Up" else 0)
		for shooter in range(2):
			tower.pending = {}; tower.attack_at = battle.sim.tick; battle.sim._tower_step(tower)
			var sid: int = 4 if shooter == 0 else 3
			check(tower.layers[sid].state == "shooting" + direction, "native facing " + direction)
			var start: int = battle.sim.tick
			for frame in range(9):
				battle.sim.tick = start + frame; battle.sim._tower_step(tower)
				for bullet: Dictionary in battle.sim.projectiles:
					if not bullet.done: battle.sim._bullet_step(bullet)
				await draw_frame()
				var expected := "tower_archer_lvl2_shooter_%04d" % ((3 if direction == "Down" else 11) + frame) if frame < 8 else ("tower_archer_lvl2_shooter_0001" if direction == "Down" else "tower_archer_lvl2_shooter_0002")
				var shooter_pos: Vector2 = tower.pos + battle.Simulation.vec(battle.sim.tower_template(tower).render.sprites[sid - 1].offset)
				check(battle.draw_list.any(func(d): return d.frame == expected and d.pos == shooter_pos and d.flip == (direction == "Up")), "native attack and return frame %s %d %d" % [direction, shooter, frame])
				check(battle.draw_list.all(func(d): return not battle._frame(d.frame).is_empty()), "every native attack frame resolves")
				attack_frames.append(crop_tower())
			await capture("attack_%s_%d" % [direction.to_lower(), shooter])
	var cell: Vector2i = attack_frames[0].get_size()
	var sheet := Image.create(cell.x * 9, cell.y * 4, false, Image.FORMAT_RGBA8)
	for i in range(attack_frames.size()): sheet.blit_rect(attack_frames[i], Rect2i(Vector2i.ZERO, cell), Vector2i((i % 9) * cell.x, (i / 9) * cell.y))
	check(sheet.save_png("res://reports/archer_attack_frames_%s.png" % suffix) == OK, "save all native animation frames")
	# Use the full simulation after the frame fixture: the upgraded tower really kills.
	battle.sim.reset(); dismiss()
	battle.sim.command("build", {"id": "8", "type": "archer"})
	for i in range(25): battle.sim.step()
	battle.sim.command("upgrade", {"id": "8", "upgrade_to": "tower_archer_2"})
	battle.sim.command("wave")
	for i in range(1600):
		dismiss(); battle.sim.step()
	check(battle.sim.kills > 0, "upgraded tower kills in normal native simulation")
	await capture("combat")

	# A new production view in the same process must still use the campaign lock.
	arena.remove_child(battle); battle.queue_free(); await process_frame
	battle = Battle.new(); arena.add_child(battle); arena.battle = battle
	battle.initialize(arena.loader, arena.audio); battle.set_process(false); dismiss()
	await menu(); await action("build")
	for i in range(25): battle.sim.step()
	await menu()
	check(hit("upgrade").is_empty() and not hit("locked").is_empty(), "campaign view keeps locked upgrade icon")
	var gold: int = battle.sim.gold
	click(hit("locked").rect.get_center())
	check(battle.sim.gold == gold and battle.sim.tower_by_id("8").template == "tower_archer_1", "locked native button cannot upgrade")
	check(not battle.sim.command("upgrade", {"id": "8", "upgrade_to": "tower_archer_2"}), "campaign view command guard")
	await hover(hit("locked").rect.get_center()); await capture("campaign_locked")
	expect_text("升级尚未解锁"); expect_text("本关只能建造一级防御塔。")
	for i in range(3):
		await action("pause"); await action("restart"); dismiss()
		check(battle.sim.gold == 270 and battle.sim.tower_locked("tower_archer_2") and battle.sim.towers.all(func(t): return t.spent == 0), "native campaign reset isolation %d" % i)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "resolution": suffix, "captures": captures, "attack_frames": attack_frames.size()}
	var file := FileAccess.open("res://reports/archer_upgrade_visual_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	arena.queue_free(); await process_frame; await process_frame
	print("ARCHER_UPGRADE_VISUAL: ", "PASS" if failures.is_empty() else str(failures), " ", suffix, " checks=", checks)
	quit(0 if failures.is_empty() else 1)
