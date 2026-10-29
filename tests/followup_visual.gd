extends "res://tests/feedback_visual.gd"
const Writer = preload("res://tests/report_writer.gd")
var journeys: Array=[]
func guard_draws() -> Array:
	return battle.draw_list.filter(func(d):return d.frame.begins_with("imperialGuard_"))
func capture_followup(label: String) -> void:
	await draw_frame()
	var path:="res://reports/followup_%s_%s.png" % [label,suffix]
	check(root.get_texture().get_image().save_png(path)==OK,"native capture "+label)
	check(battle.draw_list.all(func(d):return not battle._frame(d.frame).is_empty()),"rendered frames resolve "+label)
	captures.append({"state":label,"path":path})
func hover_and_ranges(level_id: int) -> void:
	await open_stage(level_id);await dismiss()
	await hover(battle.world(battle.sim.tower_by_id("1").pos));await capture_followup("hover_empty_%d" % level_id)
	var over: Array=battle.draw_list.filter(func(d):return d.frame.ends_with("_over"))
	check(over.size()==1 and over[0].z==1400,"source empty hover remains on decal layer")
	await menu("1");await hover(hit("build",{"id":"1","type":"mage"}).rect.get_center())
	await capture_followup("range_build_%d" % level_id)
	check(battle.interface.range_previews.size()==1 and battle.interface.range_previews[0].frame=="range_circle","source build attack range artwork")
	await make_tower("1","mage",[]);await menu("1");await hover(hit("upgrade").rect.get_center())
	await capture_followup("range_upgrade_%d" % level_id)
	var rings: Array=battle.interface.range_previews
	check(rings.size()==2 and rings.all(func(r):return r.frame=="range_circle" and r.quadrants==4 and r.tint==Color.WHITE),"current and upgraded source circles retain native color")
	var t: Dictionary=battle.sim.tower_by_id("1")
	check(rings.all(func(r):return r.center.is_equal_approx(battle.world(t.pos+battle.sim.vec(battle.sim.tower_template(t).tower.range_offset)))),"range center uses source offset")
	await hover(Vector2(20,80));await capture_followup("hover_built_%d" % level_id)
	over=battle.draw_list.filter(func(d):return d.frame.ends_with("_over"))
	check(over.size()==1 and over[0].z==1300,"source built highlight stays below tower, above background")
	await make_tower("2","barrack",[]);await menu("2");await hover(hit("upgrade").rect.get_center())
	await capture_followup("rally_upgrade_%d" % level_id)
	rings=battle.interface.range_previews
	check(rings.size()==1 and rings[0].frame=="rally_circle" and rings[0].tint==Color.WHITE,"barracks preview replaces single source rally circle")
func sale_scene() -> void:
	await open_stage(6);await dismiss();await make_tower("1","barrack",["tower_barrack_2","tower_barrack_3","tower_paladin"])
	var sim=battle.sim
	for frame in 100:sim.step()
	await capture_followup("barracks_before_sale")
	var owned: Array=sim.soldiers.filter(func(s):return s.home=="1")
	check(owned.size()==3,"native sale starts with three paladins")
	check(sim.command("sell",{"id":"1"}),"native barracks sale")
	await capture_followup("barracks_after_sale")
	check(not battle.draw_list.any(func(d):return d.frame.begins_with("soldier_paladin_")),"sale draws no paladin death or corpse")
	check(sim.soldiers.size()==7 and guard_draws().size()==7,"sale preserves seven preplaced guards exactly once")
func guard_journey(mode: int) -> void:
	await open_stage(6,mode);await dismiss();var sim=battle.sim
	sim.spawn_queue.clear();sim.enemies.clear()
	for frame in 80:sim.step()
	await draw_frame();check(guard_draws().size()==7,"seven units rendered exactly once mode%d" % mode)
	for s: Dictionary in sim.soldiers.duplicate():
		var nearest:=INF;var location: Array=[]
		for pi in sim.data.paths.paths.size():
			if not sim.data.paths.active[pi]:continue
			for spi in sim.data.paths.paths[pi].size():
				for ni in range(8,sim.data.paths.paths[pi][spi].size()-1):
					var d: float=sim.distance(s.rally_center,sim.vec(sim.data.paths.paths[pi][spi][ni]))
					if d<nearest:nearest=d;location=[pi,spi,ni]
		var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",location[1],location[0]);e.node=location[2]-8;e.progress=e.node;e.pos=sim.vec(sim.data.paths.paths[e.path][e.subpath][e.node])
		e.hp=10000;e.max_hp=e.hp # Keep peers from killing this observation target first.
		var reached:=false
		for frame in 220:
			sim.step()
			if not e.blockers.is_empty():reached=true;break
		check(reached,"real-path enemy intercepted with all guards present %d/%d" % [mode,s.id])
		for frame in 15:sim.step()
		await draw_frame()
		check(guard_draws().size()==sim.soldiers.size(),"no stationary layout copies during engagement")
		var blocker: Dictionary=sim.unit_by_id(e.blocker) if e.blocker!=0 else s
		var live_draws: Array=guard_draws().filter(func(d):return d.pos.is_equal_approx(blocker.pos))
		check(live_draws.size()==1,"drawn guard follows actual melee position")
		if s.slot==0:await capture_followup("guard_engagement_%d" % mode)
		journeys.append({"mode":mode,"guard_post":s.id,"blocker":e.blocker,"path":location,"intercepted":reached,"live_position":[blocker.pos.x,blocker.pos.y]})
		sim.damage(e,99999,1)
		for frame in 150:sim.step()
	for s: Dictionary in sim.soldiers.duplicate():sim.damage(s,99999,1)
	for frame in 180:sim.step()
	await capture_followup("guards_removed_%d" % mode)
	check(sim.soldiers.is_empty() and guard_draws().is_empty(),"dead preplaced guards leave no immortal layout image")
func teleport_scene() -> void:
	await open_stage(6);await dismiss();await make_tower("5","mage",["tower_mage_2","tower_mage_3","tower_arcane_wizard"])
	var sim=battle.sim;sim.soldiers.clear();sim.enemies.clear();sim.spawn_queue.clear()
	var tower: Dictionary=sim.tower_by_id("5")
	check(sim.command("upgrade_power",{"id":"5","power":"teleport"}),"native teleport purchase")
	for frame in 301:sim.step()
	var nearest:=INF;var node:=0;var path:=0
	for pi in sim.data.paths.paths.size():
		if not sim.data.paths.active[pi]:continue
		for ni in range(40,sim.data.paths.paths[pi][0].size()-10):
			var d: float=sim.distance(tower.pos,sim.vec(sim.data.paths.paths[pi][0][ni]))
			if d<nearest:nearest=d;node=ni;path=pi
	var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",0,path);e.node=node;e.progress=node;e.pos=sim.vec(sim.data.paths.paths[path][0][node]);e.hp=10000;e.max_hp=e.hp
	var fired:=false;var hidden:=false;var moved:=false;var initial:=node
	for frame in 180:
		sim.step()
		if not fired and sim.auras.size()>0:
			fired=true;await capture_followup("teleport_cast")
		if not hidden and e.get("hidden",false):hidden=true;await capture_followup("teleport_hidden")
		if e.node<initial-10 and not e.get("hidden",false):moved=true;await capture_followup("teleport_arrival");break
	check(fired and hidden and moved,"purchased tower automatically casts, hides and moves enemy backwards")
	for frame in 40:sim.step()
	check(int(e.get("stun_count",0))==0 and not e.get("hidden",false),"teleport restores enemy after action")
	await capture_followup("teleport_finished")
	check(sim.auras.is_empty() and not sim.modifiers.active.any(func(m):return m.template=="mod_teleport_arcane"),"teleport aura and modifier removed after action")
func _run() -> void:
	create_timer(120).timeout.connect(func():push_error("Followup native timeout");quit(1))
	suffix="%dx%d" % [root.size.x,root.size.y];layout_only=OS.get_cmdline_user_args().has("--layout-only")
	temporary="user://followup_%d" % Time.get_ticks_usec()
	app=AppScene.instantiate();app.settings_path=temporary+"_settings.json";app.slots_path=temporary+"_slots.json";root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,8):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	for level_id in [6,7]:await hover_and_ranges(level_id)
	if not layout_only:
		for mode in [1,2]:await guard_journey(mode)
		await sale_scene();await teleport_scene();await cannon_scene();await capture_followup("cannon_default_impact")
	var hashes:={}
	for path in ["tests/followup_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_arcane.gd","scripts/battle/dove_projectile.gd","scripts/battle/level01_sim.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	Writer.json_file("res://reports/followup_native_"+suffix+".json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"layout_only":layout_only,"guard_scenes":journeys,"captures":captures,"source_hashes":hashes})
	print("FOLLOWUP_NATIVE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	app.queue_free();await process_frame
	for ending in ["_settings.json","_slots.json"]:DirAccess.remove_absolute(temporary+ending)
	quit(0 if failures.is_empty() else 1)
