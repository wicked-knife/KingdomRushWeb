extends SceneTree
## Sample the actual renderer through an elf's complete source shooting action.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
var checks := 0
var failures: Array[String] = []
var samples := {}
var images: Array[Image] = []
var battle: Control
var native := false

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func render() -> void:
	battle.queue_redraw(); await process_frame; await process_frame
	if native: await RenderingServer.frame_post_draw

func shot(left: bool, cripple: bool) -> void:
	var sim: RefCounted = battle.sim
	sim.reset(42); sim.notices.clear(); sim.gold = 10000
	sim.command("upgrade",{"id":"5","upgrade_to":"tower_elf"})
	sim.command("buy_soldier",{"id":"5","type":"soldier_elf"})
	for i in 80: sim.step()
	var elf: Dictionary = sim.soldiers[0]
	elf.pos = Vector2(500,550); elf.dest = elf.pos; elf.rallying = false; elf.rally_pending = false
	elf.powers.cripple = 3 if cripple else 0
	var enemy: Dictionary = sim._spawn_enemy("enemy_brigand",1,0)
	enemy.pos = elf.pos + Vector2(-100 if left else 100,0)
	# A controlled chance sample exercises the special arrow without modifying data.
	if cripple:
		while true:
			var saved: int = sim.rng.state
			if sim.rng.randf() <= 0.5: sim.rng.state = saved; break
	var start: int = sim.tick
	var expected: Array = []; var actual: Array = []
	for elapsed in 12:
		sim.tick = start + elapsed; sim._soldier_step(elf)
		var rng_state: int = sim.rng.state
		battle.draw_list.clear()
		battle._queue_template(elf.template,elf.pos,elf.state,elf.state_at,elf.flip)
		expected.append("elfSoldier_%04d" % (25+elapsed)); actual.append(battle.draw_list[0].frame)
		check(actual[-1] == expected[-1],"source elf shoot frame %d left=%s cripple=%s" % [elapsed,left,cripple])
		check(sim.rng.state == rng_state,"rendering preserves battle RNG")
		check(sim.projectiles.size() == (0 if elapsed < 7 else 1),"single arrow at source tick 7")
		if native and elapsed in [0,4,6,7,11]:
			await render()
			var image := root.get_texture().get_image()
			var scale_value := image.get_height() / 768.0
			var center: Vector2 = battle.world(elf.pos) * scale_value
			var crop := image.get_region(Rect2i(Vector2i(center - Vector2(36,52) * scale_value),Vector2i(Vector2(72,64) * scale_value)))
			crop.resize(216,192,Image.INTERPOLATE_NEAREST); images.append(crop)
	check(elf.flip == left,"source left/right facing")
	check(sim.projectiles[0].from == elf.pos + Vector2(-4 if left else 4,16),"arrow starts at source bow offset")
	check(sim.projectiles[0].template == ("arrow_elf_cripple" if cripple else "arrow_elf"),"source arrow variant")
	var first_difference := -1
	for i in expected.size():
		if actual[i] != expected[i]: first_difference = i; break
	samples["left" if left else "right"] = {"expected":expected,"actual":actual,"first_difference":first_difference}
	sim.enemies.clear(); sim.tick = start + 12; sim._soldier_step(elf)
	check(elf.state == "idle","complete shooting action returns to idle")

func run() -> void:
	create_timer(60).timeout.connect(func():push_error("Ranged animation timeout");quit(1))
	native = DisplayServer.get_name() != "headless"
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://ranged_animation_settings_"+token+".json"
	app.slots_path = "user://ranged_animation_progress_"+token+".json"
	root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
	battle = Battle.new(); app.add_child(battle); battle.initialize(app.loader,app.audio,Levels.load_definition(5))
	battle.set_process(false); battle.set_process_input(false)
	await render(); await shot(false,false); await shot(true,true)
	# A sprite's walk angles must not hide its ordinary shoot action either.
	battle.sim.templates.enemy_shadow_archer = Levels.load_definition(6).templates.enemy_shadow_archer
	var sixth_animations: Dictionary = Levels.read_json("res://data/level06/animations.json").animations
	battle.animations.merge(sixth_animations)
	battle.draw_list.clear(); battle._queue_template("enemy_shadow_archer",Vector2.ZERO,"shoot",battle.sim.tick)
	check(battle.draw_list[0].frame == "shadowArcher_0075","enemy archer also retains its source shoot animation")
	for up in [true,false]:
		battle.draw_list.clear(); battle._queue_template("tower_archer_1",Vector2.ZERO,"shoot",battle.sim.tick,false,up)
		var sprite: Dictionary = battle.sim.templates.tower_archer_1.render.sprites.filter(func(s):return s.get("angles",{}).has("shoot"))[0]
		var key: String = sprite.prefix + ("_shootingUp" if up else "_shootingDown")
		var animation: Dictionary = battle.animations[key]
		check(battle.draw_list.any(func(d):return d.frame == "%s_%04d" % [animation.prefix,animation.frames[0]]),"tower directional shooting remains intact")
	var captures: Array[String] = []
	if native:
		var sheet := Image.create(216*5,192*2,false,Image.FORMAT_RGBA8)
		for i in images.size(): sheet.blit_rect(images[i],Rect2i(0,0,216,192),Vector2i((i%5)*216,(i/5)*192))
		var path := "res://reports/elf_ranged_animation_frames.png"; sheet.save_png(path); captures.append(path)
	app.queue_free(); await process_frame
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":native,"independent_scenarios":2,"source_frames":24,"samples":samples,"captures":captures,"source":"Dove current soldier_elf_shoot: elfSoldier 25-36; shoot_time 7/30; bullet_start_offset (4,16)","scope":"elf normal/special arrows, both facings; enemy and tower animation group regression"}
	var file := FileAccess.open("res://reports/ranged_animation_"+("native" if native else "logic")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("RANGED_ANIMATION: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
