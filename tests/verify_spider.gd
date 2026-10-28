extends SceneTree
## Focused source-script and actual renderer comparison; no campaign replay.
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Battle = preload("res://scripts/battle/battle_view.gd")
const App = preload("res://scenes/app_root.tscn")
var checks := 0
var failures: Array[String] = []
var comparison := {}
var images: Array[Image] = []
var native := false
var battle: Control

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func fresh():
	var sim = Sim.new(Levels.load_definition(5),42)
	sim.notices.clear()
	return sim

func lifecycle(reference: Dictionary) -> void:
	var sim = battle.sim
	var mother: Dictionary = sim._spawn_enemy("enemy_spider_big",1,0)
	mother.pos = Vector2(500,300); mother.node = 30; mother.egg_at = -1
	sim.Spider.lay(sim,mother)
	var egg: Dictionary = sim.eggs[0]
	check(mother.state == "walkingDown", "laying does not interrupt the mother's movement animation")
	check(egg.next == reference.spawns[0].tick,"source complete egg animation precedes first hatch")
	sim.damage(mother,100000,1)
	sim.enemies.erase(mother) # Keep the egg visible while checking owner-independent hatching.
	var actual: Array = []; var expected: Array = []; var births: Array = []
	var last_spawn_count := 0
	for row: Dictionary in reference.frames:
		sim.tick = int(row.tick); sim.Spider.step(sim)
		var babies: Array = sim.enemies.filter(func(e):return e.template == "enemy_spider_tiny")
		if babies.size() > last_spawn_count:
			var e: Dictionary = babies[-1]
			births.append({"tick":sim.tick,"template":e.template,"path":e.path+1,"subpath":e.subpath+1,"node":e.node+1,"x":e.pos.x,"y":e.pos.y,"gold":sim.unit_gold(e)})
		last_spawn_count = babies.size()
		battle.draw_list.clear()
		if not sim.eggs.is_empty(): battle._queue_egg(egg)
		var visible: bool = not battle.draw_list.is_empty() and battle.draw_list[0].tint.a > 0
		var observed := {"tick":sim.tick,"visible":visible,"spawned":babies.size()}
		var wanted := {"tick":sim.tick,"visible":row.alpha>0,"spawned":int(row.spawned)}
		if visible:
			observed.merge({"state":egg.state,"frame":battle.draw_list[0].frame,"alpha":snappedf(battle.draw_list[0].tint.a,0.0001)})
		if row.alpha>0:
			wanted.merge({"state":row.state,"frame":row.frame,"alpha":snappedf(row.alpha,0.0001)})
		actual.append(observed); expected.append(wanted)
		check(observed == wanted,"source egg render and hatch tick %d" % sim.tick)
		if native and sim.tick in [0,30,60,88,89,95,101,107,167,226,227]:
			battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var scale_value := screenshot.get_height()/768.0
			var center: Vector2 = battle.world(egg.pos)*scale_value
			var crop := screenshot.get_region(Rect2i(Vector2i(center-Vector2(60,70)*scale_value),Vector2i(Vector2(120,100)*scale_value)))
			crop.resize(240,200,Image.INTERPOLATE_NEAREST); images.append(crop)
	check(JSON.parse_string(JSON.stringify(births)) == reference.spawns,"source child types, hatch order, routes, node offsets, positions and zero gold")
	check(sim.eggs.is_empty(),"empty shell is removed after four-second fade")
	var first_difference := -1
	for i in actual.size():
		if actual[i] != expected[i]: first_difference = i; break
	comparison.egg = {"expected":expected,"actual":actual,"first_difference":first_difference,"spawns":births}
	# Hatched units head from the egg toward their own advanced path node.
	for baby: Dictionary in sim.enemies.filter(func(e):return e.template == "enemy_spider_tiny"):
		var before: Vector2 = baby.pos
		var destination: Vector2 = sim.vec(sim.data.paths.paths[baby.path][baby.subpath][baby.node+1])
		sim._enemy_step(baby)
		check(baby.pos.distance_to(destination)<before.distance_to(destination),"baby moves toward its own path")
		check(baby.pos.distance_to(before)<=float(sim.templates[baby.template].motion.max_speed)*float(sim.data.rules.enemy_speed_factor)*Sim.STEP+0.001,"baby does not teleport to the advanced node")

func mother_rules(reference: Dictionary) -> void:
	var sim = fresh()
	var mother: Dictionary = sim._spawn_enemy("enemy_spider_big",1,0)
	mother.pos=Vector2(500,300); mother.egg_period=150; mother.egg_at=150
	var laid: Array = []
	for tick in 761:
		sim.tick=tick
		if tick==140: mother.silence_count=1; mother.silence_at=tick
		if tick==200: sim.modifiers._release(sim,{"silence":true,"target":mother.id,"template":"mod_paladin_silence"})
		mother.blocker=999 if tick>=350 and tick<390 else 0
		mother.stun_count=1 if tick>=530 and tick<550 else 0
		var count: int = mother.eggs_laid
		sim._enemy_step(mother)
		if mother.eggs_laid>count: laid.append(tick)
	var expected: Array = reference.mother_spawns.map(func(e):return int(e.tick))
	check(laid==expected,"source silence, blocked/stunned mother, strict cooldown and lifetime egg limit")
	comparison.mother={"expected":expected,"actual":laid}
	# Stacked silences resume the clock only after the last silence ends.
	mother.silence_count=2; mother.silence_at=800; sim.tick=830
	var deadline: int = mother.egg_at
	var silence := {"silence":true,"target":mother.id,"template":"mod_paladin_silence"}
	sim.modifiers._release(sim,silence)
	check(mother.egg_at==deadline and mother.silence_count==1,"first stacked silence removal does not resume egg clock")
	sim.tick=860; sim.modifiers._release(sim,silence)
	check(mother.egg_at==deadline+60 and mother.silence_count==0,"last silence removal restores the full suspended cooldown")

func run() -> void:
	create_timer(60).timeout.connect(func():push_error("Spider check timeout");quit(1))
	native=DisplayServer.get_name()!="headless"
	var reference := Levels.read_json("res://tests/fixtures/dove_spider_source.json")
	check(reference.source.commit==Levels.catalog().source.commit,"reference uses pinned Dove source")
	var app: Control
	var temporary := "user://spider_check_%d" % Time.get_ticks_usec()
	if native:
		app=App.instantiate(); app.settings_path=temporary+"/settings.json"; app.slots_path=temporary+"/saves"
		root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
		battle=Battle.new(); app.add_child(battle); battle.initialize(app.loader,app.audio,Levels.load_definition(5))
		battle.set_process(false); battle.set_process_input(false)
		battle.sim.notices.clear(); battle.sim.alerts.clear(); battle.pointer=Vector2(-1000,-1000)
	else:
		battle=Battle.new(); battle.sim=fresh(); battle.animations=battle.sim.animations
	for key: String in reference.animations: check(battle.animations[key]==reference.animations[key],"source binary animation "+key)
	await lifecycle(reference); mother_rules(reference)
	if native:
		var sheet := Image.create(240*6,200*2,false,Image.FORMAT_RGBA8)
		for i in images.size(): sheet.blit_rect(images[i],Rect2i(0,0,240,200),Vector2i((i%6)*240,(i/6)*200))
		sheet.save_png("res://reports/spider_native_frames.png")
		app.queue_free(); await process_frame
		if FileAccess.file_exists(temporary+"/settings.json"): DirAccess.remove_absolute(temporary+"/settings.json")
		if DirAccess.dir_exists_absolute(temporary+"/saves"): DirAccess.remove_absolute(temporary+"/saves")
		DirAccess.remove_absolute(temporary)
	else: battle.free()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":native,"independent_scenarios":2,"egg_frames":reference.frames.size(),"clock":"30 Hz; source engine waits normalized to integer ticks","comparison":comparison}
	var file := FileAccess.open("res://reports/spider_"+("native" if native else "logic")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("SPIDER: passed=",failures.is_empty()," checks=",checks," native=",native); quit(0 if failures.is_empty() else 1)
