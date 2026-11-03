extends "res://tests/level09_visual.gd"
func _run() -> void:
	create_timer(120).timeout.connect(func():push_error("Tesla animation native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y]
	app=AppScene.instantiate();app.settings_path="user://tesla_animation_settings.json";app.slots_path="user://tesla_animation_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,10):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(10,1)
	var sim=battle.sim;sim.enemies.clear();sim.soldiers.clear()
	for i in 3:
		var e:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);e.pos=Vector2(530+i*40,350+i*20)
	var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/level10_source.json"))
	var tower:Dictionary=sim.tower_by_id("1");tower.template="tower_tesla";tower.type="engineer";tower.pos=Vector2(493,321);sim.Behaviors.Tesla.initialize(sim,tower)
	sim.tick=-1;sim.Behaviors.Tesla.launch(sim,sim.tower_by_id("1"),sim.enemies[0],Vector2(500,400),0)
	for n in 20:
		sim.tick=n
		for i in 3:sim.enemies[i].pos=Vector2(530+i*40+n*2,350+i*20+n)
		for p:Dictionary in sim.projectiles.duplicate():sim._bullet_step(p)
		sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
		await draw_frame()
		var expected:Array=reference.ray_visuals.moving.filter(func(row):return int(row[0])==n and not row[9])
		var rays:Array=battle.draw_list.filter(func(d):return d.frame.begins_with("ray_tesla_"))
		check(rays.size()==expected.size(),"native source ray count tick %d"%n)
		for row:Array in expected:
			var point:=Vector2(row[2],row[3]);var scale_value:=Vector2(row[7],row[8])
			var frame:String="ray_tesla_%04d"%(int(row[10])+1)
			check(rays.any(func(d):return d.frame==frame and d.pos.is_equal_approx(point) and d.scale.is_equal_approx(scale_value) and absf(d.rotation-float(row[6]))<0.00001 and d.anchor==Vector2(0,0.5)),"native exact source geometry and frame tick %d ray %d"%[n,int(row[1])])
		if n in [0,1,2,3,5,8,12,15,18]:await capture("tesla_moving_%02d"%n)
	var hashes:Dictionary={}
	for path:String in ["tests/tesla_animation_visual.gd","scripts/battle/dove_tesla.gd","scripts/battle/battle_view.gd","tests/fixtures/level10_source.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/tesla_animation_native.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes})
	print("TESLA_ANIMATION_NATIVE: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
