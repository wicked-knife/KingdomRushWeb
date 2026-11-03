extends "res://tests/level09_visual.gd"
func _run() -> void:
	create_timer(180).timeout.connect(func():push_error("Tenth native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y]
	app=AppScene.instantiate();app.settings_path="user://level10_native_settings.json";app.slots_path="user://level10_native_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,10):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(10,1);await capture("tenth_opening")
	check(battle.sim.gold==800 and battle.sim.towers.size()==14,"native tenth source opening")
	battle.sim.gold=20000
	await menu("1");await action("build",{"id":"1","type":"engineer"})
	for i in 30:battle.sim.step()
	for name:String in ["tower_engineer_2","tower_engineer_3","tower_tesla"]:
		await menu("1");await action("upgrade",{"id":"1","upgrade_to":name})
	for power:String in ["bolt","overcharge"]:
		for rank in 3:await menu("1");await action("upgrade_power",{"id":"1","power":power})
		await menu("1");await hover(hit("upgrade_power",{"id":"1","power":power}).rect.get_center());await capture("tenth_power_"+power)
	var sim=battle.sim;var tower:Dictionary=sim.tower_by_id("1")
	battle.selected="";battle.hovered="";tower.pos=Vector2(500,350)
	for i in 6:
		var e:Dictionary=sim._spawn_enemy("enemy_demon" if i%2==0 else "enemy_demon_wolf",0)
		e.pos=Vector2(550+i*35,350);e.hp=10000;e.max_hp=10000;e.progress=100-i
	sim.tick=200;sim._tower_step(tower);sim.tick=tower.tesla.cast.fire;sim._tower_step(tower)
	for i in 7:
		for p:Dictionary in sim.projectiles.duplicate():sim._bullet_step(p)
		sim.snow.step(sim);sim.tick+=1
	await capture("tenth_tesla_chain")
	check(battle.draw_list.any(func(d):return d.frame.begins_with("ray_tesla")),"native source Tesla ray frame")
	check(battle.draw_list.any(func(d):return d.frame.begins_with("teslahit")),"native source Tesla hit frame")
	check(not sim.snow.particles.is_empty(),"native overcharge particles")
	var finish_at:int=int(tower.tesla.cast.end)
	for tick10 in range(sim.tick,finish_at+1):
		sim.tick=tick10
		for p:Dictionary in sim.projectiles.duplicate():sim._bullet_step(p)
		sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
		sim.Behaviors.Tesla.auras(sim);sim.snow.step(sim)
	sim._tower_step(tower)
	await capture("tenth_tesla_finished")
	check(tower.tesla.cast.is_empty() and tower.layers[2].state=="idle","native Tesla returns to idle after source shoot animation")
	for tick10 in range(sim.tick+1,sim.tick+70):
		sim.tick=tick10
		for p:Dictionary in sim.projectiles.duplicate():sim._bullet_step(p)
		sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
		sim.Behaviors.Tesla.auras(sim);sim.snow.step(sim)
	await capture("tenth_tesla_ray_end")
	check(sim.projectiles.is_empty() and sim.auras.is_empty(),"native Tesla rays and overcharge finish")
	check(not battle.draw_list.any(func(d):return d.frame.begins_with("ray_tesla")),"native completed rays leave render queue")
	sim.tick+=90;sim.snow.step(sim)
	check(sim.snow.particles.is_empty(),"native overcharge emission and particle lifetimes finish")
	sim.enemies.clear();sim.projectiles.clear();sim.auras.clear();sim.modifiers.clear(sim)
	var corpse:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);sim.damage(corpse,100000,1)
	sim.tick+=20;sim.controller.step(sim)
	var raised:Dictionary=sim.enemies[-1]
	await frame9(raised,"raise","tenth_skeleton_raise")
	sim.tick=raised.raise_until;sim._enemy_step(raised);await capture("tenth_skeleton_walk")
	check(raised.state!="raise","native raising ends into movement")
	var big:Dictionary=sim._spawn_enemy("enemy_skeleton_big",0);big.pos=Vector2(620,390)
	sim.tick+=50;sim.wasteland.step(sim);await capture("tenth_skeleton_aura")
	check(battle.draw_list.any(func(d):return d.frame=="CB_DeathKnight_aura_0001" and d.tint.a>0),"native skeleton aura fades into render queue")
	sim.damage(big,100000,1);await capture("tenth_skeleton_aura_end")
	check(not battle.draw_list.any(func(d):return d.frame=="CB_DeathKnight_aura_0001" and d.pos.is_equal_approx(big.pos+Vector2(0,-8))),"native skeleton aura stops when owner dies")
	# Source magic bolt keeps the gold star and emits the missing particle trail.
	sim.enemies.clear();sim.snow.particles.clear()
	var target:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);target.pos=Vector2(700,430)
	sim._projectile("bolt_sorcerer",target.id,Vector2(450,430),target.pos,1)
	for i in 6:sim.tick+=1;sim._bullet_step(sim.projectiles[-1])
	await capture("tenth_sorcerer_trail")
	check(battle.draw_list.any(func(d):return d.frame=="sorcererbolt_particle"),"native Sorcerer source trail sprite")
	check(battle.draw_list.any(func(d):return d.frame.begins_with("sorcererbolt_star")),"native Sorcerer gold star retained")
	await restart();check(sim.wave==0 and sim.controller.graveyards[0].queue.is_empty(),"native restart clears graveyard")
	sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await action("map");await app.map_ready
	check("tower_tesla" not in app.campaign.data.locked_towers and app.campaign.is_playable(10,2) and not app.campaign.is_playable(11),"native tenth unlock and eleventh preview")
	for mode in [2,3]:
		await enter(10,mode);await capture("tenth_mode%d"%mode)
		check(battle.sim.gold==[1800,2200][mode-2] and battle.sim.lives==1,"native challenge opening %d"%mode)
		if mode==3:
			await menu("1");check(not battle.hits.any(func(h):return h.action=="build" and h.args.type=="engineer"),"native iron bans artillery construction")
		battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await action("map");await app.map_ready
		check(app.campaign.record(10).get(mode,0)==2,"native challenge result persists %d"%mode)
	var hashes:Dictionary={}
	for path:String in ["tests/level10_visual.gd","scripts/battle/battle_view.gd","scripts/battle/dove_tesla.gd","scripts/battle/dove_wasteland.gd","scripts/battle/dove_snow.gd","data/level10/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level10_native_%s.json"%suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes,"full_replays":false})
	print("LEVEL10_NATIVE: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
