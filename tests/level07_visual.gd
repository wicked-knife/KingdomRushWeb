extends "res://tests/challenges_visual.gd"
func menu(id: String = "1") -> void:
	var tower: Dictionary=battle.sim.tower_by_id(id)
	await draw_frame();await click(battle.world(tower.pos+Vector2(0,32 if tower.type!="" else 0)))
	await create_timer(0.15).timeout;await draw_frame()
	check(battle.selected==id,"native tower selection "+id)
func _run() -> void:
	create_timer(180).timeout.connect(func():push_error("Seventh native timeout");quit(1))
	suffix="%dx%d" % [root.size.x,root.size.y]
	layout_only=OS.get_cmdline_user_args().has("--layout-only")
	app=AppScene.instantiate();app.settings_path="user://level07_native_settings.json";app.slots_path="user://level07_native_%d.progress" % Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,7):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(7,1);await capture("seventh_snow_opening")
	check(battle.sim.snow.tunnels.size()==2 and battle.sim.snow.particles.size()>100,"native snowfall and source tunnel layouts")
	battle.sim.gold=10000
	await menu();await action("build",{"id":"1","type":"archer"})
	for i in 30:battle.sim.step()
	for target in ["tower_archer_2","tower_archer_3"]:
		await menu();await action("upgrade",{"id":"1","upgrade_to":target})
	await menu();await capture("seventh_branches")
	check(battle.hits.any(func(h):return h.action=="upgrade" and h.args.get("upgrade_to","")=="tower_musketeer"),"native Musketeer source branch slot")
	check(battle.hits.any(func(h):return h.action=="locked" and h.args.get("upgrade_to","")=="tower_ranger"),"native separate Ranger saved lock")
	await hover(hit("upgrade",{"id":"1","upgrade_to":"tower_musketeer"}).rect.get_center());await capture("seventh_musketeer_tooltip")
	await action("upgrade",{"id":"1","upgrade_to":"tower_musketeer"})
	for power in ["sniper","shrapnel"]:
		await menu();await action("upgrade_power",{"id":"1","power":power})
		await menu();await hover(hit("upgrade_power",{"id":"1","power":power}).rect.get_center());await capture("seventh_power_"+power)
	check(battle.sim.tower_by_id("1").powers.sniper==1 and battle.sim.tower_by_id("1").powers.shrapnel==1,"native power transaction input")
	if not layout_only:
		battle.selected="";battle.hovered="";battle.pointer=Vector2(50,200);battle.sim.paused=false
		await create_timer(0.2).timeout;await draw_frame()
		var tower: Dictionary=battle.sim.tower_by_id("1")
		var target: Dictionary=battle.sim._spawn_enemy("enemy_troll",0);target.pos=tower.pos+Vector2(80,-55);target.node=50;target.hp=1000;target.max_hp=1000
		battle.sim.tick=500;tower.musketeer.ts=[500,0,0,500];tower.musketeer.cursor=0;tower.musketeer.job={}
		battle.sim.templates.tower_musketeer.powers.sniper.instakill_chance_inc=0
		battle.sim.Behaviors.Musketeer.step(battle.sim,tower)
		battle.sim.tick+=10;await capture("seventh_sniper_aim")
		check(battle.draw_list.any(func(d):return d.frame.begins_with("Halloween_hero_vhelsing_sniper")),"native source crosshair frame")
		battle.sim.tick+=12;battle.sim.Behaviors.Musketeer.step(battle.sim,tower);await capture("seventh_sniper_shot")
		check(not battle.draw_list.any(func(d):return d.frame.begins_with("Halloween_hero_vhelsing_sniper")),"native crosshair expires after source duration")
		for i in 3:
			battle.sim.tick+=1
			if not battle.sim.projectiles[0].done:battle.sim._bullet_step(battle.sim.projectiles[0])
		await capture("seventh_sniper_trail")
		battle.sim.projectiles.clear();battle.sim.tick=600;tower.musketeer.job={};tower.musketeer.cursor=2;tower.musketeer.ts=[600,600,600,0]
		battle.sim.Behaviors.Musketeer.step(battle.sim,tower);battle.sim.tick+=16;battle.sim.Behaviors.Musketeer.step(battle.sim,tower)
		await capture("seventh_shrapnel_fire")
		check(battle.sim.projectiles.size()==6,"native six shrapnel shells")
		battle.sim.tick+=30;battle.sim.Behaviors.Musketeer.step(battle.sim,tower);await capture("seventh_shrapnel_finished")
		check(tower.layers.values().all(func(layer):return not layer.has("draw_order")),"temporary shooter drawing order restored")
		battle.sim.enemies.clear();battle.sim.projectiles.clear()
		var traveller: Dictionary=battle.sim._spawn_enemy("enemy_troll",1,1);traveller.node=79;traveller.progress=79;traveller.pos=battle.sim.vec(battle.sim.data.paths.paths[1][1][79])
		battle.sim.snow.step(battle.sim);await capture("seventh_tunnel_inside")
		check(battle.sim.snow.occupied() and battle.draw_list.any(func(d):return "cave_light" in d.frame or "caveLight" in d.frame),"native cave occupied light")
		battle.sim.tick=ceili(battle.sim.snow.tunnels[0].queue[0].release);battle.sim.snow.step(battle.sim);await capture("seventh_tunnel_exit")
		check(traveller.path==3 and traveller.subpath==1,"native actual tunnel reinsertion")
		battle.sim.enemies.clear()
		var wolf: Dictionary=battle.sim._spawn_enemy("enemy_whitewolf",0);wolf.pos=Vector2(550,400);wolf.node=50
		battle.sim.damage(wolf,99999,1);battle.sim.tick+=12;await capture("seventh_whitewolf_death")
		var duration: int=battle.SpriteAnimation.duration(battle.animations,battle.SpriteAnimation.key(battle.sim.templates.enemy_whitewolf.render.sprites[0],"death"))
		battle.sim.tick=wolf.dead_at+duration;await capture("seventh_whitewolf_hidden")
		check(not battle.draw_list.any(func(d):return d.frame.begins_with("winterwolf")),"whitewolf hidden at source animation end")
		battle.sim.tick=wolf.dead_at+battle.sim.frames(battle.sim.templates.enemy_whitewolf.health.dead_lifetime);battle.sim.step()
		check(battle.sim.unit_by_id(wolf.id).is_empty(),"whitewolf entity removed at corpse lifetime")
		var goat: Dictionary=battle.sim.decals[0]
		for i in 8:await click(battle.world(goat.pos+Vector2(0,4)))
		check(goat.removed,"native goat eight-click interaction")
		await restart();check(not battle.sim.snow.occupied() and battle.sim.wave==0,"native restart clears tunnel and skills")
		battle.sim.command("wave");await dismiss();await draw_frame()
		check(app.audio.music_player.playing,"native source stage music plays")
		battle.sim._finish("victory")
		check("tower_musketeer" in app.campaign.data.locked_towers,"native victory leaves unlock pending")
		battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false)
		await capture("seventh_victory");await action("map");await app.map_ready
		check(not "tower_musketeer" in app.campaign.data.locked_towers and app.campaign.is_playable(7,2) and not app.campaign.is_playable(8),"native map commits unlock and keeps eighth preview")
		for mode in [2,3]:
			await enter(7,mode);await capture("seventh_mode%d" % mode)
			if mode==3:
				check(battle.sim.towers.filter(func(t):return t.template=="tower_barrack_2" and t.spent==0).size()==3,"native Iron free barracks")
				await menu();check(battle.hits.filter(func(h):return h.action=="build").size()==2,"native Iron two allowed build types")
			battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await action("map");await app.map_ready
			check(app.campaign.record(7).get(mode,0)==2,"native challenge settlement %d" % mode)
	var hashes := {}
	for path in ["tests/level07_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_musketeer.gd","scripts/battle/dove_snow.gd","data/level07/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	if not preload("res://tests/report_writer.gd").json_file("res://reports/level07_native_%s.json" % suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"layout_only":layout_only,"source_hashes":hashes,"scope":"native Godot input, source animation keyframes and endings, cave light/reinsertion, snow, goat, stage music and constructed-result settlement; no victory replay"}):quit(1);return
	print("LEVEL07_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
