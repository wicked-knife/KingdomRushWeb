extends SceneTree
## Compare actual death rendering with pinned source animations and hide flags.
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
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func sample(name: String, expected: Dictionary) -> void:
	var sim = battle.sim
	sim.reset(42); sim.notices.clear(); sim.alerts.clear()
	var enemy: Dictionary = sim._spawn_enemy(name,1,0)
	enemy.pos=Vector2(500,400)
	sim.damage(enemy,100000,2)
	check(enemy.state=="death" and enemy.dead_at==0,"lethal damage starts source death action "+name)
	var animation: Dictionary = expected.animation
	var frames: Array = []; var first_difference := -1
	for tick in 61:
		sim.tick=tick; battle.draw_list.clear()
		battle._queue_template(name,enemy.pos,enemy.state,enemy.state_at,enemy.flip,false,1,true,"",enemy)
		var wanted: String = "%s_%04d" % [animation.prefix,int(animation.frames[tick])] if tick<animation.frames.size() else "hidden"
		var actual: String = battle.draw_list[0].frame if not battle.draw_list.is_empty() else "hidden"
		frames.append({"tick":tick,"expected":wanted,"actual":actual})
		if actual!=wanted and first_difference<0: first_difference=tick
		check(actual==wanted,"source death frame/hide %s tick=%d" % [name,tick])
		if not battle.draw_list.is_empty(): check(is_equal_approx(battle.draw_list[0].tint.a,1.0),"death action keeps source opacity "+name)
		if native and name in ["enemy_wolf","enemy_wolf_small"] and tick in [0,2,4,6,8,10,12,15,17]:
			battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var scale_value := screenshot.get_height()/768.0
			var center: Vector2 = battle.world(enemy.pos)*scale_value
			var crop := screenshot.get_region(Rect2i(Vector2i(center-Vector2(55,65)*scale_value),Vector2i(Vector2(110,90)*scale_value)))
			crop.resize(220,180,Image.INTERPOLATE_NEAREST); images.append(crop)
	comparison[name]={"frames":frames,"first_difference":first_difference,"hidden_at":animation.frames.size()}
	# Visual hiding does not shorten the source entity lifetime or award twice.
	var gold: int = sim.gold; var kills: int = sim.kills
	sim.tick=sim.frames(expected.dead_lifetime)-2; sim.step()
	check(sim.enemies.has(enemy),"dead entity retained until source cleanup "+name)
	sim.step()
	check(not sim.enemies.has(enemy) and sim.gold==gold and sim.kills==kills,"source cleanup preserves rewards "+name)

func run() -> void:
	create_timer(60).timeout.connect(func():push_error("Death check timeout");quit(1))
	native=DisplayServer.get_name()!="headless"
	var reference := Levels.read_json("res://tests/fixtures/dove_death_source.json")
	check(reference.source.commit==Levels.catalog().source.commit,"death reference uses pinned source")
	var app: Control
	var temporary := "user://death_check_%d" % Time.get_ticks_usec()
	if native:
		app=App.instantiate(); app.settings_path=temporary+"/settings.json"; app.slots_path=temporary+"/saves"
		root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
		battle=Battle.new(); app.add_child(battle); battle.initialize(app.loader,app.audio,Levels.load_definition(6))
		battle.set_process(false); battle.set_process_input(false); battle.pointer=Vector2(-1000,-1000)
	else:
		battle=Battle.new(); battle.sim=Sim.new(Levels.load_definition(6),42); battle.animations=battle.sim.animations
	for name in ["enemy_wolf","enemy_wolf_small","enemy_gargoyle","enemy_golem_head"]: await sample(name,reference.units[name])
	# Units which leave corpses retain their existing death rendering.
	var sim = battle.sim; var enemy: Dictionary = sim._spawn_enemy("enemy_goblin",1,0)
	sim.damage(enemy,100000,2); sim.tick=enemy.dead_at+20; battle.draw_list.clear()
	battle._queue_template(enemy.template,enemy.pos,enemy.state,enemy.state_at,false,false,1,true,"",enemy)
	check(not battle.draw_list.is_empty(),"ordinary corpse rendering is unaffected")
	if native:
		var sheet := Image.create(220*9,180*2,false,Image.FORMAT_RGBA8)
		for i in images.size(): sheet.blit_rect(images[i],Rect2i(0,0,220,180),Vector2i((i%9)*220,(i/9)*180))
		sheet.save_png("res://reports/wolf_native_death_frames.png")
		app.queue_free(); await process_frame
		if FileAccess.file_exists(temporary+"/settings.json"): DirAccess.remove_absolute(temporary+"/settings.json")
		if DirAccess.dir_exists_absolute(temporary+"/saves"): DirAccess.remove_absolute(temporary+"/saves")
		DirAccess.remove_absolute(temporary)
	else: battle.free()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":native,"independent_scenarios":5,"comparison":comparison}
	var file := FileAccess.open("res://reports/death_animation_"+("native" if native else "logic")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DEATH_ANIMATION: passed=",failures.is_empty()," checks=",checks," native=",native); quit(0 if failures.is_empty() else 1)
