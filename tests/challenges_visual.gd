extends "res://tests/tower_upgrade_visual.gd"
const AppScene = preload("res://scenes/app_root.tscn")
const Fixture = preload("res://tests/slot_fixture.gd")
var app: Control
var layout_only := false

func click(point: Vector2) -> void:
	var screen: Vector2=root.get_screen_transform()*battle.get_global_transform_with_canvas()*(point*battle.zoom)
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new();input.position=screen;input.global_position=screen;input.pressed=pressed;input.button_index=MOUSE_BUTTON_LEFT
		Input.parse_input_event(input);await process_frame
	if is_instance_valid(battle):await draw_frame()

func map_draw() -> void:
	app.campaign_map.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw

func map_action(kind: String, args: Dictionary = {}) -> void:
	await map_draw()
	var map: Control=app.campaign_map
	for entry: Dictionary in map.hits:
		if entry.action!=kind or not entry.enabled:continue
		if not args.is_empty() and entry.args!=args:continue
		var point: Vector2=root.get_screen_transform()*map.get_global_transform_with_canvas()*(entry.rect.get_center()*map.zoom)
		for pressed in [true,false]:
			var input:=InputEventMouseButton.new();input.position=point;input.global_position=point;input.pressed=pressed;input.button_index=MOUSE_BUTTON_LEFT
			Input.parse_input_event(input);await process_frame
		return
	check(false,"native map hit "+kind+str(args))

func map_capture(label: String) -> void:
	await map_draw()
	var path:="res://reports/challenges_%s_%s.png" % [label,suffix]
	check(root.get_texture().get_image().save_png(path)==OK,"map capture "+label)
	check(app.campaign_map.paint.audit.all(func(row):return row.fits),"native map text fits "+label)
	captures.append({"state":label,"path":path})

func capture(label: String) -> void:
	await draw_frame()
	var path:="res://reports/towers_%s_%s.png" % [label,suffix]
	check(root.get_texture().get_image().save_png(path)==OK,"capture "+label)
	var invalid: Array=battle.hits.filter(func(entry):return entry.rect.position.x<0 or entry.rect.end.x>battle.view_width or entry.rect.position.y<0 or entry.rect.end.y>(769 if entry.action=="unit_info" else 768))
	check(invalid.is_empty(),"visible hit regions "+label+str(invalid))
	check(battle.draw_list.all(func(d):return not battle._frame(d.frame).is_empty()),"all rendered frames resolve "+label)
	captures.append({"state":label,"path":path,"gold":battle.sim.gold,"tick":battle.sim.tick})

func enter(id: int, mode: int) -> void:
	app.campaign_map.camera_offset=Vector2.ZERO
	await map_action("level",{"id":id})
	await map_action("mode",{"mode":mode,"reason":"战役获得三星后开放挑战"})
	check(app.campaign_map.mode==mode,"mouse selects challenge mode")
	await map_capture("level%d_mode%d" % [id,mode])
	await map_action("battle")
	battle=app.battle
	check(battle!=null and battle.sim.data.level.id==id and battle.sim.data.level.mode==mode,"native starts actual identity")
	battle.set_process(false)
	await dismiss()

func victory(mode: int) -> void:
	await enter(1,mode)
	check(battle.sim.notices.is_empty() and battle.sim.lives==1,"native challenge one has no campaign tutorials")
	await menu("4")
	var kinds: Array=battle.hits.filter(func(h):return h.action=="build").map(func(h):return h.args.type)
	check(kinds.size()==(4 if mode==2 else 2) and (mode==2 or (not "archer" in kinds and not "mage" in kinds)),"native iron bans absent from menu")
	await capture("challenge1_mode%d_build" % mode)
	if not layout_only:
		await action("build",{"id":"4","type":"engineer"})
		check(battle.sim.gold==int(battle.sim.data.waves.cash)-125,"native legal challenge build")
		await action("wave")
		check(battle.sim.unlocked.fire and battle.sim.unlocked.reinforcements,"native first wave opens both powers")
		await action("target",{"power":"reinforcements"});await click(battle.world(Vector2(474,516)))
		check(battle.sim.cooldowns.reinforcements>0,"native challenge spell mouse input")
		await capture("challenge1_mode%d_powers" % mode)
		if mode==2:
			await restart();check(battle.sim.wave==0 and battle.sim.data.level.mode==mode and battle.sim.lives==1,"native restart retains mode")
	# A real simulation finish event exercises Battle -> pending result -> map;
	# this is an interface fixture, not evidence of a playable victory.
	battle.sim._finish("victory")
	check(battle.outcome.mode==mode and battle.outcome.stars==1,"native challenge finish event identity and reward")
	battle.set_process(true);await create_timer(2.1).timeout;battle.set_process(false);await capture("challenge1_mode%d_victory" % mode)
	check(battle.sound_cache.has("GUIQuestCompleted") and battle.sound_cache.has("GUIWinStars"),"native challenge victory fanfare/star audio")
	check(app.campaign.data.last_victory.level_mode==mode,"native pending result has challenge identity")
	await action("map");await app.map_ready
	if not layout_only:
		await create_timer(0.8).timeout;await map_capture("mode%d_first_completion" % mode)
		await create_timer(4).timeout;await map_capture("mode%d_settled_flag" % mode)
	check(app.campaign.record(1).has(mode),"native map settlement preserves challenge score")
	app.campaign_map.camera_offset=Vector2.ZERO;await map_action("level",{"id":1});await map_capture("mode%d_completed_panel" % mode);await map_action("close")

func _run() -> void:
	create_timer(240).timeout.connect(func():push_error("Challenge native timeout");quit(1))
	layout_only=OS.get_cmdline_user_args().has("--layout-only")
	suffix="%dx%d" % [root.size.x,root.size.y]
	app=AppScene.instantiate();app.settings_path="user://challenges_native_settings.json";app.slots_path="user://challenges_native_%d.progress" % Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,6):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	for mode in [2,3]:await victory(mode)
	await enter(5,3);await capture("challenge5_iron_opening")
	check(battle.sim.towers.filter(func(t):return t.template=="tower_archer_3").size()==3,"native fifth iron three preplaced archers")
	for site in ["5","7"]:
		await menu(site);await capture("challenge5_iron_camp"+site+"_ruins")
		if layout_only:
			# Set up the repaired menu only; transaction/input regressions run at 720p.
			battle.sim.command("upgrade",{"id":site,"upgrade_to":"tower_elf"})
			battle.sim.command("buy_soldier",{"id":site,"type":"soldier_elf"})
			battle.sim.command("upgrade_power",{"id":site,"power":"bleed"})
		else:
			await action("upgrade");await menu(site);await action("buy_soldier")
			for i in range(50):battle.sim.step()
			await menu(site);await action("upgrade_power",{"id":site,"power":"bleed"})
			check(battle.sim.tower_by_id(site).hired==1 and battle.sim.tower_by_id(site).powers.bleed==1,"native forbidden barracks allow camp repair/recruit/skill")
		await menu(site);await capture("challenge5_iron_camp"+site+"_repaired")
	await menu("6");check(hit("build",{"id":"6","type":"barrack"}).is_empty(),"native fifth barrack ban")
	await capture("challenge5_iron_build_restriction")
	var f:=FileAccess.open("res://reports/challenges_visual_"+suffix+".json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"scope":"new interface layout only" if layout_only else "challenge input, finish-event settlement and interface", "combat_replays_run":false},"\t"));f.close()
	print("CHALLENGES_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," ",suffix," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
