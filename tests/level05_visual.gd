extends "res://tests/tower_upgrade_visual.gd"
const Fixture = preload("res://tests/slot_fixture.gd")
const AppScene = preload("res://scenes/app_root.tscn")
const Replay = preload("res://tests/level05_playback.gd")
var app: Control
var checked_third_entrance := false
var sound_events: Array = []
func capture(label: String) -> void:
	await draw_frame(); await create_timer(0.4).timeout
	await super.capture(label)
func drive(kind: String,args: Dictionary = {}) -> void: battle._action(kind,args)
func camp_ui() -> void:
	await menu("5"); await hover(hit("upgrade").rect.get_center()); await capture("level05_elf_repair")
	await action("upgrade"); check(battle.sim.gold == 510 and battle.sim.tower_by_id("5").hired == 0,"native repair empty camp")
	for i in range(2):
		await menu("5"); await action("buy_soldier")
	check(battle.sim.gold == 310 and battle.sim.tower_by_id("5").hired == 2,"native recruit two paid slots")
	for i in range(60): battle.sim.step()
	for power in ["bleed","cripple"]:
		await menu("5"); await hover(hit("upgrade_power",{"id":"5","power":power}).rect.get_center())
		await capture("level05_elf_" + power); await action("upgrade_power",{"id":"5","power":power})
	check(battle.sim.gold == 10,"native source skill prices")
	await menu("5"); check(not hit("buy_soldier").enabled,"insufficient money disables recruit")
	battle.sim.gold = 10000 # Isolated UI/animation fixture, never the legal campaign replay.
	for i in range(2): await menu("5"); await action("buy_soldier")
	for i in range(60): battle.sim.step()
	await menu("5"); check(not hit("buy_soldier").enabled,"native reserved four-slot cap")
	for power in ["bleed","cripple"]:
		for i in range(2): await menu("5"); await action("upgrade_power",{"id":"5","power":power})
		await menu("5"); check(not hit("upgrade_power",{"id":"5","power":power}).enabled,"native skill maximum")
	await capture("level05_elf_maximum")
	await action("target",{"power":"rally"}); await click(battle.world(Vector2(450,565)))
	check(battle.sim.tower_by_id("5").rally != Vector2(346,541),"native rally changes camp")
	if OS.get_cmdline_user_args().has("--layout-only"): return
	var sim: RefCounted = battle.sim
	var e: Dictionary = sim._spawn_enemy("enemy_brigand",1,0)
	e.pos = Vector2(440,570); e.hp = 10000; e.max_hp = 10000
	var mother: Dictionary = sim._spawn_enemy("enemy_spider_big",1,2)
	mother.pos = Vector2(650,550); mother.egg_at = sim.tick
	var images: Array = []; var saw_bleed := false; var saw_cripple := false; var saw_egg := false; var saw_baby := false
	for i in range(260):
		sim.tick += 1; sim.modifiers.step(sim); sim.Spider.lay(sim,mother); sim.Spider.step(sim)
		for tower: Dictionary in sim.towers: sim._tower_step(tower)
		for soldier: Dictionary in sim.soldiers: sim._soldier_step(soldier)
		for p: Dictionary in sim.projectiles: sim._bullet_step(p)
		sim.projectiles = sim.projectiles.filter(func(p): return not p.done)
		sim.effects = sim.effects.filter(func(f): return sim.tick - f.at < f.duration)
		saw_bleed = saw_bleed or sim.modifiers.has(e.id,"mod_elf_bleed")
		saw_cripple = saw_cripple or sim.modifiers.has(e.id,"mod_elf_cripple")
		saw_egg = saw_egg or not sim.eggs.is_empty()
		saw_baby = saw_baby or sim.enemies.any(func(u): return u.template == "enemy_spider_tiny")
		if i % 10 == 0:
			await draw_frame(); images.append(crop(Vector2(440,570)))
			check(battle.draw_list.all(func(d): return not battle._frame(d.frame).is_empty()),"elf/egg animation frames resolve")
		if i in [10,50,120,230]: await capture("level05_elf_combat_" + str(i))
	check(saw_bleed and saw_cripple and saw_egg and saw_baby,"native elf effects and spider lifecycle")
	contact_sheet(images,"level05_elf",7)
func _run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Level five native timeout"); quit(1))
	suffix = "%dx%d" % [root.size.x,root.size.y]
	app = AppScene.instantiate(); app.settings_path = "user://level05_visual_settings.json"; app.slots_path = "user://level05_visual_%d.progress" % Time.get_ticks_usec(); root.add_child(app)
	await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	for id in range(1,5): Fixture.complete(app.campaign, {"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	check(app.campaign.is_playable(5),"native settled fourth slot opens fifth")
	app.campaign_map._action("level",{"id":5}); app.campaign_map._action("battle")
	battle = app.battle; battle.set_process(false); battle.sim.reset(42)
	battle.sim.event.connect(func(kind,payload):
		if kind == "sound" and not sound_events.has(payload.id): sound_events.append(payload.id))
	var prep: Dictionary = battle.catalog.get_sound(battle.sim.data.level.prep_music)
	check(battle.audio.music_player.playing and battle.audio.music_player.stream.resource_path == prep.paths[0],"native fifth preparation music")
	check(battle.sim.towers.size() == 14 and battle.sim.notices == ["TOWER_RANGER"],"native fifth initial placements and notice")
	await capture("level05_opening"); expect_text("新防御塔"); await dismiss()
	check(battle.sim.data.locations.entrances.size() == 3,"three mapped native entrances")
	for path in [1,2]: check(not hit("wave",{"path":path}).is_empty(),"initial active entrance " + str(path))
	await capture("level05_setup"); await camp_ui()
	for id in ["ElfTaunt","GUITowerOpenDoor"]:
		check(sound_events.has(id) and battle.sound_cache.has(id) and battle.sound_cache[id].streams.all(func(s): return s != null),"native camp audio " + id)
	if not OS.get_cmdline_user_args().has("--layout-only"):
		battle._action("restart"); battle.sim.reset(42)
		for i in range(60000):
			Replay.commands(battle.sim,drive)
			if battle.sim.wave == 2 and battle.sim.can_send_wave() and not checked_third_entrance:
				await draw_frame(); check(not hit("wave",{"path":3}).is_empty(),"third entrance active for wave three")
				await capture("level05_third_entrance")
				checked_third_entrance = true
			if i in [1800,5000,10000,15000]: await capture("level05_campaign_" + str(i))
			battle.sim.step()
			if battle.sim.result != "": break
		check(battle.sim.result == "victory" and battle.sim.lives == int(Replay.outcome.lives) and not battle.sim.developer_used,"native legal campaign victory")
		check(app.campaign.data.last_victory.level_idx == 5 and not app.campaign.is_unlocked(6),"native fifth victory waits for map settlement")
		check(battle.sound_cache.has("GUIQuestCompleted"),"native fifth victory fanfare")
		await capture("level05_victory")
		battle._action("restart"); await dismiss(); battle._action("wave")
		for i in range(20000):
			battle.sim.step()
			if battle.sim.result != "": break
		check(battle.sim.result == "defeat","native fifth no-purchase defeat"); await capture("level05_defeat")
		for id in ["ArrowSound","MeleeSword","GUILooseLife"]: check(sound_events.has(id) and battle.sound_cache.has(id),"native campaign audio " + id)
	var old: WeakRef = weakref(battle); battle._action("map"); await app.map_ready; await process_frame
	check(old.get_ref() == null and app.battle == null,"native map return frees fifth")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"sampled_frames":sampled_frames,"sound_events":sound_events}
	var f := FileAccess.open("res://reports/level05_visual_"+suffix+".json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("LEVEL05_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," ",suffix," checks=",checks)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
