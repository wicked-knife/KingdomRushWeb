extends "res://tests/level09_visual.gd"
## Bounded native fixtures, actual input and render queue; no victory replay.
func enter(id:int,mode:int) -> void:
	print("ELEVENTH_ENTER ",mode)
	app.campaign_map.camera_offset=Vector2.ZERO
	await map_action("level",{"id":id})
	await map_action("mode",{"mode":mode,"reason":"战役获得三星后开放挑战"})
	await map_capture("level%d_mode%d"%[id,mode])
	print("ELEVENTH_MAP_INPUT ",mode)
	await map_action("battle")
	print("ELEVENTH_BATTLE_INPUT ",mode)
	battle=app.battle
	check(battle!=null and battle.sim.data.level.id==id and battle.sim.data.level.mode==mode,"native actual identity")
	battle.set_process(false);await dismiss()
	print("ELEVENTH_DISMISSED ",mode)

func settle11(result:String="victory") -> void:
	battle.sim._finish(result);battle.set_process(true)
	await create_timer(4.2).timeout;battle.set_process(false)
	await capture("eleventh_"+result+"_mode%d"%battle.sim.data.level.mode)
	await action("map");await app.map_ready

func actor11(unit:Dictionary,state:String,label:String) -> void:
	await capture(label)
	var sprite:Dictionary=battle.sim.unit_template(unit).render.sprites[0]
	var expected:String=Anim.frame(sprite,battle.animations,{"state":state,"elapsed":battle.sim.tick-unit.state_at,"loop":unit.get("playback_loop",false)})
	check(battle.draw_list.any(func(d):return d.frame==expected),"source frame "+label+" "+expected)

func actors11() -> void:
	var sim=battle.sim
	sim.enemies.clear();sim.soldiers.clear();sim.spawn_queue.clear()
	var necro:Dictionary=sim._spawn_enemy("enemy_necromancer",0)
	necro.node=40;necro.pos=Vector2(500,350)
	for n in range(241,258):sim.tick=n;sim.behaviors.enemy_step(sim,necro,sim.templates.enemy_necromancer)
	await actor11(necro,"summon","eleventh_summon")
	for n in range(258,262):sim.tick=n;sim.behaviors.enemy_step(sim,necro,sim.templates.enemy_necromancer)
	check(sim.enemies.size()>1,"native source summon produces child")
	var child:Dictionary=sim.enemies[-1];child.hp-=10
	await actor11(child,"raise","eleventh_skeleton_raise")
	check(child.health_bar_hidden,"raise hides damaged child health bar")
	sim.tick=int(child.raise_until);sim._enemy_step(child)
	await actor11(child,child.state,"eleventh_skeleton_walk")
	check(child.state!="raise" and not child.health_bar_hidden,"raise ends and restores health bar")
	sim.enemies.clear();sim.tick=500
	var guard:Dictionary=sim._soldier("soldier_militia","",0,Vector2(650,350),Vector2(650,350));guard.hp=10000
	sim._projectile("bolt_necromancer",guard.id,Vector2(500,372),guard.pos+Vector2(0,13),1)
	var bolt:Dictionary=sim.projectiles[-1]
	for n in range(501,506):sim.tick=n;sim._bullet_step(bolt)
	await capture("eleventh_bolt")
	check(not bolt.done and battle.draw_list.any(func(d):return "necromancer" in d.frame),"native enemy magic bolt visible")
	for n in range(506,560):
		sim.tick=n
		if not bolt.done:sim._bullet_step(bolt)
	await capture("eleventh_bolt_end")
	check(bolt.done and guard.hp<10000,"native bolt damages and ends")
	sim.projectiles.clear();sim.enemies.clear();sim.soldiers.clear();sim.tick=12000;sim.wave=1
	sim.layout_spawners[0].next=12001
	sim.tick=12001;sim.Behaviors.Spawner.step_layout(sim)
	var lava:Dictionary=sim.enemies[-1]
	await actor11(lava,"raise","eleventh_lava_raise")
	check(lava.pos==Vector2(498,383) and lava.path==3,"native generator source location and path")
	check(battle.sound_cache.has("RockElementalDeath"),"generator source audio resolves")
	sim.tick=int(lava.raise_until);sim._enemy_step(lava)
	await actor11(lava,lava.state,"eleventh_lava_walk")
	check(lava.state!="raise","lava rise ends into forced movement")
	lava.erase("forced_waypoint");lava.pos=Vector2(550,350)
	guard=sim._soldier("soldier_militia","",0,Vector2(580,350),Vector2(580,350));guard.hp=10000
	lava.blocker=guard.id;lava.blockers=[guard.id];guard.target=lava.id
	sim._melee(lava,guard,sim.templates.enemy_lava_elemental)
	sim.tick+=15;sim.Behaviors.EnemyMelee.step(sim,lava,sim.templates.enemy_lava_elemental)
	await actor11(lava,"attack","eleventh_lava_attack")
	check(guard.hp<10000,"native lava area hit")
	for name:String in ["enemy_lava_elemental","enemy_necromancer"]:
		sim.enemies.clear()
		var corpse:Dictionary=sim._spawn_enemy(name,0);corpse.pos=Vector2(550,350)
		sim.damage(corpse,100000,1);sim.tick+=10
		await actor11(corpse,"death","eleventh_"+name+"_death")
		sim.tick=corpse.dead_at+Anim.duration(sim.animations,Anim.key(sim.templates[name].render.sprites[0],"death"))+1
		await actor11(corpse,"death","eleventh_"+name+"_hold")
		check(battle.draw_list.any(func(d):return d.pos==corpse.pos and d.tint.a==1),"source corpse holds full alpha "+name)
		sim.tick=corpse.dead_at+sim.frames(sim.templates[name].health.dead_lifetime);sim.step()
		check(sim.unit_by_id(corpse.id).is_empty(),"source corpse entity removed "+name)

func _run() -> void:
	create_timer(45).timeout.connect(func():root.get_texture().get_image().save_png("res://output/level11_native_debug.png");print("NATIVE_STATE ",app.transitioning," battle=",app.battle!=null))
	create_timer(180).timeout.connect(func():push_error("Eleventh native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y]
	app=AppScene.instantiate();app.settings_path="res://output/level11_native_settings.json";app.slots_path="res://output/level11_native_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,11):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	for id:String in app.campaign.selected_hero_ids().duplicate():app.campaign.deselect_hero(id)
	check(app.campaign.select_hero("hero_malik"),"selected Malik saved")
	await enter(11,1);await capture("eleventh_opening")
	check(battle.sim.gold==1300 and battle.sim.towers.size()==18,"native source campaign opening")
	check(battle.sim.soldiers.any(func(s):return s.template=="hero_malik"),"native campaign Malik enters")
	await menu("1");await action("build",{"id":"1","type":"mage"})
	await action("wave");await dismiss()
	check(battle.sim.unlocked.fire and battle.sim.unlocked.reinforcements,"first wave opens powers")
	await action("target",{"power":"reinforcements"})
	await click(battle.world(battle.sim.tower_by_id("1").rally))
	check(battle.sim.cooldowns.reinforcements>0,"native reinforcement input")
	await actors11()
	await restart();check(battle.sim.wave==0 and battle.sim.layout_spawners[0].next==-1,"native restart resets generator")
	await settle11()
	check(app.campaign.is_playable(11,2) and app.campaign.is_playable(11,3) and not app.campaign.is_playable(12),"settlement opens challenges and twelfth preview")
	for mode in [2,3]:
		await enter(11,mode);await capture("eleventh_mode%d"%mode)
		check(battle.sim.gold==[2100,2600][mode-2] and battle.sim.lives==1,"native challenge source economy %d"%mode)
		check(battle.sim.soldiers.any(func(s):return s.template=="hero_malik"),"native challenge Malik allowed %d"%mode)
		if mode==3:
			await menu("1")
			var kinds:Array=battle.hits.filter(func(h):return h.action=="build").map(func(h):return h.args.type)
			check(kinds.size()==2 and "mage" in kinds and "barrack" in kinds,"iron source construction bans")
		await settle11();check(app.campaign.record(11).get(mode,0)==2,"native challenge persists %d"%mode)
	await enter(11,3);await settle11("defeat")
	check(app.campaign.record(11).get(3,0)==2,"defeat preserves settled best score")
	var hashes:Dictionary={}
	for path:String in ["tests/level11_visual.gd","scripts/battle/battle_view.gd","scripts/battle/dove_necromancer.gd","scripts/battle/dove_spawner.gd","scripts/battle/dove_enemy_ranged.gd","scripts/battle/dove_enemy_projectiles.gd","scripts/battle/level01_sim.gd","data/level11/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level11_native_%s.json"%suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes,"full_replays":false,"native_input":true,"native_audio":true,"scope":"three mode entry, source actor lifecycle/render queue, generator, build/spell input, restart and constructed result persistence"})
	print("LEVEL11_NATIVE: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
