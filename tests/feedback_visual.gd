extends "res://tests/level06_visual.gd"
## Native feedback acceptance, using an isolated slot and bounded combat scenes.
var temporary: String
var guard_scenes: Array=[]
func map_balance(expected: int,label: String) -> void:
	await map_draw()
	var rows: Array=app.campaign_map.paint.audit.filter(func(r):return r.id=="upgrade_points")
	check(rows.is_empty() if expected==0 else rows.size()==1 and rows[0].text==str(expected),"native star balance refresh "+label)
	if expected==0:root.get_texture().get_image().save_png("res://reports/feedback_map_zero_"+suffix+".png")
func star_refresh() -> void:
	var before: Dictionary=app.campaign.data.duplicate(true)
	check(app.campaign.set_upgrade_level("archers",1),"star purchase fixture")
	await map_balance(20,"purchase")
	check(app.campaign.set_upgrade_level("archers",0),"star refund fixture")
	await map_balance(21,"refund")
	app.campaign.data.levels.clear();app.campaign.data.levels[1]={"stars":1,1:2};app.campaign.save()
	app.campaign.set_upgrade_level("archers",1);await map_balance(0,"zero hides star")
	app.campaign.reset_upgrades();await map_balance(1,"reset")
	app.campaign.data=before;app.campaign.save()
	var reload=preload("res://scripts/services/campaign_progress.gd").new();reload.initialize(app.campaign.path)
	check(reload.upgrade_summary().hint_available==21,"star balance reloads from independent slot")
	app._return_to_menu();app.menu._select_slot(2);await app.map_ready;await map_balance(0,"empty slot")
	app._return_to_menu();app.menu._select_slot(1);await app.map_ready;await map_balance(21,"return to original test slot")
func open_stage(id: int, mode: int=1) -> void:
	if is_instance_valid(app.battle):app._return_to_map();await app.map_ready
	app._start_level(id,mode,2);battle=app.battle;battle.set_process(false)
	await process_frame
func photograph(label: String) -> void:
	await draw_frame()
	if label=="dual_tower_notice":await create_timer(0.35).timeout;await draw_frame()
	var path:="res://reports/feedback_%s_%s.png" % [label,suffix]
	root.get_texture().get_image().save_png(path)
	check(battle.draw_list.all(func(d):return not battle._frame(d.frame).is_empty()),"feedback frames resolve "+label)
	for row: Dictionary in battle.interface.paint.audit:check(row.fits,"feedback text fits "+str(row.id)+" "+label)
	captures.append({"state":label,"path":path})
func site_hover(id: String,label: String) -> void:
	battle.selected="";await hover(battle.world(battle.sim.tower_by_id(id).pos))
	check(battle.tower_hover_id==id and battle.pick_tower(battle.sim.tower_by_id(id).pos)==id,"same hover and click picker "+label)
	check(battle.draw_list.any(func(d):return d.frame.ends_with("_over")),"source base hover drawn "+label)
	await photograph(label)
	await click(battle.world(battle.sim.tower_by_id(id).pos));await create_timer(0.15).timeout
	await hover(Vector2(20,80));check(battle.tower_hover_id==id,"selected base remains lit "+label)
	battle.sim.paused=true;await draw_frame();check(battle.tower_hover_id=="","pause clears base "+label)
	battle.sim.paused=false;battle.targeting="fire";await draw_frame();check(battle.tower_hover_id=="","casting clears base "+label)
	battle.targeting="";battle.selected="";await hover(Vector2(20,80));check(battle.tower_hover_id=="","pointer exit clears base "+label)
func make_tower(id: String,kind: String,upgrades: Array) -> void:
	battle.sim.gold=10000
	check(battle.sim.command("build",{"id":id,"type":kind}),"fixture build "+id)
	for frame in 30:battle.sim.step()
	for target in upgrades:check(battle.sim.command("upgrade",{"id":id,"upgrade_to":target}),"fixture upgrade "+target)
func power_steps(id: String,power: String) -> void:
	var t: Dictionary=battle.sim.tower_by_id(id)
	for level in range(int(battle.sim.tower_template(t).powers[power].max_level)+1):
		await menu(id);await hover(hit("upgrade_power",{"id":id,"power":power}).rect.get_center());await photograph(power+str(level))
		var rows: Array=battle.interface.paint.audit.filter(func(r):return r.id=="power_description")
		check(rows.size()==1,"rich tooltip drawn "+power+str(level))
		if rows.size()==1:
			check(rows[0].text.contains("→")== (level>0 and level<int(battle.sim.tower_template(t).powers[power].max_level)),"native current to next numeric diff "+power+str(level))
		if level<int(battle.sim.tower_template(t).powers[power].max_level):
			await action("upgrade_power",{"id":id,"power":power})
			check(t.powers[power]==level+1,"native power purchase "+power+str(level))
	battle.selected="";await hover(Vector2(20,80))
func passing_guards(mode: int) -> void:
	await open_stage(6,mode);await dismiss()
	var sim=battle.sim;sim.spawn_queue.clear();sim.gold=10000
	for frame in 80:sim.step()
	for s: Dictionary in sim.soldiers.duplicate():
		var guard_id: int=s.id
		var nearest:=INF;var chosen: Array=[]
		for pi in sim.data.paths.paths.size():
			if not sim.data.paths.active[pi]:continue
			for spi in sim.data.paths.paths[pi].size():
				var path: Array=sim.data.paths.paths[pi][spi]
				for ni in range(8,path.size()-1):
					var dist: float=sim.distance(s.rally_center,sim.vec(path[ni]))
					if dist<nearest:nearest=dist;chosen=[pi,spi,ni]
		var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",chosen[1],chosen[0]);e.node=chosen[2]-8;e.progress=e.node;e.pos=sim.vec(sim.data.paths.paths[e.path][e.subpath][e.node])
		var acquired:=-1
		# Observe each actual placement with the other guards out of the scene.
		var others: Array=sim.soldiers.filter(func(u):return u.id!=guard_id);sim.soldiers=[s]
		for frame in 240:
			sim.step()
			if s.target==e.id:acquired=sim.tick;break
		check(acquired>=0,"passing source-path enemy intercepted mode%d guard%d" % [mode,guard_id])
		if acquired>=0:
			for frame in 24:sim.step()
			await photograph("guard_%d_%d" % [mode,guard_id])
			var replacement: Dictionary=sim._spawn_enemy("enemy_goblin",e.subpath,e.path);replacement.node=e.node;replacement.progress=e.node;replacement.pos=e.pos+Vector2(4,0)
			sim.damage(e,9999,1)
			for frame in 80:
				sim.step()
				if s.target==replacement.id:break
			check(s.target==replacement.id,"guard reacquires after kill mode%d guard%d" % [mode,guard_id])
			sim.damage(replacement,9999,1)
			for frame in 140:sim.step()
			check(s.target==0 and s.pos.is_equal_approx(s.dest),"guard returns to post mode%d guard%d" % [mode,guard_id])
		guard_scenes.append({"mode":mode,"guard":guard_id,"path":chosen,"first_acquisition_tick":acquired})
		sim.enemies.clear();sim.soldiers.append_array(others)
	var victim: Dictionary=sim.soldiers[-1];sim.damage(victim,9999,1);sim.tick+=5
	await photograph("guard_death_%d" % mode)
	sim.tick=victim.dead_at+sim.frames(sim.templates[victim.template].health.dead_lifetime)+1;sim.step()
	check(sim.unit_by_id(victim.id).is_empty(),"preplaced guard corpse cleaned mode%d" % mode)
func cannon_scene() -> void:
	await open_stage(6);await dismiss();await make_tower("5","engineer",[])
	var sim=battle.sim;var tower: Dictionary=sim.tower_by_id("5");sim.enemies.clear();sim.effects.clear();sim.tick=600;tower.attack_at=sim.tick
	var nearest:=INF;var chosen: Array=[]
	for pi in sim.data.paths.paths.size():
		for ni in sim.data.paths.paths[pi][0].size():
			var d: float=sim.distance(tower.pos,sim.vec(sim.data.paths.paths[pi][0][ni]))
			if d<nearest:nearest=d;chosen=[pi,ni]
	var e: Dictionary=sim._spawn_enemy("enemy_goblin",0,chosen[0]);e.node=chosen[1];e.progress=e.node;e.pos=sim.vec(sim.data.paths.paths[e.path][0][e.node]);e.hp=1000;e.max_hp=1000
	for frame in 30:
		sim._tower_step(tower)
		if not sim.projectiles.is_empty():break
		sim.tick+=1
	check(sim.projectiles.size()==1,"native cannon fires at stationary source node")
	if sim.projectiles.is_empty():return
	var p: Dictionary=sim.projectiles[0]
	for frame in 16:sim.tick+=1;sim._bullet_step(p)
	await photograph("cannon_flight")
	while not p.done:sim.tick+=1;sim._bullet_step(p)
	await photograph("cannon_impact")
	check(not sim.effects.is_empty() and sim.effects.all(func(fx):return fx.pos.is_equal_approx(p.pos)),"native actual explosion and crater share impact")
func _run() -> void:
	create_timer(180).timeout.connect(func():push_error("Feedback native timeout");quit(1))
	suffix="%dx%d" % [root.size.x,root.size.y];layout_only=OS.get_cmdline_user_args().has("--layout-only")
	temporary="user://feedback_%d" % Time.get_ticks_usec()
	app=AppScene.instantiate();app.settings_path=temporary+"_settings.json";app.slots_path=temporary+"_slots.json";root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,8):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20,"unlock_towers":preload("res://scripts/services/campaign_levels.gd").load_definition(id).layout.get("unlock_towers",[])})
	await map_draw();root.get_texture().get_image().save_png("res://reports/feedback_map_stars_"+suffix+".png")
	check(app.campaign_map.paint.audit.any(func(r):return r.id=="upgrade_points" and r.font_role=="numbers" and r.fits),"map star numeral inside source label")
	if not layout_only:await star_refresh()
	await open_stage(6);await photograph("dual_tower_notice");await dismiss()
	await site_hover("1","grass_empty")
	await make_tower("1","mage",["tower_mage_2","tower_mage_3","tower_arcane_wizard"])
	await site_hover("1","grass_built")
	for power in ["disintegrate","teleport"]:await power_steps("1",power)
	await make_tower("2","barrack",["tower_barrack_2","tower_barrack_3","tower_paladin"])
	for power in ["healing","holystrike","shield"]:await power_steps("2",power)
	await make_tower("3","archer",["tower_archer_2","tower_archer_3","tower_ranger"])
	for power in ["poison","thorn"]:await power_steps("3",power)
	if not layout_only:
		for mode in [1,2]:await passing_guards(mode)
		await cannon_scene()
	await open_stage(5,3);await dismiss();battle.sim.gold=10000
	check(battle.sim.command("upgrade",{"id":"5","upgrade_to":"tower_elf"}),"source mercenary repair fixture")
	await power_steps("5","bleed")
	await open_stage(7);await dismiss();await site_hover("1","snow_empty")
	await make_tower("1","archer",["tower_archer_2","tower_archer_3","tower_musketeer"])
	await site_hover("1","snow_built")
	for power in ["sniper","shrapnel"]:await power_steps("1",power)
	var hashes:={}
	for path in ["tests/feedback_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_ui_layout.gd","scripts/battle/dove_power_preview.gd","scripts/battle/level01_sim.gd","scripts/battle/dove_paladin.gd","scripts/map/map_interface.gd","scripts/map/upgrades_room.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	if not preload("res://tests/report_writer.gd").json_file("res://reports/feedback_native_"+suffix+".json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"guard_scenes":guard_scenes,"layout_only":layout_only,"source_hashes":hashes,"browser_tested":false}):quit(1);return
	print("FEEDBACK_NATIVE: ","PASS" if failures.is_empty() else failures," checks=",checks)
	app.queue_free();await process_frame
	for ending in ["_settings.json","_slots.json"]:DirAccess.remove_absolute(temporary+ending)
	quit(0 if failures.is_empty() else 1)
