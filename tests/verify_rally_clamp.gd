extends SceneTree
## Narrow regression for Dove's directional rally fallback, both barrack tiers.
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Battle = preload("res://scripts/battle/battle_view.gd")
const App = preload("res://scenes/app_root.tscn")
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func build(sim: RefCounted, sample: Dictionary) -> Dictionary:
	sim.reset(3); sim.notices.clear()
	sim.command("build", {"id":sample.tower_id, "type":"barrack"})
	var tower: Dictionary = sim.tower_by_id(sample.tower_id)
	sim.tick = tower.ready
	if sample.template == "tower_barrack_2": sim.command("upgrade", {"id":tower.id, "upgrade_to":sample.template})
	return sim.tower_by_id(sample.tower_id)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Rally clamp timeout"); quit(1))
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/rally_clamp_reference.json"))
	var simulations := {}
	for level in [1,2,3]: simulations[level] = Sim.new(Levels.load_definition(level),3)
	var ui_sample: Dictionary = {}
	for sample: Dictionary in reference.cases:
		var sim: RefCounted = simulations[int(sample.level)]
		var tower := build(sim,sample)
		var old: Vector2 = tower.rally
		var point := Sim.vec(sample.point)
		var gold: int = sim.gold
		var success: bool = sim.command("rally", {"id":tower.id, "pos":point})
		var label := "%d/%s/%s %s" % [sample.level,tower.id,sample.template,str(point)]
		check(success == sample.valid and sim.gold == gold and (tower.rally.distance_to(Sim.vec(sample.resolved)) < 0.002 if sample.valid else tower.rally == old), "source fallback result " + label)
		if success:
			var center: Vector2 = tower.pos + Sim.vec(sim.tower_template(tower).tower.range_offset)
			check(Sim.distance(center,tower.rally) <= float(sim.tower_template(tower).barrack.rally_range) + 0.001 and sim.valid_ground(tower.rally), "resolved point stays in displayed range and on legal road " + label)
			if int(sample.level) == 2 and sample.template == "tower_barrack_1" and point.distance_to(tower.rally) > 100 and ui_sample.is_empty(): ui_sample = sample
	# A resolved destination must flow through the actual input command and all
	# soldiers, releasing their old combat block before moving to the new slots.
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://rally_clamp_settings_" + token + ".json"
	app.progress_path = "user://rally_clamp_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
	var battle := Battle.new(); app.add_child(battle)
	battle.initialize(app.loader,app.audio,Levels.load_definition(2))
	battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tower := build(battle.sim,ui_sample)
	for slot in range(3): battle.sim._soldier("soldier_militia",tower.id,slot,tower.rally,tower.rally)
	var enemy: Dictionary = battle.sim._spawn_enemy("enemy_goblin",0,0)
	var soldier: Dictionary = battle.sim.soldiers[0]
	soldier.target = enemy.id; soldier.pending = {"at":9999}; enemy.blocker = soldier.id; enemy.blockers = [soldier.id]
	battle.selected = tower.id; battle._action("target",{"power":"rally"}); battle.hits.clear()
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT; input.pressed = true; input.position = battle.world(Sim.vec(ui_sample.point)) * battle.zoom
	battle._gui_input(input)
	var resolved := Sim.vec(ui_sample.resolved)
	check(tower.rally.distance_to(resolved) < 0.002 and battle.targeting == "" and battle.message_time == 0 and battle.invalid_point_time == 0, "out-of-range click succeeds without error feedback")
	check(battle.sim.soldiers.all(func(s): return s.rally_center.distance_to(resolved) < 0.002 and s.dest.is_equal_approx(battle.sim._formation(tower.rally,s.slot,tower)) and s.rallying and s.target == 0 and s.pending.is_empty()), "all soldiers use the resolved center and formation slots")
	check(enemy.blockers.is_empty() and enemy.blocker == 0, "fallback releases old combat block")
	check(not battle.sim.command("rally",{"id":tower.id,"pos":Vector2(NAN,0)}), "nonfinite rally rejected")
	var native := DisplayServer.get_name() != "headless"
	if native:
		battle.selected = tower.id; battle.queue_redraw()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/rally_clamp_native.png")
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed":failures.is_empty(),"checks":checks,"source_cases":reference.cases.size(),"failures":failures,"native":native,"scope":"directional rally fallback, range center and soldier destination"}
	var file := FileAccess.open("res://reports/rally_clamp_" + ("native" if native else "logic") + ".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("RALLY_CLAMP: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
