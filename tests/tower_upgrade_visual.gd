extends SceneTree
const Arena = preload("res://tests/tower_upgrade_arena.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Anim = preload("res://scripts/battle/dove_animation.gd")
var arena: Control
var battle: Control
var failures: Array[String] = []
var checks := 0
var captures: Array = []
var sampled_frames := 0
var suffix: String

func _init() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func draw_frame() -> void:
	battle.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
func click(point: Vector2) -> void:
	# Feed the engine input pipeline using screen-space coordinates, including
	# project canvas stretching. Assertions below observe the resulting UI state.
	var screen: Vector2 = root.get_screen_transform() * battle.get_global_transform_with_canvas() * (point * battle.zoom)
	for pressed in [true, false]:
		var input := InputEventMouseButton.new()
		input.position = screen; input.global_position = screen
		input.button_index = MOUSE_BUTTON_LEFT; input.pressed = pressed
		Input.parse_input_event(input); await process_frame
	await draw_frame()
func hover(point: Vector2) -> void:
	var input := InputEventMouseMotion.new()
	input.position = root.get_screen_transform() * battle.get_global_transform_with_canvas() * (point * battle.zoom)
	Input.parse_input_event(input); await draw_frame()
func hit(action_name: String, args: Dictionary = {}) -> Dictionary:
	for entry: Dictionary in battle.hits:
		if entry.action == action_name and (args.is_empty() or args == entry.args): return entry
	return {}
func action(action_name: String, args: Dictionary = {}) -> void:
	await create_timer(0.15).timeout; await draw_frame()
	var entry := hit(action_name, args)
	check(not entry.is_empty() and entry.get("enabled", false), "native enabled " + action_name + str(args))
	if not entry.is_empty(): await click(entry.rect.get_center())
func menu(id: String = "8") -> void:
	await draw_frame(); await click(battle.world(battle.sim.tower_by_id(id).pos))
	await create_timer(0.15).timeout; await draw_frame()
	check(battle.selected == id, "native tower selection " + id)
func dismiss() -> void:
	while not battle.sim.notices.is_empty(): await action("confirm")
func restart() -> void:
	if not battle.sim.paused: await action("pause")
	await action("restart"); await dismiss(); battle.message_time = 0
func capture(label: String) -> void:
	await draw_frame()
	var path := "res://reports/towers_%s_%s.png" % [label, suffix]
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)
	for entry: Dictionary in battle.hits:
		# The existing source InfoBar is anchored at 769; tower menus must stay
		# inside 768. Retain that one-unit source bleed only for the bottom bar.
		check(entry.rect.position.x >= 0 and entry.rect.end.x <= battle.view_width and entry.rect.position.y >= 0 and entry.rect.end.y <= (769 if entry.action == "unit_info" else 768), "visible hit region " + entry.action)
	check(battle.draw_list.all(func(d): return not battle._frame(d.frame).is_empty()), "all rendered frames resolve " + label)
	captures.append({"state": label, "path": path, "gold": battle.sim.gold, "tick": battle.sim.tick})
func expect_text(value: String) -> void:
	var rows: Array = battle.interface.paint.audit.filter(func(row): return row.text == value)
	check(not rows.is_empty() and rows.all(func(row): return row.fits), "native text fits " + value)
func crop(point: Vector2 = Vector2.INF) -> Image:
	var image := root.get_texture().get_image()
	var scale_value := image.get_height() / 768.0
	var center: Vector2 = battle.world(battle.sim.tower_by_id("8").pos if point == Vector2.INF else point) * scale_value
	return image.get_region(Rect2i(Vector2i(center - Vector2(75, 115) * scale_value), Vector2i(Vector2(150, 155) * scale_value)))
func contact_sheet(images: Array, label: String, columns: int) -> void:
	var cell: Vector2i = images[0].get_size()
	var sheet := Image.create(cell.x * columns, cell.y * ceili(float(images.size()) / columns), false, Image.FORMAT_RGBA8)
	for i in range(images.size()): sheet.blit_rect(images[i], Rect2i(Vector2i.ZERO, cell), Vector2i((i % columns) * cell.x, (i / columns) * cell.y))
	check(sheet.save_png("res://reports/towers_%s_frames_%s.png" % [label, suffix]) == OK, "native contact sheet " + label)
	sampled_frames += images.size()

func build_upgrade(kind: String) -> void:
	await menu(); await action("build", {"id": "8", "type": kind})
	for i in range(25): battle.sim.step()
	await menu(); await action("upgrade")
	for i in range(20): battle.sim.step()
	await create_timer(0.15).timeout

func family(kind: String, price: int, total: int, refund: int) -> void:
	await restart()
	await menu(); await action("build", {"id": "8", "type": kind})
	for i in range(25): battle.sim.step()
	await menu()
	var entry := hit("upgrade")
	check(not entry.is_empty() and entry.args.upgrade_to == "tower_" + kind + "_2", kind + " real upgrade target")
	if entry.is_empty(): return
	await hover(entry.rect.get_center())
	var item: Dictionary = battle.sim.data.ui.tower_menus[kind][0]
	expect_text(battle.sim.data.ui.strings[item.tt_title]); expect_text(str(price))
	await capture(kind + "_ready")
	battle.sim.gold = price - 1; await draw_frame(); entry = hit("upgrade")
	check(not entry.enabled, kind + " insufficient native button disabled")
	await click(entry.rect.get_center())
	check(battle.sim.gold == price - 1 and battle.sim.tower_by_id("8").template == "tower_" + kind + "_1" and battle.selected == "8", kind + " disabled input has no effect")
	await capture(kind + "_insufficient")
	battle.sim.gold = price; await action("upgrade")
	check(battle.sim.gold == 0 and battle.sim.tower_by_id("8").template == "tower_" + kind + "_2" and battle.selected == "", kind + " native upgrade and menu close")
	battle.message_time = 0
	for i in range(20): battle.sim.step()
	await create_timer(0.15).timeout; await menu()
	check(hit("upgrade").is_empty() and hit("locked").is_empty(), kind + " no third-tier menu")
	if kind == "barrack":
		await action("target", {"power": "rally"})
		var rally: Vector2 = battle.sim.tower_by_id("8").rally
		await click(battle.world(rally))
		check(battle.targeting == "" and battle.sim.tower_by_id("8").rally.is_equal_approx(rally), "native upgraded rally input")
		await menu()
	await hover(hit("sell").rect.get_center()); expect_text("返还 %d 金币" % total)
	await capture(kind + "_refund_%d" % total)
	await action("sell")
	check(battle.sim.gold == total and battle.sim.tower_by_id("8").spent == 0, kind + " native full refund")
	battle.sim.gold = 1000
	await build_upgrade(kind); await action("wave"); await dismiss()
	await menu(); await hover(hit("sell").rect.get_center())
	expect_text("返还 %d 金币" % refund); await capture(kind + "_refund_%d" % refund)
	var gold: int = battle.sim.gold
	await action("sell")
	check(battle.sim.gold == gold + refund and battle.sim.tower_by_id("8").type == "", kind + " native post-wave refund")
	await restart(); await build_upgrade(kind)
	if kind == "barrack": await barrack_frames()
	else: await attack_frames(kind)
	# Run the regular simulation, rather than only sampling render fixtures.
	await restart(); await build_upgrade(kind); await action("wave")
	for i in range(1800):
		while not battle.sim.notices.is_empty(): battle.sim.command("confirm")
		battle.sim.step()
	check(battle.sim.kills > 0, kind + " real combat kills")
	await capture(kind + "_combat")

func attack_frames(kind: String) -> void:
	var sim: RefCounted = battle.sim
	var tower: Dictionary = sim.tower_by_id("8")
	var template: Dictionary = sim.tower_template(tower)
	var e: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	e.hp = 10000; e.max_hp = 10000
	var images: Array = []
	for direction in (["Down", "Up"] if kind == "mage" else ["Down"]):
		e.pos = tower.pos + Vector2(-65 if direction == "Up" else 65, 95 if direction == "Up" else 0)
		tower.pending = {}; tower.attack_at = sim.tick; sim._tower_step(tower)
		var start: int = sim.tick
		var length := 14 if kind == "mage" else 35
		for frame in range(length + 1):
			sim.tick = start + frame; sim._tower_step(tower)
			for projectile: Dictionary in sim.projectiles:
				if not projectile.done: sim._bullet_step(projectile)
			await draw_frame()
			for sid in range(2, template.render.sprites.size() + 1):
				var sprite: Dictionary = template.render.sprites[sid - 1]
				if not sprite.get("animated", false): continue
				var layer: Dictionary = tower.layers[sid]
				var duration := Anim.duration(sim.animations, Anim.key(sprite, layer.state))
				var state: String = layer.state if frame < duration else layer.idle
				var expected := Anim.frame(sprite, sim.animations, {"state": state, "elapsed": frame if frame < duration else frame - duration, "loop": frame >= duration})
				var position: Vector2 = tower.pos + sim.vec(sprite.offset)
				check(battle.draw_list.any(func(d): return d.frame == expected and d.pos == position and not d.flip), kind + " rendered layer %d frame %d %s" % [sid, frame, direction])
			images.append(crop())
		await capture(kind + "_attack_" + direction.to_lower())
	contact_sheet(images, kind + "_attack", 9 if kind == "engineer" else 10)

func barrack_frames() -> void:
	var sim: RefCounted = battle.sim
	var tower: Dictionary = sim.tower_by_id("8")
	var template: Dictionary = sim.tower_template(tower)
	var door: Dictionary = template.render.sprites[2]
	var images: Array = []
	for state in ["open", "close"]:
		var start: int = sim.tick
		tower.layers = {3: {"state": state, "at": start, "loop": false}}
		for frame in range(Anim.duration(sim.animations, Anim.key(door, state)) + 1):
			sim.tick = start + frame; await draw_frame()
			var expected := Anim.frame(door, sim.animations, {"state": state, "elapsed": frame, "loop": false})
			check(battle.draw_list.any(func(d): return d.frame == expected), "native level two door %s frame %d" % [state, frame])
			images.append(crop())
	contact_sheet(images, "barrack_door", 6)
	for i in range(120): sim.step()
	check(sim.soldiers.size() == 3 and sim.soldiers.all(func(s): return s.template == "soldier_footmen"), "native three footmen")
	var soldier: Dictionary = sim.soldiers[0]
	await click(battle.world(soldier.pos + Vector2(0, 8)))
	check(battle.selected_unit == soldier.id and battle.unit_info().hp_max == 100, "native footman selection and information")
	expect_text("4–6 / 1.37秒")
	await capture("footman_information")
	# Also render every source footman action frame at its real world position.
	images.clear()
	var sprite: Dictionary = sim.templates.soldier_footmen.render.sprites[0]
	for state in ["running", "attack", "death", "idle"]:
		var start: int = sim.tick
		for frame in range(Anim.duration(sim.animations, Anim.key(sprite, state))):
			sim.tick = start + frame; soldier.state = state; soldier.state_at = start
			await draw_frame()
			var expected := Anim.frame(sprite, sim.animations, {"state": state, "elapsed": frame, "loop": false})
			check(battle.draw_list.any(func(d): return d.frame == expected and d.pos == soldier.pos), "native footman %s frame %d" % [state, frame])
			images.append(crop(soldier.pos))
	contact_sheet(images, "footman", 6)

func _run() -> void:
	create_timer(170).timeout.connect(func(): quit(1))
	suffix = "%dx%d" % [root.size.x, root.size.y]
	arena = Arena.instantiate(); root.add_child(arena)
	while arena.battle == null: await process_frame
	battle = arena.battle; battle.set_process(false)
	await family("barrack", 110, 180, 108)
	await family("engineer", 220, 345, 207)
	await family("mage", 160, 260, 156)
	arena.remove_child(battle); battle.queue_free(); await process_frame
	battle = Battle.new(); arena.add_child(battle); arena.battle = battle
	battle.initialize(arena.loader, arena.audio); battle.set_process(false); await dismiss()
	for kind in ["barrack", "engineer", "mage", "archer"]:
		await restart(); battle.sim.command("dev_add_gold")
		await menu(); await action("build", {"id": "8", "type": kind})
		for i in range(25): battle.sim.step()
		await menu()
		check(hit("upgrade").is_empty() and not hit("locked").is_empty(), kind + " production locked menu")
		var gold: int = battle.sim.gold
		await click(hit("locked").rect.get_center())
		check(battle.sim.gold == gold and battle.sim.tower_by_id("8").template == "tower_" + kind + "_1", kind + " locked real input")
		await hover(hit("locked").rect.get_center()); expect_text("本关只能建造一级防御塔。")
		await capture(kind + "_campaign_locked")
	for i in range(3):
		await restart()
		check(battle.sim.gold == 270 and battle.sim.towers.all(func(t): return t.spent == 0) and battle.sim.tower_locked("tower_mage_2"), "native production restart isolation %d" % i)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "resolution": suffix, "input": "Input.parse_input_event", "captures": captures, "sampled_frames": sampled_frames}
	var file := FileAccess.open("res://reports/tower_upgrade_visual_%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	arena.queue_free(); await process_frame; await process_frame
	print("TOWER_UPGRADE_VISUAL: ", "PASS" if failures.is_empty() else str(failures), " ", suffix, " checks=", checks)
	quit(0 if failures.is_empty() else 1)
