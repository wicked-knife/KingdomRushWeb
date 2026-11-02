extends "res://tests/level07_visual.gd"
## Godot native input and actual render-queue checkpoints; constructed settlement.

func build9(id:String,target:String) -> void:
	battle.sim.gold=20000
	await menu(id);await action("build",{"id":id,"type":"mage"})
	for i in 30:battle.sim.step()
	for name:String in ["tower_mage_2","tower_mage_3"]:
		await menu(id);await action("upgrade",{"id":id,"upgrade_to":name})
	await menu(id);await capture("ninth_mage_branches_"+id)
	check(battle.hits.any(func(h):return h.action=="upgrade" and h.args.get("upgrade_to","")==target),"native ninth mage branch "+target)
	await hover(hit("upgrade",{"id":id,"upgrade_to":target}).rect.get_center());await capture("ninth_tooltip_"+target)
	await action("upgrade",{"id":id,"upgrade_to":target})
	var tower:Dictionary=battle.sim.tower_by_id(id)
	for power:String in tower.powers:
		var count:int=int(battle.sim.tower_template(tower).powers[power].max_level)-int(tower.powers[power])
		for rank in count:await menu(id);await action("upgrade_power",{"id":id,"power":power})
		await menu(id);await hover(hit("upgrade_power",{"id":id,"power":power}).rect.get_center());await capture("ninth_power_"+power)
		check(battle.interface.paint.audit.all(func(row):return row.fits),"native ninth tooltip fits "+power)
	battle.selected="";battle.hovered=""

func frame9(unit:Dictionary,state:String,label:String) -> void:
	await capture("ninth_"+label)
	var sprite:Dictionary=battle.sim.unit_template(unit).render.sprites[0]
	var expected:String=Anim.frame(sprite,battle.animations,{"state":state,"elapsed":battle.sim.tick-unit.state_at,"loop":unit.get("playback_loop",false)})
	check(battle.draw_list.any(func(d):return d.frame==expected),"native exact source frame "+label+" "+expected)

func cave9() -> void:
	var sim=battle.sim
	var source_layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/level09_source.json")).get("layout",{})
	var expected:Array=source_layout.get("entities_list",[]).filter(func(e):return e.get("render.sprites[1].name","")=="stage9_cave1")
	check(expected.size()==1,"source defines one cave foreground")
	await capture("ninth_cave_empty")
	var masks:Array=battle.draw_list.filter(func(d):return d.frame=="stage9_cave1")
	check(masks.size()==1,"cave foreground reaches actual render queue")
	if masks.is_empty():return
	var mask:Dictionary=masks[0]
	check(mask.pos==sim.vec(expected[0].pos) and mask.anchor==Vector2(0.5,0.08) and mask.z==3000 and mask.sort_y==100,"source cave position, anchor and depth")
	var enemy:Dictionary=sim._spawn_enemy("enemy_troll",0,1)
	for node:int in [0,8,20]:
		enemy.node=node;enemy.pos=sim.vec(sim.data.paths.paths[1][0][node])
		await capture("ninth_cave_node%d"%node)
		var foreground:int=-1;var actor:int=-1
		for i in battle.draw_list.size():
			var row:Dictionary=battle.draw_list[i]
			if row.frame=="stage9_cave1":foreground=i
			if row.pos==enemy.pos and row.frame.begins_with("troll_"):actor=i
		check(actor>=0 and foreground>actor,"cave covers source entrance path node %d"%node)
	sim.enemies.erase(enemy)

func frozen_order9(tower:Dictionary) -> void:
	var body:int=-1;var ice:int=-1;var tap:int=-1
	for i in battle.draw_list.size():
		var row:Dictionary=battle.draw_list[i]
		if row.z!=3000 or row.sort_y!=tower.pos.y:continue
		if int(row.get("draw_order",0)) in [2,3,4,5]:body=maxi(body,i)
		if row.frame.begins_with("boss_jt_tower_freeze_"):ice=i;check(row.draw_order==10,"ice consumes source draw_order 10")
		if row.frame.begins_with("boss_JT_tap_notxt_"):tap=i;check(row.draw_order==11,"tap consumes source draw_order 11")
	check(body>=0 and ice>body and tap>ice,"frozen ice and tap render above every tower layer "+tower.template)

func lifecycles9() -> void:
	var sim=battle.sim
	var sorcerer:Dictionary=sim.tower_by_id("1")
	var previous:Dictionary=sim.unit_by_id(sorcerer.slots[0])
	if not previous.is_empty():sim.damage(previous,10000,1);sim.tick+=301
	sim.behaviors.tower_step(sim,sorcerer)
	var elemental:Dictionary=sim.unit_by_id(sorcerer.slots[0])
	await frame9(elemental,"raise","elemental_raise")
	sim.tick=elemental.raise_until;sim._soldier_step(elemental)
	await capture("ninth_elemental_active")
	var old:Dictionary=sim._spawn_enemy("enemy_slayer",0);old.pos=Vector2(600,390);old.hp=600
	sim.modifiers.apply(sim,"mod_polymorph_sorcerer",old,1,"1")
	var sheep:Dictionary=sim.enemies[-1]
	await capture("ninth_polymorph")
	await click(battle.world(sheep.pos+Vector2(0,8)));sim._enemy_step(sheep)
	check(sheep.hp==0,"native sheep click damages")
	await frame9(sheep,"death","sheep_death")
	sim.tick=sheep.dead_at+Anim.duration(battle.animations,Anim.key(sim.templates[sheep.template].render.sprites[0],"death"))
	await capture("ninth_sheep_hidden")
	var sheep_frame:String=Anim.frame(sim.templates[sheep.template].render.sprites[0],battle.animations,{"state":"death","elapsed":sim.tick-sheep.dead_at,"loop":false})
	check(not battle.draw_list.any(func(d):return d.frame==sheep_frame),"native sheep hidden after death animation")
	var jt:Dictionary=sim._spawn_enemy("eb_jt",0);jt.pos=Vector2(660,440)
	sim.jt.freeze(sim,sorcerer,jt.id);sim.tick=sim.jt.freezes[0].end_at;sim.jt.step_freezes(sim)
	var sunray:Dictionary=sim.tower_by_id("2")
	sim.jt.freeze(sim,sunray,jt.id);sim.tick=sim.jt.freezes[1].end_at;sim.jt.step_freezes(sim)
	await capture("ninth_frozen_tower")
	frozen_order9(sorcerer);frozen_order9(sunray)
	var tap_before: Array = battle.draw_list.filter(func(d):return d.frame.begins_with("boss_JT_tap_notxt_" )).map(func(d):return d.frame)
	sim.tick += 3
	await capture("ninth_frozen_tap_motion")
	var tap_after: Array = battle.draw_list.filter(func(d):return d.frame.begins_with("boss_JT_tap_notxt_" )).map(func(d):return d.frame)
	check(tap_before.size()==2 and tap_after.size()==2 and tap_before!=tap_after,"native frozen hand changes source frame independently of ice")
	for i in 3:
		await click(battle.world(sorcerer.pos+Vector2(0,30)));sim.jt.step_freezes(sim);sim.tick+=1
	sim.jt.step_freezes(sim)
	check(sim.jt.freezes[0].phase=="end","native three tower clicks start thaw")
	sim.tick+=6;sim.jt.step_freezes(sim);check(not sorcerer.blocked,"native thaw releases tower")
	await capture("ninth_thaw_end")
	sim.tick+=30;sim.jt.step_freezes(sim);await capture("ninth_thaw_fade")
	sim.damage(jt,jt.hp,1);sim._enemy_step(jt);await frame9(jt,"death","jt_death")
	sim.tick+=Anim.duration(battle.animations,Anim.key(sim.templates.eb_jt.render.sprites[0],"death"));sim._enemy_step(jt)
	await capture("ninth_jt_wait_click")
	sim.tick+=120;sim._enemy_step(jt);check(jt.jt.phase=="tap","native JT waits beyond unused timeout")
	await click(battle.world(jt.pos+Vector2(0,50)));sim._enemy_step(jt)
	check(jt.jt.phase=="death_end","native JT click enters final animation")
	await frame9(jt,"death_end","jt_death_end")
	sim.tick+=Anim.duration(battle.animations,Anim.key(sim.templates.eb_jt.render.sprites[0],"death_end"));sim._enemy_step(jt);sim.tick+=1;sim._enemy_step(jt)
	check(jt.boss.death_handled,"native JT final cleanup")
	check(battle.sound_cache.has("JtDeath") and battle.sound_cache.has("JtExplode"),"native JT death audio resolves")

func _run() -> void:
	create_timer(180).timeout.connect(func():push_error("Ninth native timeout");quit(1))
	suffix="%dx%d"%[root.size.x,root.size.y];layout_only=OS.get_cmdline_user_args().has("--layout-only")
	app=AppScene.instantiate();app.settings_path="user://level09_native_settings.json";app.slots_path="user://level09_native_%d.progress"%Time.get_ticks_usec();root.add_child(app)
	await app.menu_ready;app.menu.start_button.pressed.emit();app.menu._select_slot(1);await app.map_ready
	for id in range(1,9):Fixture.complete(app.campaign,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	await enter(9,1);await capture("ninth_opening")
	check(battle.sim.gold==800 and battle.sim.towers.size()==15,"native ninth source opening")
	await cave9()
	await status_presentation9()
	await build9("1","tower_sorcerer");await build9("2","tower_sunray")
	if not layout_only:await lifecycles9()
	await restart();check(battle.sim.gold==800 and battle.sim.wave==0,"native ninth restart")
	await final_death9()
	battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await capture("ninth_victory");await action("map");await app.map_ready
	check("tower_sorcerer" not in app.campaign.data.locked_towers and "tower_sunray" not in app.campaign.data.locked_towers and not app.campaign.is_playable(10),"native map commits new towers and tenth preview")
	for mode in [2,3]:
		await enter(9,mode);await capture("ninth_mode%d"%mode)
		check(battle.sim.gold==[2000,2400][mode-2] and battle.sim.lives==1,"native ninth challenge economy %d"%mode)
		if mode==3:check(battle.sim.towers.filter(func(t):return t.template=="tower_mage_1" and t.spent==0).size()==9,"native iron free mages")
		battle.sim._finish("victory");battle.set_process(true);await create_timer(4.2).timeout;battle.set_process(false);await action("map");await app.map_ready
		check(app.campaign.record(9).get(mode,0)==2,"native ninth challenge settlement %d"%mode)
	var hashes:Dictionary={}
	for path:String in ["tests/level09_visual.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_sorcerer.gd","scripts/battle/dove_sunray.gd","scripts/battle/dove_jt.gd","scripts/battle/level01_sim.gd","data/level09/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level09_native_%s.json"%suffix,{"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"layout_only":layout_only,"source_hashes":hashes,"scope":"Godot native mouse, source frames and constructed settlement; no victory replay"})
	print("LEVEL09_NATIVE: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)

func status_presentation9() -> void:
	var sim = battle.sim
	var enemy: Dictionary = sim._spawn_enemy("enemy_marauder", 0)
	enemy.pos = Vector2(500, 360)
	sim.gold = 5201; sim.lives = 120; sim.wave = 2
	battle.selected_unit = enemy.id
	check(sim.modifiers.apply(sim,"mod_sorcerer_curse_dps",enemy,1,"1"),"source curse applied for native depth check")
	await capture("ninth_curse_depth_hud")
	var actor := -1
	var curse := -1
	for i in battle.draw_list.size():
		var row: Dictionary = battle.draw_list[i]
		if row.frame.begins_with("curse_"):
			curse = i
			check(row.sort_y == enemy.pos.y - 3,"curse depth uses feet and source minus three")
		if row.pos == enemy.pos and row.z == 3000: actor = i
	check(actor >= 0 and curse > actor,"native curse ring renders over ground below body")
	for row: Dictionary in battle.interface.paint.audit:
		if str(row.id).begins_with("hud:"):check(row.fits,"HUD visible glyphs fit "+row.id)
	sim.enemies.erase(enemy); sim.modifiers.clear(sim)
	battle.selected_unit = 0
	sim.gold = 800; sim.lives = 20; sim.wave = 0

func final_death9() -> void:
	var sim = battle.sim
	sim.notices.clear(); sim.spawn_queue.clear(); sim.pending_entities.clear(); sim.spawners.clear()
	sim.enemies.clear(); sim.wave = sim.data.waves.groups.size()
	var enemy: Dictionary = sim._spawn_enemy("enemy_marauder",0)
	enemy.pos = Vector2(500,360)
	sim.damage(enemy,enemy.hp,1)
	for i in 10:sim.step()
	await frame9(enemy,"death","last_enemy_death_before_victory")
	check(sim.result=="" and battle.victory_elapsed<0,"native last death plays before settlement starts")
	for i in 51:sim.step()
	await capture("ninth_last_enemy_death_complete")
	check(sim.result=="victory" and sim.tick-enemy.dead_at>=Anim.duration(battle.animations,Anim.key(sim.templates[enemy.template].render.sprites[0],"death")),"native victory starts after final source death and delay")
