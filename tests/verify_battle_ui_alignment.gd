extends SceneTree
## Focused UI state/input checks. Native mode adds rendered compositions, not playthroughs.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
var app: Control
var battle: Control
var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var native := false
var suffix := ""

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func fresh(id: int = 6, mode: int = 1) -> void:
	if is_instance_valid(battle): battle.queue_free(); await process_frame
	battle = Battle.new(); app.add_child(battle)
	battle.initialize(app.loader,app.audio,Levels.load_definition(id,mode))
	battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle.sim.notices.clear()
	await process_frame; await process_frame

func render() -> void:
	battle.queue_redraw(); await process_frame; await process_frame
	if native: await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await render()
	var path := "res://reports/battle_ui_%s_%s.png" % [label,suffix]
	root.get_texture().get_image().save_png(path); captures.append(path)
	check(battle.interface.paint.audit.all(func(row):return row.fits),"rendered text fits "+label)
	check(battle.hits.all(func(hit):return Rect2(0,0,battle.view_width,769).grow(1).encloses(hit.rect)),"hit regions fit "+label)
	check(battle.draw_list.all(func(d):return not battle._frame(d.frame).is_empty()),"draw frames resolve "+label)

func press(point: Vector2, double_click: bool = false, real_input: bool = false) -> void:
	var event := InputEventMouseButton.new(); event.position = point * battle.zoom
	event.global_position = event.position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.double_click = double_click
	if real_input:
		event.position = root.get_screen_transform() * battle.get_global_transform_with_canvas() * (point * battle.zoom)
		event.global_position = event.position
		battle.mouse_filter = Control.MOUSE_FILTER_STOP
		Input.parse_input_event(event); await process_frame
		event = event.duplicate(); event.pressed = false; event.double_click = false
		Input.parse_input_event(event); await process_frame
		battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else: battle._gui_input(event)

func wave_hit(path: int) -> void:
	battle.hits = [{"rect":Rect2(20,20,40,40),"action":"wave","args":{"path":path},"enabled":true}]

func next_wave(index: int = 1) -> void:
	battle.sim.wave = index; battle.sim.spawn_queue.clear(); battle.sim.enemies.clear()
	battle.sim.next_wave_tick = battle.sim.tick + 600
	battle.interface.wave_flags.sync()

func buy_advanced(id: String, kind: String) -> void:
	battle.sim.gold = 10000
	battle.sim.command("build",{"id":id,"type":kind}); battle.sim.tick += 30
	for i in 3: check(battle.sim.command("upgrade",{"id":id,"upgrade_to":"tower_ranger" if kind == "archer" and i == 2 else battle.sim.upgrade_target(battle.sim.tower_by_id(id))}),"fixture advanced tower upgrade")
	battle.selected = id

func logic() -> void:
	await fresh(3)
	wave_hit(1); await press(Vector2(30,30)); check(battle.sim.wave == 1,"first wave remains single click")
	battle.sim.notices.clear(); next_wave()
	var before_gold: int = battle.sim.gold
	var rewards: Array = []
	battle.sim.event.connect(func(kind,payload):
		if kind == "reward": rewards.append(payload))
	wave_hit(1); await press(Vector2(30,30)); check(battle.sim.wave == 1 and battle.sim.gold == before_gold,"early single click has no gameplay effect")
	wave_hit(2); await press(Vector2(30,30),true); check(battle.sim.wave == 1,"cross-entrance double click rejected")
	wave_hit(2); await press(Vector2(30,30),true)
	check(battle.sim.wave == 2 and rewards.size() == 1 and battle.sim.gold > before_gold,"same entrance double click sends wave and rewards exactly once")
	wave_hit(2); await press(Vector2(30,30),true); check(rewards.size() == 1,"stale double click cannot reward twice")
	next_wave(3); wave_hit(1); await press(Vector2(30,30)); next_wave(4)
	wave_hit(1); await press(Vector2(30,30),true); check(battle.sim.wave == 4,"wave identity rejects cross-wave double click")
	for transition in ["pause","focus","selection","world"]:
		next_wave(3); wave_hit(1); await press(Vector2(30,30))
		match transition:
			"pause": battle._action("pause"); battle._action("pause")
			"focus": battle._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT); battle._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
			"selection": battle.selected = "1"; battle.interface.wave_flags.advance(0); battle.selected = ""
			"world": battle.hits.clear(); await press(Vector2(700,690))
		wave_hit(1); await press(Vector2(30,30),true)
		check(battle.sim.wave == 3,"confirmation cleared by "+transition)
	next_wave(3)
	battle.set_process_input(true)
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_SPACE; battle._input(key)
	check(battle.sim.wave == 4,"space shortcut remains available")
	battle.set_process_input(false)
	await fresh()
	battle.selected = "1"
	var state: Array = [battle.sim.gold,battle.sim.rng.state]
	for action in ["locked","upgrade","upgrade_power"]:
		battle.hits = [{"rect":Rect2(20,20,40,40),"action":action,"args":{},"enabled":false}]
		await press(Vector2(30,30))
	check(battle.selected == "1" and battle.message_time == 0 and state == [battle.sim.gold,battle.sim.rng.state],"disabled menu input is silent and preserves selection/economy/RNG")
	battle._action("upgrade_power",{"id":"1","power":"shield"})
	check(battle.message_time == 0,"rejected tower command has no generic error text")
	battle.sim.wave = 1; battle.sim.unlocked = {"fire":true,"reinforcements":true}
	for power in ["fire","reinforcements","rally"]:
		if power == "rally": battle.sim.command("build",{"id":"1","type":"barrack"}); battle.sim.tick += 30; battle.selected = "1"
		battle._action("target",{"power":power})
		check(battle.feedback.cursor_mode() == Input.MOUSE_MODE_HIDDEN,"cursor hiding requested for "+power)
		var first: String = battle.target_pointer_frame(); battle.advance_target_feedback(0.1)
		check(battle.target_pointer_frame() != first,"source pointer animates for "+power)
		for blocker in ["pause","notice","focus","exit"]:
			match blocker:
				"pause": battle.sim.paused = true
				"notice": battle.sim.notices.append("TUTORIAL_1")
				"focus": battle.feedback.focused = false
				"exit": battle.feedback.inside = false
			battle.feedback.sync_cursor(); check(battle.feedback.cursor_mode() == Input.MOUSE_MODE_VISIBLE,"cursor restored "+power+"/"+blocker)
			battle.sim.paused = false; battle.sim.notices.clear(); battle.feedback.focused = true; battle.feedback.inside = true; battle.feedback.sync_cursor()
			check(battle.feedback.cursor_mode() == Input.MOUSE_MODE_HIDDEN,"target mode resumes "+power+"/"+blocker)
		battle.invalid_point_time = battle.INVALID_POINT_DURATION
		check(battle.target_pointer_frame() == "error_feedback_0001","source error feedback retained")
		battle._action("restart"); check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and battle.feedback.rally_fx.is_empty(),"restart clears targeting and feedback")
		battle.sim.notices.clear(); battle.sim.wave = 1; battle.sim.unlocked = {"fire":true,"reinforcements":true}
	battle.sim.command("build",{"id":"1","type":"barrack"}); battle.sim.tick += 30; battle.selected = "1"
	battle._action("target",{"power":"rally"}); battle.hits.clear()
	var rally: Vector2 = battle.sim.tower_by_id("1").rally
	await press(battle.world(rally))
	check(battle.feedback.rally_fx.get("pos",Vector2.INF) == battle.sim.tower_by_id("1").rally and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"rally feedback uses resolved target and restores cursor")
	battle.advance_target_feedback(1.5); check(battle.feedback.rally_fx.is_empty(),"rally feedback expires at source duration")
	for pair in [["barrack",["healing","holystrike","shield"]],["mage",["disintegrate","teleport"]]]:
		await fresh(); buy_advanced("1",pair[0])
		var tower: Dictionary = battle.sim.tower_by_id("1")
		for power: String in pair[1]:
			for rank in int(battle.sim.tower_template(tower).powers[power].max_level):
				var price: int = battle.sim.power_price(tower,power); var gold: int = battle.sim.gold
				battle._action("upgrade_power",{"id":"1","power":power})
				check(tower.powers[power] == rank + 1 and battle.sim.gold == gold - price and battle.selected == "1" and battle.interface.power_fx.powers.has(power),"purchase preserves menu and starts feedback "+power+str(rank))
			var spent: int = battle.sim.gold
			battle.interface.power_fx.clear(); battle._action("upgrade_power",{"id":"1","power":power})
			check(battle.sim.gold == spent and battle.interface.power_fx.is_empty() and battle.message_time == 0,"maxed power purchase is silent "+power)
		battle.interface.power_bought("1",pair[1][0]); battle.selected = "2"; battle.interface.advance_feedback(0)
		check(battle.interface.power_fx.is_empty(),"selection change clears skill animation")
	# The same purchase UI is shared by the older ranger and mercenary menus.
	for kind in ["ranger","camp"]:
		await fresh(5 if kind == "camp" else 6)
		var id := "5" if kind == "camp" else "1"
		battle.sim.gold = 10000
		if kind == "camp": check(battle.sim.command("upgrade",{"id":id,"upgrade_to":"tower_elf"}),"fixture elf camp repair")
		else: buy_advanced(id,"archer")
		battle.selected = id
		var tower: Dictionary = battle.sim.tower_by_id(id)
		for power: String in tower.powers:
			for rank in int(battle.sim.tower_template(tower).powers[power].max_level):
				battle._action("upgrade_power",{"id":id,"power":power})
			check(battle.selected == id and battle.interface.power_fx.powers.has(power),"shared purchase feedback "+kind+"/"+power)
			var gold: int = battle.sim.gold
			battle.interface.power_fx.clear(); battle._action("upgrade_power",{"id":id,"power":power})
			check(battle.sim.gold == gold and battle.interface.power_fx.is_empty(),"shared maxed menu silent "+kind+"/"+power)
		var power: String = tower.powers.keys()[0]
		battle.interface.power_bought(id,power); battle.interface.advance_feedback(23.0 / 30.0)
		check(battle.interface.power_fx.powers.is_empty(),"purchase animation expires "+kind)
		battle.interface.power_bought(id,power); battle._action("sell",{"id":id})
		check(battle.selected == "" and battle.interface.power_fx.is_empty(),"sale clears purchase feedback "+kind)
		battle._action("restart"); check(battle.interface.power_fx.is_empty(),"restart clears purchase feedback "+kind)
	for mode in [1,2,3]:
		for stars in ([1,2,3] if mode == 1 else [1]):
			await fresh(6,mode); battle.sim.lives = [5,10,20][stars-1] if mode == 1 else 1
			var rng_state: int = battle.sim.rng.state
			battle.sim._finish("victory")
			check(battle.interface.victory.badge() == "victoryBadges_notxt_%04d" % {1:2,2:3,3:1}[mode],"source mode badge "+str(mode))
			check(battle.interface.victory.particles.size() == 150 and battle.sim.rng.state == rng_state,"victory particles use separate random state")
			check(is_equal_approx(battle.interface.victory.buttons_ready_at(),0.65 + [19,38,54][stars-1] / 30.0 + 1),"source chain/button timing "+str(stars))
			battle._action("restart"); check(battle.interface.victory.particles.is_empty(),"restart clears victory particles")
	await fresh(3); battle.interface.wave_flags.sync()
	var flag: Dictionary = battle.interface.wave_flags.active[0]
	for point in [Vector2(60,60),Vector2(60,680),Vector2(1100,60),Vector2(1100,680)]:
		flag.entrance = {"pos":{"x":point.x-battle.margin,"y":768-point.y},"r":0}
		var geometry: Dictionary = battle.interface.wave_flags.tooltip_geometry(flag)
		check(geometry.polygons.size() == 1 and Rect2(0,0,battle.view_width,768).encloses(geometry.rect),"tooltip four-way single polygon within screen "+str(point))
	# Exercise the new Continue hit through the actual app and two-stage save flow.
	battle.queue_free(); await process_frame
	app._start_campaign(1); await app.map_ready
	app._start_level(1,1,2); battle = app.battle
	battle.set_process(false); battle.sim.notices.clear(); battle.sim._finish("victory")
	check(app.campaign.data.has("last_victory") and app.campaign.record(1).get("stars",0) == 0,"victory retains pending result until Continue")
	battle.victory_elapsed = battle.interface.victory.buttons_ready_at() + 0.1
	await render()
	var continue_hit: Dictionary = battle.hits.filter(func(h):return h.action == "map")[0]
	await press(continue_hit.rect.get_center()); await app.map_ready
	check(app.battle == null and app.campaign_map != null and app.campaign.record(1).get("stars",0) == 3 and not app.campaign.data.has("last_victory"),"Continue routes to map and settles the existing save format")

func native_scenes() -> void:
	var layout_only := OS.get_cmdline_user_args().has("--layout-only")
	await fresh(3); battle.interface.wave_flags.sync()
	var flag: Dictionary = battle.interface.wave_flags.active[0]
	battle.hovered = "wave"+str({"path":flag.path}); battle.interface.wave_flags.advance(0.3)
	await capture("incoming")
	if not layout_only:
		var hit: Dictionary = battle.hits.filter(func(h):return h.action == "wave")[0]
		await press(hit.rect.get_center(),false,true); check(battle.sim.wave == 1,"native viewport first-wave click")
		battle.sim.notices.clear(); next_wave(); await render()
		hit = battle.hits.filter(func(h):return h.action == "wave")[0]
		await press(hit.rect.get_center(),false,true); check(battle.sim.wave == 1,"native viewport early single rejected")
		await press(hit.rect.get_center(),true,true); check(battle.sim.wave == 2,"native viewport double click accepted")
	await fresh()
	if not layout_only:
		buy_advanced("3","archer"); await render(); await create_timer(0.15).timeout
		await capture("ranger_menu")
		battle._action("upgrade_power",{"id":"3","power":"poison"}); battle.interface.advance_feedback(0.1)
		await capture("ranger_powerbuy")
		battle.selected = ""
	for type in (["enemy_ogre"] if layout_only else ["enemy_goblin","enemy_dark_knight","enemy_ogre","enemy_gargoyle","eb_juggernaut"]):
		var enemy: Dictionary = battle.sim._spawn_enemy(type,0)
		enemy.pos = Vector2(520,350); battle.selected_unit = enemy.id
		await capture("selected_"+type)
		var marker: Dictionary = battle.draw_list.filter(func(d):return d.frame.begins_with("selected_"))[0]
		check(marker.z == 1400 and marker.pos == enemy.pos + battle.Simulation.vec(battle.sim.templates[type].unit.marker_offset),"source marker layer and offset "+type)
		enemy.hp = 0; await render(); check(battle.draw_list.all(func(d):return not d.frame.begins_with("selected_")),"dead target loses marker")
		battle.sim.enemies.clear()
	buy_advanced("1","barrack"); await render(); await create_timer(0.15).timeout
	await capture("paladin_menu")
	check(battle.draw_list.any(func(d):return d.frame.begins_with("rally_feedback_")),"current rally uses source ground animation")
	battle._action("upgrade_power",{"id":"1","power":"holystrike"}); battle.interface.advance_feedback(0.2)
	await capture("powerbuy")
	battle.sim.wave = 1; battle.sim.unlocked = {"fire":true,"reinforcements":true}
	for power in ["fire","reinforcements","rally"]:
		# Make native window enter/focus explicit, independent of the physical desktop pointer.
		battle._notification(Control.NOTIFICATION_WM_MOUSE_ENTER)
		battle._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
		battle._action("target",{"power":power}); battle.pointer = battle.world(Vector2(500,350)); battle.advance_target_feedback(0.13)
		if not layout_only:
			check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN,"native system cursor hidden "+power)
			battle._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
			check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"native focus loss restores cursor "+power)
			battle._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
			check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN,"native focus return restores targeting "+power)
			battle.pointer = battle.world(Vector2(500,350))
		await capture("pointer_"+power)
		battle.targeting = ""; battle.feedback.sync_cursor()
		if not layout_only: check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"native system cursor restored "+power)
	await fresh(); buy_advanced("2","mage"); await render(); await create_timer(0.15).timeout
	await capture("arcane_menu")
	for power in ["disintegrate","teleport"]:
		for rank in 3: battle._action("upgrade_power",{"id":"2","power":power})
	await capture("arcane_maxed")
	await fresh(5); battle.sim.gold = 10000; battle.sim.command("upgrade",{"id":"5","upgrade_to":"tower_elf"}); battle.selected = "5"
	await render(); await create_timer(0.15).timeout; await capture("camp_menu")
	for mode in [1,2,3]:
		for stars in ([3] if layout_only and mode == 1 else ([1,2,3] if mode == 1 else [1])):
			await fresh(6,mode); battle.sim.lives = [5,10,20][stars-1] if mode == 1 else 1; battle.sim._finish("victory")
			if not layout_only:
				battle.victory_elapsed = 0.3; await capture("victory_%d_%d_popup" % [mode,stars])
				check(battle.hits.all(func(h):return h.action not in ["map","restart"]),"victory buttons unavailable during popup")
				battle.victory_elapsed = battle.interface.victory.buttons_ready_at() - 0.1; await render()
				check(battle.hits.all(func(h):return h.action not in ["map","restart"]),"victory buttons unavailable while chains expand")
			battle.victory_elapsed = battle.interface.victory.buttons_ready_at() + 0.2; await capture("victory_%d_%d_ready" % [mode,stars])
			check(battle.hits.filter(func(h):return h.action in ["map","restart"]).size() == 2,"both source buttons open together")
	if layout_only: return
	var returned := []
	battle.returned_to_map.connect(func(): returned.append(true))
	var map_hit: Dictionary = battle.hits.filter(func(h):return h.action == "map")[0]
	await press(map_hit.rect.get_center(),false,true); check(returned.size() == 1,"native continue triggers existing return event once")

func run() -> void:
	create_timer(120).timeout.connect(func():push_error("Battle UI timeout");quit(1))
	native = DisplayServer.get_name() != "headless"; suffix = "%dx%d" % [root.size.x,root.size.y] if native else "logic"
	app = App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://battle_ui_settings_"+token+".json"; app.slots_path = "user://battle_ui_progress_"+token+".json"
	root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
	if native: await native_scenes()
	else: await logic()
	app.queue_free(); await process_frame; await process_frame
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"exit always restores system cursor")
	var hashes := {}
	for script in ["battle_feedback","battle_victory","battle_view","battle_ui","battle_wave_flags","dove_ui_layout"]:
		var path: String = "scripts/battle/"+script+".gd"; hashes[path] = FileAccess.get_sha256("res://"+path)
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":native,"captures":captures,"source_hashes":hashes,"layout_only":OS.get_cmdline_user_args().has("--layout-only"),"scope":"targeted UI/input with constructed battle states; no complete replays"}
	if not preload("res://tests/report_writer.gd").json_file("res://reports/battle_ui_"+suffix+".json",report):quit(1);return
	print("BATTLE_UI: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
