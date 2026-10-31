extends "res://tests/level07_visual.gd"
## Native input and representative lifecycle frames; constructed results, no victory search.

func menu(id:String="11") -> void:
	if battle.selected==id:await draw_frame();return
	await super.menu(id)

func new_tower(id:String,kind:String,target:String) -> void:
	battle.sim.gold=20000
	await menu(id);await action("build",{"id":id,"type":kind})
	for i in 30:battle.sim.step()
	for name:String in ["tower_"+kind+"_2","tower_"+kind+"_3",target]:
		await menu(id);await capture("eighth_branch_"+name)
		await action("upgrade",{"id":id,"upgrade_to":name})
	check(battle.sim.tower_by_id(id).template==target,"native new tower branch "+target)
	for power:String in battle.sim.tower_by_id(id).powers:
		for rank in 3:await menu(id);await action("upgrade_power",{"id":id,"power":power})
		await menu(id);await hover(hit("upgrade_power",{"id":id,"power":power}).rect.get_center());await capture("eighth_power_"+power)
		check(battle.interface.paint.audit.all(func(row):return row.fits),"native new tower tooltip fits "+power)
	battle.selected="";battle.hovered=""

func unit_frame(unit:Dictionary,state:String,elapsed:int,label:String) -> void:
	var t:Dictionary=battle.sim.unit_template(unit);var sprite:Dictionary=t.render.sprites[0]
	var expected:String=Anim.frame(sprite,battle.animations,{"state":state,"elapsed":elapsed,"loop":false})
	await capture("eighth_"+label)
	check(battle.draw_list.any(func(d):return d.frame==expected and d.pos.distance_to(unit.pos+battle.sim.vec(sprite.get("offset",{"x":0,"y":0})))<0.01),"native exact unit frame "+label+" "+expected)

func runtime_frames() -> void:
	var sim=battle.sim
	for i in 100:sim.step()
	var barb:Dictionary=sim.soldiers.filter(func(s):return s.template=="soldier_barbarian")[0]
	barb.pos=Vector2(640,390);barb.dest=barb.pos;barb.rallying=false
	sim.Behaviors.AdvancedBarrack._changes(sim,barb)
	await unit_frame(barb,"idle2",0,"barbarian_dual_idle")
	var enemy:Dictionary=sim._spawn_enemy("enemy_troll",0);enemy.pos=barb.pos+Vector2(20,0);enemy.node=60;enemy.hp=10000
	var t:Dictionary=barb.combat_template;var a:Dictionary=t.melee.attacks[1]
	sim.Behaviors.AdvancedBarrack._begin(sim,barb,t,a,{"kind":"melee","target":enemy.id,"entity":enemy,"index":1},float(a.hit_time))
	sim.tick=barb.advanced_job.hit_at;sim.Behaviors.AdvancedBarrack._job(sim,barb,t)
	await unit_frame(barb,"twister2",sim.tick-barb.state_at,"barbarian_twister")
	sim.tick=barb.advanced_job.end_at;sim.Behaviors.AdvancedBarrack._job(sim,barb,t)
	check(barb.state=="idle2" and barb.advanced_job.is_empty(),"native twister returns to dual idle")
	sim.damage(barb,10000,1);var dead:int=barb.dead_at
	var duration:int=Anim.duration(battle.animations,Anim.key(t.render.sprites[0],"death"))
	sim.tick=dead+duration+40;await unit_frame(barb,"death",duration+40,"barbarian_corpse")
	check(battle.draw_list.any(func(d):return d.pos.distance_to(barb.pos)<0.1 and d.tint.a==1),"native barbarian corpse retains opacity")
	sim.tick=dead+sim.frames(t.health.dead_lifetime);sim.step()
	check(sim.unit_by_id(barb.id).is_empty(),"native barbarian corpse removed at source lifetime")
	sim.enemies.clear();sim.projectiles.clear()
	var tower:Dictionary=sim.tower_by_id("11")
	enemy=sim._spawn_enemy("enemy_troll",0);enemy.pos=tower.pos+Vector2(60,-20);enemy.node=60;enemy.hp=10000
	for index in [1,2,0]:
		sim.tick+=1000;tower.bfg.ts=[sim.tick,sim.tick,sim.tick];tower.bfg.ts[index]=0;tower.bfg.job={};tower.bfg.cursor=[2,0,1][index]
		sim.Behaviors.Bfg.step(sim,tower);check(not tower.bfg.job.is_empty(),"native BFG action starts %d"%index)
		if tower.bfg.job.is_empty():continue
		var end_at:int=tower.bfg.job.end_at
		sim.tick=tower.bfg.job.hit_at;sim.Behaviors.Bfg.step(sim,tower)
		await capture("eighth_bfg_fire%d"%index)
		check(not sim.projectiles.is_empty(),"native BFG projectile emitted %d"%index)
		sim.tick=end_at;sim.Behaviors.Bfg.step(sim,tower)
		check(tower.layers[2].state=="idle","native BFG shooter returns idle %d"%index)
		sim.projectiles.clear()
	sim.enemies.clear()
	var chief:Dictionary=sim._spawn_enemy("enemy_troll_chieftain",0);chief.pos=Vector2(535,400);chief.node=60;chief.hp-=100
	var troll:Dictionary=sim._spawn_enemy("enemy_troll_axe_thrower",0);troll.pos=Vector2(590,400);troll.node=60;troll.hp-=100
	sim.tick+=181;sim.Behaviors.Chieftain.step(sim,chief,sim.templates[chief.template])
	sim.tick=chief.rage_job.at;sim.Behaviors.Chieftain.step(sim,chief,sim.templates[chief.template])
	await unit_frame(chief,"special",sim.tick-chief.state_at,"chieftain_rage")
	check(sim.modifiers.has(chief.id,"mod_troll_rage") and sim.modifiers.has(troll.id,"mod_troll_heal"),"native chief buffs itself and nearby troll")
	await capture("eighth_rage_and_heal")
	sim.enemies.clear();sim.soldiers.clear();sim.effects.clear();sim.projectiles.clear();sim.tick+=100
	var yeti:Dictionary=sim._spawn_enemy("enemy_yeti",0);yeti.pos=Vector2(630,470);yeti.node=60
	var soldier:Dictionary=sim._soldier("soldier_militia","",0,yeti.pos+Vector2(30,0),yeti.pos+Vector2(30,0));soldier.hp=1000;soldier.armor=0
	yeti.blocker=soldier.id;yeti.blockers=[soldier.id];soldier.target=yeti.id
	sim._melee(yeti,soldier,sim.templates[yeti.template])
	sim.tick=yeti.mixed_melee_job.hit_at;sim.behaviors.enemy_step(sim,yeti,sim.templates[yeti.template])
	await unit_frame(yeti,"attack",sim.tick-yeti.state_at,"yeti_area")
	for effect:String in ["fx_ground_hit","decal_ground_hit"]:
		var ground:Dictionary=sim.effects.filter(func(e):return e.template==effect)[0]
		var sprite:Dictionary=sim.templates[effect].render.sprites[0]
		var frame:String=Anim.frame(sprite,battle.animations,{"elapsed":0,"loop":false})
		check(battle.draw_list.any(func(d):return d.frame==frame and d.pos.distance_to(ground.pos+sim.vec(sprite.get("offset",{"x":0,"y":0})))<0.01),"native yeti ground effect rendered "+effect)
	sim.tick=yeti.mixed_melee_job.end_at;sim.behaviors.enemy_step(sim,yeti,sim.templates[yeti.template])
	check(yeti.state=="idle" and yeti.playback_loop,"native yeti attack ends in looping idle")
	sim.enemies.clear();sim.effects.clear();sim.tick+=100;soldier.target=0
	var thrower:Dictionary=sim._spawn_enemy("enemy_troll_axe_thrower",0);thrower.pos=Vector2(570,470);thrower.node=60
	sim._enemy_step(thrower);sim.tick=thrower.ranged_cast.at;sim._enemy_step(thrower)
	await unit_frame(thrower,"shoot",sim.tick-thrower.state_at,"axe_thrower_shoot")
	check(sim.projectiles.any(func(p):return p.template=="axe_troll_axe_thrower"),"native enemy axe emitted at source shoot frame")
	sim.tick=thrower.ranged_cast.end;sim._enemy_step(thrower)
	check(thrower.state=="idle" and thrower.playback_loop,"native enemy ranged animation returns to idle")

func sasquash_frames() -> void:
	var sim=battle.sim
	var s:Dictionary=sim.soldiers.filter(func(unit):return unit.template=="soldier_sasquash")[0]
	s.pos=Vector2(420,470);s.dest=s.pos;s.rallying=false
	var enemy:Dictionary=sim._spawn_enemy("enemy_troll",0);enemy.pos=s.pos+Vector2(40,0);enemy.node=60;enemy.hp=10000
	var t:Dictionary=s.combat_template;var a:Dictionary=t.melee.attacks[0]
	sim.Behaviors.AdvancedBarrack._begin(sim,s,t,a,{"kind":"melee","target":enemy.id,"entity":enemy,"index":0},float(a.hit_time))
	sim.tick=s.advanced_job.hit_at;sim.Behaviors.AdvancedBarrack._job(sim,s,t)
	await unit_frame(s,"attack",sim.tick-s.state_at,"sasquash_attack")
	sim.tick=s.advanced_job.end_at;sim.Behaviors.AdvancedBarrack._job(sim,s,t)
	check(s.state=="idle" and s.advanced_job.is_empty(),"native Sasquatch attack returns idle")
	sim.damage(s,10000,1);var dead:int=s.dead_at
	var duration:int=Anim.duration(battle.animations,Anim.key(t.render.sprites[0],"death"))
	sim.tick=dead+duration+60;await unit_frame(s,"death",duration+60,"sasquash_corpse")
	check(battle.draw_list.any(func(d):return d.pos.distance_to(s.pos)<0.1 and d.tint.a==1),"native Sasquatch corpse retains opacity")
	sim.tick=dead+359;sim._tower_step(sim.tower_by_id("91"))
	check(sim.soldiers.filter(func(unit):return unit.template=="soldier_sasquash" and unit.hp>0).is_empty(),"native Sasquatch waits twelve seconds")
	var gold:int=sim.gold;sim.tick=dead+360;sim.step()
	check(sim.unit_by_id(s.id).is_empty() and sim.soldiers.any(func(unit):return unit.template=="soldier_sasquash" and unit.hp>0) and sim.gold==gold,"native Sasquatch corpse cleanup and free replacement")
	await capture("eighth_sasquash_respawn")

func _run() -> void:
	create_timer(240).timeout.connect(func():push_error("Eighth native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y];layout_only=OS.get_cmdline_user_args().has("--layout-only")
	app=AppScene.instantiate();app.settings_path="user://level08_native_settings.json";app.slots_path="user://level08_native_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,8):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(8,1);await capture("eighth_opening")
	check(battle.sim.gold==800 and battle.sim.snow.tunnels.size()==1,"native eighth source economy and tunnel")
	await menu("91");await hover(hit("frozen").rect.get_center());await capture("eighth_frozen_camp")
	check(hit("sell").is_empty() and hit("buy_soldier").is_empty(),"native frozen camp has no sale or hire")
	await new_tower("11","engineer","tower_bfg")
	await new_tower("09","barrack","tower_barbarian")
	if not layout_only:await runtime_frames()
	await restart();check(battle.sim.tower_by_id("91").template=="tower_sasquash_holder","native restart refreezes camp")
	await action("wave");await dismiss();await action("target",{"power":"fire"});await click(battle.world(battle.sim.tower_by_id("91").pos))
	check(battle.sim.cooldowns.fire>0,"native fire input accepts frozen camp")
	for i in 120:
		await dismiss();battle.sim.step()
		if battle.sim.tower_by_id("91").template=="tower_sasquash":break
	await menu("91");await capture("eighth_thawed_camp")
	check(battle.sim.tower_by_id("91").template=="tower_sasquash" and hit("sell").is_empty(),"native actual fire thaws non-sale camp")
	await action("buy_soldier",{"id":"91","type":"soldier_sasquash"});battle.sim._tower_step(battle.sim.tower_by_id("91"))
	await capture("eighth_sasquash_hired")
	check(battle.sim.soldiers.any(func(s):return s.template=="soldier_sasquash"),"native paid Sasquatch hire")
	if not layout_only:
		await sasquash_frames()
		battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false)
		await capture("eighth_victory");await action("map");await app.map_ready
		check("tower_bfg" not in app.campaign.data.locked_towers and "tower_barbarian" not in app.campaign.data.locked_towers and not app.campaign.is_playable(9),"native result commits new towers and ninth preview")
		for mode in [2,3]:
			await enter(8,mode);await capture("eighth_mode%d"%mode)
			check(battle.sim.gold==[1100,1200][mode-2] and battle.sim.lives==1,"native source challenge economy %d"%mode)
			if mode==3:
				await menu("11");check(battle.hits.filter(func(h):return h.action=="build").size()==2,"native Iron two allowed build types")
			battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await action("map");await app.map_ready
			check(app.campaign.record(8).get(mode,0)==2,"native eighth challenge settlement %d"%mode)
	var hashes:Dictionary={}
	for path:String in ["tests/level08_visual.gd","tests/level07_visual.gd","tests/challenges_visual.gd","tests/tower_upgrade_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_bfg.gd","scripts/battle/dove_advanced_barrack.gd","scripts/battle/dove_chieftain.gd","scripts/battle/dove_sasquash.gd","scripts/battle/dove_enemy_melee.gd","scripts/battle/dove_enemy_ranged.gd","scripts/battle/level01_sim.gd","data/level08/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level08_native_%s.json"%suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"layout_only":layout_only,"source_hashes":hashes,"scope":"native Godot input, advanced tower skills and animation endpoints, camp fire/hire, chief effects, restart and constructed settlement; no victory replay"})
	print("LEVEL08_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
