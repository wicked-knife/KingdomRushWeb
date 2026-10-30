extends "res://tests/challenges_visual.gd"
var room: Control
func room_action(kind: String) -> void:
	room.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	var entries: Array=room.hits.filter(func(h):return h.action==kind)
	check(not entries.is_empty(),"hero room action "+kind)
	if entries.is_empty():return
	var point: Vector2=root.get_screen_transform()*room.get_global_transform_with_canvas()*(entries[0].rect.get_center()*room.zoom)
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new();input.position=point;input.button_index=MOUSE_BUTTON_LEFT;input.pressed=pressed
		Input.parse_input_event(input);await process_frame
func hero_frame() -> String:
	for d: Dictionary in battle.draw_list:
		if d.frame.begins_with("hero_reinforce_") and d.frame.get_slice_count("_")==3:return d.frame
	return ""
func ticks(count: int) -> void:
	for i in count:battle.sim.step()
func source_attack(index: int,h: Dictionary,target: Dictionary) -> void:
	var sim=battle.sim;var attack: Dictionary=sim.templates.hero_malik.melee.attacks[index]
	h.target=target.id;target.blockers=[h.id];target.blocker=h.id;h.flip=false
	h.hero_phase="attack";h.pending={"index":index,"target":target.id,"started":sim.tick,"at":sim.tick+sim.source_wait_ticks(sim.tick,float(attack.hit_time)),"resolved":false}
	h.busy_until=sim.tick+sim.Heroes.animation_ticks(sim,h,attack.animation);sim._state(h,attack.animation,true)
	if attack.has("xp_from_skill"):sim.Heroes.gain_skill_xp(h,attack.xp_from_skill)
	if attack.get("sound","")!="":sim.event.emit("sound",{"id":attack.sound})
func _run() -> void:
	create_timer(160).timeout.connect(func():push_error("Malik native timeout");quit(1))
	suffix="%dx%d" % [root.size.x,root.size.y]
	app=AppScene.instantiate();app.settings_path="user://malik_native_settings.json";app.slots_path="user://malik_native_%d.progress" % Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,4):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await map_action("heroes");room=app.campaign_map.hero_room
	while not room.loader.loaded:await process_frame
	for id: String in app.campaign.selected_hero_ids().duplicate():room.show_hero(id);await room_action("deselect")
	room.show_hero("hero_malik");await room_action("select");await room_action("close")
	check(app.campaign.selected_hero_ids()==["hero_malik"],"native hero room selection persists")
	await enter(3,1)
	var sim=battle.sim;var h: Dictionary=sim.soldiers.filter(func(s):return s.has("hero"))[0]
	sim.reset(42);h=sim.soldiers.filter(func(s):return s.has("hero"))[0]
	await capture("malik_intro")
	check(h.hero.level==1 and h.health_bar_hidden and hero_frame()=="hero_reinforce_0108","source initial levelup animation and hidden health bar")
	check(battle.sound_cache.has("HeroReinforcementTauntIntro"),"intro source audio resolved")
	ticks(24);await capture("malik_idle")
	check(h.hero_phase=="active" and not h.health_bar_hidden and hero_frame()=="hero_reinforce_0001","intro returns to source idle")
	await action("hero_select",{"id":h.id});check(battle.targeting=="hero","native portrait selects movement")
	await click(battle.world(Vector2(100,600)))
	check(battle.targeting=="hero" and battle.invalid_point_time>0,"invalid hero location retains selection")
	var dest: Vector2=sim.vec(sim.data.paths.paths[0][0][119])
	await click(battle.world(dest));check(battle.targeting=="" and h.hero_move_pending,"native valid move command")
	ticks(7);await capture("malik_running")
	var first:=hero_frame();ticks(5);await draw_frame()
	check(first==hero_frame() and h.playback_loop,"source running animation loops every five frames")
	for i in 600:
		if h.hero_phase!="moving":break
		sim.step()
	check(h.pos.is_equal_approx(dest) and h.hero_phase=="active" and h.move_immune==0,"source waypoints end at commanded destination")
	await click(battle.world(h.pos+Vector2(0,10)));check(battle.targeting=="hero","native battlefield hero click selects movement")
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=root.get_screen_transform()*(battle.world(h.pos)*battle.zoom)
	Input.parse_input_event(right);await process_frame;check(battle.targeting=="","right click cancels hero command")
	# Neighbouring tower/power menus still receive actual engine input.
	sim.gold=1000;await menu("1");await action("build",{"id":"1","type":"barrack"})
	check(sim.tower_by_id("1").type=="barrack","hero HUD preserves tower input")
	battle.selected="";battle.selected_unit=0
	h.hp=100;h.hero.xp_queued=2000;sim.heroes.step(sim,h);await capture("malik_levelup")
	check(h.hero.level==2 and h.hero_phase=="levelup" and h.hp==500 and battle.sound_cache.has("HeroLevelUp"),"combat XP levels up, heals and starts source animation/audio")
	ticks(24)
	for level in range(1,11):h.hero.level=level;sim.Heroes.level_up(sim,h)
	h.pos=sim.vec(sim.data.paths.paths[0][0][79]);h.dest=h.pos;h.rally_center=h.pos
	var target: Dictionary=sim._spawn_enemy("enemy_fat_orc",0);target.pos=h.pos+Vector2(22,0);target.hp=100000;target.max_hp=100000;target.node=79;target.path=0
	for index in range(4):
		source_attack(index,h,target)
		var attack: Dictionary=sim.templates.hero_malik.melee.attacks[index]
		sim.tick=int(h.pending.at);sim.heroes.step(sim,h);sim.tick+=1;sim.heroes.step_auras(sim)
		await capture("malik_"+attack.animation)
		check(not hero_frame().is_empty(),"source attack renders "+attack.animation)
		sim.tick=int(h.busy_until);sim.heroes.step(sim,h);await draw_frame()
		check(h.state=="idle" and hero_frame()=="hero_reinforce_0001","one-shot attack returns to idle "+attack.animation)
	check(battle.sound_cache.has("HeroReinforcementSpecial") and battle.sound_cache.has("HeroReinforcementJump") and battle.sound_cache.has("HeroReinforcementHit"),"source attack and skill sounds resolve")
	check(battle.fx_players.any(func(p):return p.playing),"native hero audio playback")
	sim.tick+=1;sim.heroes.step_auras(sim)
	var rocks: Array=sim.effects.filter(func(f):return f.template=="decal_malik_earthquake")
	check(not rocks.is_empty(),"fissure inserts real earthquake effects")
	if not rocks.is_empty():
		var effect: Dictionary=rocks[-1];sim.tick=effect.at+16;await capture("malik_rocks_last_frame")
		check(battle.draw_list.any(func(d):return d.frame=="hero_reinforce_rocks_0017"),"earthquake last source frame")
		sim.tick=effect.at+17;await capture("malik_rocks_finished")
		check(not battle.draw_list.any(func(d):return d.frame.begins_with("hero_reinforce_rocks_")),"hide_after_runs hides rocks while crater remains")
		sim.tick=effect.at+50;await draw_frame()
		check(battle.draw_list.any(func(d):return d.frame=="decal_bomb_crater" and d.tint.a>0 and d.tint.a<1),"earthquake crater source fade")
		sim.tick=effect.at+75;sim.step();check(not sim.effects.has(effect),"earthquake entity removed at tween end")
	sim.enemies.clear();sim.heroes.fissures.clear();sim.effects.clear();sim.modifiers.clear(sim)
	h.hero_phase="active";h.pending={};h.move_immune=0
	battle.selected_unit=h.id;battle.targeting="hero"
	sim.damage(h,999999,1);sim.heroes.step(sim,h);battle._process(0);await capture("malik_death")
	check(battle.targeting=="" and battle.selected_unit==0,"death clears pending hero targeting")
	check(hero_frame()=="hero_reinforce_0131" and not hit("hero_select").enabled,"death first frame and portrait disabled")
	var died: int=sim.tick;sim.tick=died+9;sim.heroes.step(sim,h);await capture("malik_body")
	check(hero_frame()=="hero_reinforce_0139","death holds final body frame")
	sim.tick=died+60;sim.heroes.step(sim,h);await capture("malik_tombstone")
	check(hero_frame()=="" and battle.draw_list.any(func(d):return d.frame==sim.templates.decal_hero_tombstone.render.sprites[0].name),"two-second tombstone replaces body")
	sim.tick=died+450;sim.heroes.step(sim,h);await capture("malik_respawn")
	check(h.hero_phase=="respawn" and hero_frame()=="hero_reinforce_0112","15-second respawn animation starts")
	sim.tick=died+469;sim.heroes.step(sim,h);await capture("malik_respawn_complete")
	check(h.hp==h.max_hp and h.can_click and h.hero_phase=="active" and hit("hero_select").enabled,"respawn restores combat and HUD input")
	await restart();sim=battle.sim;h=sim.soldiers.filter(func(s):return s.has("hero"))[0]
	check(h.hero.level==1 and h.hero.xp==0 and sim.heroes.fissures.is_empty(),"native restart resets hero progress and effects")
	await action("pause");await action("map");await app.map_ready
	await enter(3,2);check(not battle.sim.soldiers.any(func(s):return s.has("hero")) and hit("hero_select").is_empty(),"source heroic lock suppresses unit and portrait")
	await action("pause");await action("map");await app.map_ready
	check(app.campaign.selected_hero_ids()==["hero_malik"],"challenge does not rewrite saved hero selection")
	var hashes := {}
	for path in ["tests/hero_malik_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/battle_feedback.gd","scripts/battle/dove_unit_info.gd","scripts/battle/dove_heroes.gd","scripts/map/hero_room.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/hero_malik_native_%s.json" % suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes,"native_input":true,"native_audio":true,"browser_tested":false,"scope":"selected Malik, source animation endings, move/rally, melee/skills, earthquake hide/fade/remove, body/tombstone/respawn, restart and challenge boundary; constructed combat fixtures"})
	print("MALIK_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
