extends "res://tests/level11_visual.gd"
## Native render/input and constructed end-to-map persistence, no played victory.
func shot12(label:String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var path:="res://reports/level12_%s_%s.png"%[label,suffix]
	check(root.get_texture().get_image().save_png(path)==OK,"capture "+label)
	captures.append({"state":label,"path":path})

func ending_input12() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=false
	Input.parse_input_event(event);await process_frame

func ending12() -> void:
	battle.sim._finish("victory");battle.set_process(true)
	await create_timer(4.2).timeout;battle.set_process(false)
	await capture("twelfth_victory")
	check(battle.outcome.get("next_item_name","")=="kr1_end","campaign result carries route")
	check(not app.campaign.data.last_victory.is_empty(),"victory saved before comic")
	if not layout_only:
		app.packs.enabled=true;app.packs._configuration_valid=false;app.packs.error_message="fixture ending download failure"
	await action("map");await create_timer(0.2).timeout
	if not layout_only:
		check(app.ending==null and app.retry.visible and app.back.visible and not app.campaign.data.last_victory.is_empty(),"ending failure retains saved result and recovery buttons")
		app.packs.enabled=false;app.retry.pressed.emit();await create_timer(0.2).timeout
	check(app.ending!=null and not battle.visible,"Continue opens ending")
	if layout_only:
		app.ending.phase_elapsed=1.1;app.ending.elapsed=float(app.ending.page().end_frame)/30-0.01;app.ending._process(0.02)
	else:await ending_input12()
	check(not app.ending.playing,"first keyboard input reaches final frame")
	await create_timer(1).timeout;await shot12("comic1_final")
	check(app.ending.page().order.size()>0,"comic sprite layer order populated")
	check(app.ending.phase=="comic1" and not app.campaign.data.last_victory.is_empty(),"comic retains pending settlement")
	await ending_input12();await create_timer(0.3).timeout
	check(app.ending.phase=="comic2","comic directly enters epilogue without credits")
	await ending_input12();await shot12("comic2_final")
	await ending_input12();await app.map_ready
	await create_timer(1).timeout
	check(app.ending==null and app.campaign.record(12).has(1),"epilogue ends in map settlement")
	await shot12("map_settlement")

func actors12() -> void:
	var sim=battle.sim;var boss:Dictionary=sim.unit_by_id(sim.veznan.boss_id);var t:Dictionary=sim.templates.eb_veznan
	await capture("twelfth_castle")
	var tower:Dictionary=sim.towers[0]
	sim.veznan.block_tower(sim,tower,boss.id);sim.tick=sim.veznan.blocks[0].next;sim.veznan.step_blocks(sim)
	await capture("twelfth_block_preHold")
	check(tower.blocked,"native tower block begins after source start")
	for i in 3:await click(battle.world(tower.pos));sim.tick+=1;sim.veznan.step_blocks(sim)
	check(sim.veznan.blocks[0].phase=="remove","native three clicks release seal")
	sim.tick=sim.veznan.blocks[0].next;sim.veznan.step_blocks(sim)
	check(not tower.blocked and sim.veznan.blocks.is_empty(),"native removal releases count")
	for portal:Dictionary in sim.veznan.portals:portal.signal=true
	sim.veznan.step_portals(sim);await capture("twelfth_portal_start")
	for n in 40:sim.tick+=1;sim.veznan.step_portals(sim)
	await capture("twelfth_portal_active")
	boss.veznan.phase="battle";boss.veznan.job={};boss.ignore_damage=false;boss.pos=Vector2(500,350);boss.hp=10
	sim.damage(boss,100000,1);sim.veznan.step_enemy(sim,boss,t)
	await capture("twelfth_transform")
	sim.tick+=sim.Behaviors.Veznan.duration(sim,boss,"demonTransform");sim.veznan.step_enemy(sim,boss,t)
	await capture("twelfth_demon")
	check(battle.draw_list.any(func(row):return row.frame==Anim.frame(t.render.sprites[0],sim.animations,{"state":boss.state,"prefix":boss.prefix,"elapsed":sim.tick-boss.state_at,"loop":boss.playback_loop})),"demon source sprite reaches render queue")
	sim.damage(boss,100000,1);sim.veznan.step_enemy(sim,boss,t)
	await capture("twelfth_death")
	check(sim.veznan.hud_hidden and not sim.controller.can_finish(sim),"native death hides HUD before victory")
	sim.tick+=110;sim.veznan.step_enemy(sim,boss,t);sim.veznan.step_souls(sim)
	await capture("twelfth_souls")
	sim.tick=int(boss.veznan.at)+sim.Behaviors.Veznan.duration(sim,boss,"death");sim.veznan.step_enemy(sim,boss,t)
	sim.tick+=90;sim.veznan.step_enemy(sim,boss,t);await capture("twelfth_white_start")
	sim.tick+=80;await capture("twelfth_white_expanded")
	check(not sim.controller.can_finish(sim),"white expansion does not finish early")
	sim.tick+=45;sim.veznan.step_enemy(sim,boss,t);await capture("twelfth_death_end")
	check(sim.veznan.complete and boss.hidden,"native final hidden state")
	check(not battle.draw_list.any(func(row):return row.pos==boss.pos and row.frame.begins_with("boss_veznan_")),"boss absent from final render queue")
	check(battle.sound_cache.has("VeznanDeath") and battle.sound_cache.has("VeznanToDemon"),"native boss sound resources")

func _run() -> void:
	create_timer(180).timeout.connect(func():push_error("Twelfth native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y];layout_only=OS.get_cmdline_user_args().has("--layout-only")
	app=AppScene.instantiate();app.settings_path="res://output/level12_native_settings.json";app.slots_path="res://output/level12_native_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,12):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	check(app.campaign.select_hero("hero_malik"),"Malik selected")
	if layout_only:
		app._start_level(12,1,2)
		while app.battle==null or app.transitioning:await process_frame
		battle=app.battle;battle.set_process(false);await dismiss()
	else:await enter(12,1)
	await capture("twelfth_opening")
	if not layout_only:
		await menu("1");await action("build",{"id":"1","type":"mage"})
		for n in 30:battle.sim.step()
		await actors12()
		battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false)
		await action("restart");check(battle.sim.wave==0 and not battle.sim.veznan.hud_hidden,"restart clears boss lifecycle")
	await ending12()
	if not layout_only:
		await enter(12,1)
		battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false)
		app.packs.enabled=true;app.packs._configuration_valid=false;app.packs.error_message="fixture repeat ending failure"
		await action("map");await create_timer(0.1).timeout
		check(app.retry.visible and app.back.visible,"repeated victory still routes to ending")
		app.packs.enabled=false;app.back.pressed.emit();await app.map_ready
		check(app.ending==null and app.campaign.record(12).get("stars",0)==3,"failed ending can return to map with score")
		for mode in [2,3]:
			await enter(12,mode);await capture("twelfth_mode%d"%mode)
			check(battle.sim.gold==[1600,2800][mode-2] and battle.sim.veznan.boss_id==0,"challenge source entry %d"%mode)
			if mode==3:
				await menu("1");check(not battle.hits.any(func(h):return h.action=="build" and h.args.type=="engineer"),"iron artillery absent")
			battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false)
			await action("map");await app.map_ready
			check(app.ending==null and app.campaign.record(12).has(mode),"challenge victory bypasses ending and settles")
		await enter(12,3);battle.sim._finish("defeat");await action("map");await app.map_ready
		check(app.ending==null and app.campaign.record(12).has(3),"challenge defeat preserves score")
	var hashes:Dictionary={}
	for path:String in ["tests/level12_visual.gd","scripts/app_root.gd","scripts/ui/kr1_ending.gd","scripts/battle/battle_view.gd","scripts/battle/dove_veznan.gd","scripts/battle/level01_sim.gd","data/kr1_end/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level12_native_%s.json"%suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes,"full_replays":false,"native_input":true,"native_audio":true,"layout_only":layout_only})
	print("LEVEL12_NATIVE: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
