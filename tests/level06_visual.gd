extends "res://tests/challenges_visual.gd"
## Native viewport/input checks using fixtures, never a challenge victory search.
func menu(id: String = "8") -> void:
	var tower: Dictionary = battle.sim.tower_by_id(id)
	# Roof selection avoids clicking a newly emerging garrison soldier.
	await draw_frame(); await click(battle.world(tower.pos + Vector2(0, 32 if tower.type != "" else 0)))
	await create_timer(0.15).timeout; await draw_frame()
	check(battle.selected == id, "native tower selection " + id)
func back() -> void:
	await action("pause"); await action("map"); await app.map_ready
func advanced(id: String, kind: String, target: String, powers: Array) -> void:
	battle.sim.gold = 10000
	await menu(id); await action("build", {"id":id,"type":kind})
	for i in 30: battle.sim.step()
	for tier in 3:
		await menu(id); await action("upgrade")
	check(battle.sim.tower_by_id(id).template == target,"native advanced upgrade " + target)
	for power: String in powers:
		for level in int(battle.sim.templates[target].powers[power].max_level):
			await menu(id); await action("upgrade_power", {"id":id,"power":power})
		await menu(id); await hover(hit("upgrade_power", {"id":id,"power":power}).rect.get_center())
		await capture("sixth_" + power)
	check(battle.interface.paint.audit.all(func(row): return row.fits), "advanced tower text fits " + target)
func _run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Sixth native timeout"); quit(1))
	suffix="%dx%d" % [root.size.x,root.size.y]
	app=AppScene.instantiate(); app.settings_path="user://level06_native_settings.json"; app.slots_path="user://level06_native_%d.progress" % Time.get_ticks_usec(); root.add_child(app)
	await app.menu_ready; app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in range(1,6): Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(6,1); await capture("sixth_campaign_guards")
	check(battle.sim.soldiers.size()==7,"seven native imperial guards")
	await advanced("1","barrack","tower_paladin",["healing","holystrike","shield"])
	await advanced("2","mage","tower_arcane_wizard",["disintegrate","teleport"])
	for i in 90: battle.sim.step()
	var paladins: Array = battle.sim.soldiers.filter(func(s):return s.home=="1" and s.hp>0)
	var caster: Dictionary = paladins[0]
	caster.rallying=false; caster.hp=170; battle.sim.tick=400
	battle.sim.Behaviors.Paladin.step(battle.sim,caster,battle.sim.templates.soldier_paladin)
	check(caster.state=="healing","native healing animation starts")
	battle.sim.tick+=8; await capture("sixth_healing_action")
	battle.sim.tick+=30; caster.healing_cast={}; caster.pending={}; caster.melee_end=0
	var knight: Dictionary=battle.sim._spawn_enemy("enemy_dark_knight",0)
	knight.pos=caster.pos+Vector2(22,0)
	battle.sim.templates.soldier_paladin.melee.attacks[2].chance=1.0
	battle.sim.Behaviors.Paladin.melee(battle.sim,caster,knight,battle.sim.templates.soldier_paladin)
	battle.sim.tick+=15; battle.sim.Behaviors.Paladin.melee(battle.sim,caster,knight,battle.sim.templates.soldier_paladin)
	await capture("sixth_holystrike_action")
	battle.sim.modifiers.apply(battle.sim,"mod_ray_arcane_disintegrate",knight,3,"2")
	battle.sim.tick+=5; battle.sim.modifiers.step(battle.sim)
	await capture("sixth_disintegrate_action")
	battle.selected=""; battle.hovered=""; battle.message_time=0
	var flying: Dictionary=battle.sim._spawn_enemy("enemy_gargoyle",0)
	flying.pos=Vector2(550,270); flying.node=50
	var boss: Dictionary=battle.sim._spawn_enemy("eb_juggernaut",0,4)
	boss.pos=Vector2(780,400);boss.node=70
	battle.sim.Behaviors.Spawner.insert(battle.sim,{"template":"juggernaut_bomb_spawner","pos":Vector2(700,400),"owner":boss.id,"level":1})
	battle.sim.auras.append({"template":"aura_teleport_arcane","pos":Vector2(540,300),"source":"2","level":3,"at":battle.sim.tick,"next":battle.sim.tick+5,"victims":0,"max":6})
	battle.sim.command("wave");await dismiss();await capture("sixth_boss_flight_skills")
	check(app.audio.music_player.playing,"native battle/boss music active")
	check(battle.draw_list.any(func(d):return d.frame=="decal_flying_shadow"),"native flying shadow")
	check(battle.draw_list.any(func(d):return d.frame.begins_with("bossJuggernaut_bombDecal")),"native spawner render")
	await restart();check(battle.sim.soldiers.size()==7 and battle.sim.wave==0 and battle.sim.tower_by_id("1").type=="","native restart isolates advanced templates")
	battle.sim._finish("victory"); await capture("sixth_campaign_victory")
	check(app.campaign.data.last_victory.level_idx==6,"native sixth pending settlement")
	await action("map");await app.map_ready
	check(app.campaign.record(6).stars==3 and app.campaign.is_playable(6,2) and app.campaign.is_playable(6,3) and app.campaign.is_playable(7),"native sixth settlement unlocks challenges, seventh playable")
	for mode in [2,3]:
		await enter(6,mode);await capture("sixth_mode%d_opening" % mode)
		check(battle.sim.soldiers.size()==(7 if mode==2 else 0),"native mode guard layout %d" % mode)
		if mode==3:
			check(battle.sim.towers.filter(func(t):return t.template=="tower_mage_3" and t.spent==0).size()==2,"native steel two free mage3")
			await menu("1");check(battle.hits.filter(func(h):return h.action=="build").size()==1,"native steel only barrack build")
			await menu("8");check(not hit("upgrade").is_empty(),"native steel free mage upgrades to arcane")
			await capture("sixth_steel_upgrade")
		battle.sim._finish("victory");await capture("sixth_mode%d_victory" % mode)
		await action("map");await app.map_ready
		check(app.campaign.record(6).get(mode,0)==2,"native sixth challenge settlement %d" % mode)
	var f=FileAccess.open("res://reports/level06_native.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"scope":"native three-mode entry, tower/skill input, restart and finish-event settlement; fixtures are not full victory replays"},"\t"));f.close()
	print("LEVEL06_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
