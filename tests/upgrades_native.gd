extends SceneTree
const App=preload("res://scenes/app_root.tscn")
const Progress=preload("res://scripts/services/campaign_progress.gd")
const Tech=preload("res://scripts/battle/dove_upgrades.gd")
var app: Control
var room: Control
var failures: Array[String]=[]
var checks:=0
var text_checks:=0
var suffix: String
var temporary: String
func _init() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func run() -> void:
	create_timer(150).timeout.connect(func():push_error("technology native timeout");quit(1))
	temporary="user://upgrades_native_%d" % Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(temporary)
	app=App.instantiate();app.settings_path=temporary+"/settings.json";app.slots_path=temporary+"/campaign.json";root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	# Independent fixture only; the user's real slots are never changed.
	for id in range(1,28):app.campaign.data.levels[id]={"stars":3,1:2,2:2,3:2}
	app.campaign.save();app.campaign_map._action("upgrades");room=app.campaign_map.upgrades_room
	suffix="%dx%d" % [root.size.x,root.size.y]
	await capture("initial")
	if "--interactive" in OS.get_cmdline_user_args():return
	await click("upgrade", "archer_el_bloodletting_shoot")
	await create_timer(0.1).timeout
	check(app.campaign.data.upgrades.archers==6,"native higher node buys all prerequisites")
	check(app.campaign_map.fx.any(func(p):return p.playing and p.get_playback_position()>0),"upgrade audio advances in native player")
	var reload=Progress.new();reload.initialize(app.campaign.path)
	check(reload.data.upgrades.archers==6,"native purchase immediately persisted")
	await click("undo");check(app.campaign.data.upgrades.archers==0 and not room.can_undo,"undo restores opening levels")
	for id: String in Tech.definition().techs:
		room.shown=id;await capture("text_audit",false)
	for branch: String in Tech.definition().classes:
		for id: String in Tech.definition().techs:
			var t: Dictionary=Tech.definition().techs[id]
			if t.class==branch and t.level==6:await click("upgrade",id)
	await capture("complete")
	check(app.campaign.upgrade_summary().spent==Tech.spent(Tech.levels({"archers":6,"barracks":6,"mages":6,"engineers":6,"rain":6,"reinforcements":6})),"all six branches bought")
	await click("reset");check(app.campaign.upgrade_summary().spent==0 and not room.can_undo,"reset rebases undo to zero")
	await click("upgrade","mage_hermetic_study");await click("undo")
	check(app.campaign.data.upgrades.mages==0,"undo after reset uses rebased snapshot")
	await click("close");check(not room.visible and app.campaign_map.overlay=="","done closes modal")
	app.campaign_map._action("upgrades");await capture("reopen",false)
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;Input.parse_input_event(key);await process_frame
	check(not room.visible,"Escape closes technology modal")
	app.campaign_map._action("upgrades");await process_frame
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=root.get_final_transform()*(room.size/2);Input.parse_input_event(right);await process_frame
	check(not room.visible,"right click closes technology modal")
	app.campaign.data.upgrade_list_id="2";app.campaign_map._action("upgrades");await capture("unsupported")
	check(room.hits.size()==1 and room.hits[0].action=="close" and not app.campaign.is_playable(1),"unsupported tree explains block and exposes close only")
	await click("close")
	if suffix=="1280x720":await combat_preview()
	var hashes := preload("res://tests/upgrades_test_support.gd").hashes()
	hashes["tests/upgrades_native.gd"]=FileAccess.get_sha256("res://tests/upgrades_native.gd")
	var report: Dictionary={"passed":failures.is_empty(),"checks":checks,"text_boxes_checked":text_checks,"resolution":suffix,"native_input":true,"native_audio":true,"source_hashes":hashes,"browser_tested":false,"failures":failures}
	var file:=FileAccess.open("res://reports/upgrades_native_"+suffix+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("UPGRADES_NATIVE: ",JSON.stringify(report));app.queue_free();await process_frame
	remove_tree(temporary);quit(0 if failures.is_empty() else 1)
func combat_preview() -> void:
	app.campaign.data.upgrade_list_id="1"
	for branch: String in Tech.definition().classes:app.campaign.data.upgrades[branch]=6
	app._start_level(6,1,2)
	var battle: Control=app.battle;battle.set_process(false);battle.set_process_input(false)
	while not battle.sim.notices.is_empty():battle.sim.command("confirm")
	battle.sim.command("wave")
	while not battle.sim.notices.is_empty():battle.sim.command("confirm")
	var point: Vector2=battle.sim.vec(battle.sim.data.paths.paths[0][0][55])
	check(battle.sim.command("cast",{"power":"reinforcements","pos":point}),"native upgraded reinforcement resolves through battle setup")
	battle.sim.tick=120;battle.sim.upgrades.scorched(battle.sim,point)
	var enemy: Dictionary=battle.sim._spawn_enemy("enemy_fat_orc",0);enemy.pos=point+Vector2(85,0);enemy.hp=10000
	for attempt in range(100):
		if battle.sim.modifiers.apply(battle.sim,"mod_blood_elves",enemy,1,"0",-1,1,{"value":100,"type":2}):break
	for frame in range(20):
		battle.sim.tick+=1;battle.sim.modifiers.step(battle.sim);battle.sim.upgrades.step(battle.sim)
	var soldier: Dictionary=battle.sim.soldiers[-1];soldier.rallying=false;soldier.pos=point
	battle.sim.upgrades.reinforcement_step(battle.sim,soldier,battle.sim.templates[soldier.template])
	battle.sim.tick+=3;battle.sim.upgrades.reinforcement_step(battle.sim,soldier,battle.sim.templates[soldier.template])
	battle.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	check(battle.draw_list.any(func(item):return item.frame.begins_with("reinforce")),"native reinforcement sprites rendered")
	check(battle.draw_list.all(func(item):return not battle._frame(item.frame).is_empty()),"native technology battle frames resolve")
	root.get_texture().get_image().save_png("res://reports/upgrades_combat_"+suffix+".png")
func click(action: String,id: String="") -> void:
	room.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	var hits: Array=room.hits.filter(func(h):return h.action==action and (id=="" or h.args.get("id","")==id))
	check(not hits.is_empty(),"native hit exists "+action+id)
	if hits.is_empty():return
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;e.position=root.get_final_transform()*(hits[0].rect.get_center()*room.zoom)
	Input.parse_input_event(e);await process_frame
	e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=root.get_final_transform()*(hits[0].rect.get_center()*room.zoom);Input.parse_input_event(e);await process_frame
func capture(label: String,save_image: bool=true) -> void:
	room.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	for audit: Dictionary in room.paint.audit:
		text_checks+=1;check(audit.fits,"text fits "+str(audit.id));check(Rect2(Vector2.ZERO,room.size/room.zoom).encloses(audit.box),"text on screen "+str(audit.id))
	for hit: Dictionary in room.hits:check(Rect2(Vector2.ZERO,room.size/room.zoom).encloses(hit.rect),"hit on screen "+hit.action)
	if save_image:root.get_texture().get_image().save_png("res://reports/upgrades_"+label+"_"+suffix+".png")
func remove_tree(folder: String) -> void:
	for child in DirAccess.get_directories_at(folder):remove_tree(folder+"/"+child)
	for child in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder+"/"+child)
	DirAccess.remove_absolute(folder)
