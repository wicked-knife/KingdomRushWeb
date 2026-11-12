extends "res://tests/verify_level11.gd"
## Bounded source comparisons; no challenge victory search.
func fresh(mode:int=1):
	var data:=Levels.load_definition(12,mode,2)
	check(not data.is_empty(),"twelfth loads %d: %s"%[mode,Levels.last_error])
	var sim=Sim.new(data,42);sim.notices.clear();return sim

func hashes12() -> Dictionary:
	var out:Dictionary={}
	for path:String in ["tests/verify_level12.gd","tests/fixtures/level12_source.json","data/campaign_content.json","data/level12/definition.json","scripts/battle/dove_veznan.gd","scripts/battle/controllers/level12.gd","scripts/battle/battle_view.gd","scripts/battle/dove_unit_info.gd","scripts/battle/dove_behaviors.gd","scripts/battle/level01_sim.gd","scripts/app_root.gd","scripts/ui/kr1_ending.gd"]:out[path]=FileAccess.get_sha256("res://"+path)
	return out

func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level12_source.json")
	var template:Dictionary=Levels.load_definition(12).templates.eb_veznan
	for field:String in source.boss_fields:
		var actual:Variant=template
		for part:String in field.split("."):actual=actual[part]
		check(source_subset12(source.boss_fields[field],actual),"raw Lua evaluated boss overrides "+field)
	check(Levels.supports(12,3) and not Levels.supports(13) and not Levels.supports(12,1,3),"twelve levels and normal difficulty")
	for mode in [1,2,3]:
		var sim=fresh(mode)
		check(sim.gold==[1300,1600,2800][mode-1] and sim.lives==[20,1,1][mode-1],"source economy %d"%mode)
		check(sim.towers.size()==13 and sim.data.locations.entrances.size()==2 and sim.veznan.portals.size()==3,"source layout counts %d"%mode)
		check(sim.data.waves==source.modes[str(mode)],"complete source waves %d"%mode)
		var layout:Dictionary=sim.data.layout.duplicate(true)
		for e:Dictionary in layout.entities_list:e.template=str(e.template).split("__")[0]
		var expected_layout:Dictionary=source.layout.duplicate(true)
		expected_layout.entities_list=expected_layout.entities_list.filter(func(e):return int(e.get("editor.game_mode",0)) in [0,mode])
		check(equivalent(layout,expected_layout),"complete source layout %d"%mode)
		check(not sim.data.layout.locked_hero and sim.data.layout.level_mode_overrides[mode-1].max_upgrade_level==6,"hero and technology cap %d"%mode)
		check((sim.veznan.boss_id>0)==(mode==1),"boss campaign only %d"%mode)
		check(sim.controller.victory_route(sim)==("kr1_end" if mode==1 else ""),"ending route %d"%mode)
		for kind:String in Sim.TYPES:check(sim.tower_locked("tower_build_"+kind)==(mode==3 and kind=="engineer"),"restriction %d/%s"%[mode,kind])
		timeline11(mode)
	for scenario:String in source.blocks:block12(scenario)
	for scenario:String in source.boss:boss12(scenario)
	for scenario:String in source.melee:melee12(scenario)
	portal12();aura12()
	mechanisms12()
	write8("level12_comparisons",comparisons);write8("level12_timelines",timeline_report)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"independent_modes":3,"timeline_waves":source.timelines["1"].size()+7,"births":births,"source_scenarios":source.boss.size()+source.blocks.size()+source.melee.size()+2,"full_replays":false,"source_hashes":hashes12()}
	write8("level12_logic",report);print("LEVEL12: ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func block12(scenario:String) -> void:
	var sim=fresh();var tower:Dictionary=sim.towers[0];var actual:Array=[]
	sim.tick=0;sim.veznan.block_tower(sim,tower,1);var last:="start";var count:=0
	actual.append(["animation",0,"start"])
	sim.event.connect(func(kind,data):
		if kind=="sound":actual.append(["sound",sim.tick,data.id]))
	for n in 401:
		sim.tick=n
		if scenario=="click" and n in [40,41,42]:sim.command("tower_click",{"id":tower.id})
		sim.veznan.step_blocks(sim)
		if not sim.veznan.blocks.is_empty():
			var phase:String=sim.veznan.blocks[0].phase
			if phase!=last:actual.append(["animation",n,phase]);last=phase
		if int(tower.get("block_count",0))!=count:count=tower.get("block_count",0);actual.append(["block",n,count])
		if sim.veznan.blocks.is_empty():actual.append(["remove",n,"mod_veznan_tower"]);break
	var expected:Array=source.blocks[scenario].duplicate(true)
	actual.sort_custom(event_order12);expected.sort_custom(event_order12)
	compare8("source tower block "+scenario,expected,actual,0)
	check(not tower.blocked and count==0,"block releases after animation "+scenario)

func source_subset12(expected:Variant,actual:Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary:return false
		for key in expected:
			if not actual.has(key) or not source_subset12(expected[key],actual[key]):return false
		return true
	if expected is Array:
		if not actual is Array or actual.size()!=expected.size():return false
		for i in expected.size():
			if not source_subset12(expected[i],actual[i]):return false
		return true
	return equivalent(expected,actual)

func event_order12(a:Array,b:Array) -> bool:return a[1]<b[1] or a[1]==b[1] and str(a)<str(b)

func boss12(scenario:String) -> void:
	var sim=fresh();var boss:Dictionary=sim.unit_by_id(sim.veznan.boss_id);var t:Dictionary=sim.templates.eb_veznan
	sim.soldiers.clear();sim.towers.clear();boss.pos=Vector2(500,350);boss.hp=4000
	if scenario!="lifecycle":sim._soldier("soldier_elemental" if scenario=="elemental" else "soldier_militia","",0,Vector2(510,350),Vector2(510,350))
	var phases:Array=[];var last:="";var drains:Array=[];var animations:Array=[]
	for n in 1601:
		sim.tick=n;sim.wave=1 if n>=32 else 0
		if n in ([200,400,700] if scenario=="lifecycle" else [200,700,1100]):boss.veznan.signal=true
		boss.stun_count=1 if scenario=="soul_stun" and n>=630 and n<640 else 0
		if scenario=="soul_phase" and n==630:boss.veznan.signal=true
		sim.veznan.step_enemy(sim,boss,t)
		if boss.state_at==n and str(boss.state).begins_with("soulDrain"):animations.append(["animation",n,boss.state])
		if n==380 and not sim.soldiers.is_empty():sim.soldiers[0].pos=boss.pos+Vector2(10,0)
		var phase:String=boss.veznan.phase
		if phase=="waiting":phase="idle"
		elif phase=="transform":phase="battle"
		if phase!=last:phases.append([n,phase]);last=phase
		for s:Dictionary in sim.soldiers:
			if s.hp<=0 and not drains.has(s.id):drains.append(s.id)
	compare8("source boss phases "+scenario,source.boss[scenario].phases,phases,0)
	var expected_drains:int=0
	var expected_animations:Array=[]
	for row:Array in source.boss[scenario].events:
		if row[0]=="damage":expected_drains+=1
		if row[0]=="animation" and str(row[2]).begins_with("soulDrain"):expected_animations.append(row)
	compare8("source soul animations "+scenario,expected_animations,animations,0)
	check(drains.size()==expected_drains,"source soul victims "+scenario)
	check(sim.veznan.complete and boss.hidden,"death-end gates victory "+scenario)

func mechanisms12() -> void:
	var sim=fresh();var boss:Dictionary=sim.unit_by_id(sim.veznan.boss_id)
	boss.veznan.phase="battle";boss.ignore_damage=false;boss.hp=10
	check(sim.damage(boss,100000,1)==0 and boss.hp==10 and boss.veznan.signal,"human lethal intercept")
	sim.veznan.step_enemy(sim,boss,sim.templates.eb_veznan)
	check(boss.veznan.phase=="transform" and boss.health_bar_hidden,"lethal transforms before death")
	sim.tick+=Sim.Behaviors.Veznan.duration(sim,boss,"demonTransform");sim.veznan.step_enemy(sim,boss,sim.templates.eb_veznan)
	check(boss.max_hp==7999*1.5 and boss.speed_override==18 and boss.portrait=="info_portraits_enemies_0072","demon hp speed portrait")
	check(sim.unit_template(boss).unit.hit_offset.y==55 and UnitInfo.snapshot(boss,sim.templates,sim.data.ui.strings).cooldown==2.5,"demon runtime consumers")
	sim.damage(boss,1000000,1);sim.veznan.step_enemy(sim,boss,sim.templates.eb_veznan)
	check(sim.veznan.hud_hidden and not sim.controller.can_finish(sim),"no early death victory")
	sim.lives=0;sim.step();check(sim.result=="defeat","zero lives precedes victory")
	sim.reset();check(sim.veznan.blocks.is_empty() and sim.veznan.souls.is_empty() and not sim.veznan.hud_hidden and sim.veznan.portals.all(func(p):return p.queue.is_empty() and not p.signal),"restart clears all stage state")
	for p:Dictionary in sim.veznan.portals:p.signal=true
	for n in 600:sim.tick=n;sim.veznan.step_portals(sim)
	check(sim.spawn_log.any(func(e):return e.origin=="veznan_portal") and sim.veznan.portals.all(func(p):return not p.signal and p.state=="idle"),"portals reset after closing")
	for p:Dictionary in sim.veznan.portals:p.signal=true
	var count:int=sim.spawn_log.size()
	for n in range(600,1200):sim.tick=n;sim.veznan.step_portals(sim)
	check(sim.spawn_log.size()>count,"portals repeat")
	check(sim.controller.extra_fire_point(Vector2(96,320)) and not sim.controller.extra_fire_point(Vector2(94,320)),"extra fire area")

func melee12(scenario:String) -> void:
	var sim=fresh();var boss:Dictionary=sim.unit_by_id(sim.veznan.boss_id)
	sim.soldiers.clear();boss.pos=Vector2(500,350);boss.veznan.phase="battle" if scenario=="human" else "demon"
	if scenario!="human":boss.prefix=sim.templates.eb_veznan.demon.sprites_prefix
	var target:Dictionary=sim._soldier("soldier_militia","",0,Vector2(510,350),Vector2(510,350));target.hp=100000;target.max_hp=100000
	sim.tick=90;sim.veznan.melee(sim,boss,target);var hits:Array=[]
	for n in range(90,201):
		sim.tick=n;boss.stun_count=1 if scenario=="demon_stun" and n>=116 and n<125 else 0
		var previous:float=target.hp
		sim.veznan._job(sim,boss)
		if target.hp<previous:hits.append(["hit",n,4 if scenario=="human" else 2])
	compare8("source melee hits "+scenario,source.melee[scenario],hits,0)

func portal12() -> void:
	var sim=fresh();sim.enemies.clear()
	sim.veznan.portals=sim.veznan.portals.filter(func(p):return p.index==3)
	var actual:Array=[]
	for n in 751:
		sim.tick=n
		if n in [0,400]:sim.veznan.portals[0].signal=true
		var before:int=sim.spawn_log.size();sim.veznan.step_portals(sim)
		for row:Dictionary in sim.spawn_log.slice(before):
			var e:Dictionary=sim.enemies[-1]
			actual.append([row.tick,row.type,row.path,e.node]);check(e.subpath in [0,1,2],"portal random exit subpath legal")
	compare8("source portal births and repeated trigger",source.portal_births,actual,0)
	check(not sim.veznan.portals[0].signal,"portal resets source signal")

func aura12() -> void:
	var sim=fresh();sim.veznan.soul_aura={"pos":Vector2(500,350),"count":0,"delay":10,"next":0}
	var actual:Array=[]
	for n in 181:
		sim.tick=n;var before:int=sim.veznan.souls.size();sim.veznan.step_souls(sim)
		for soul:Dictionary in sim.veznan.souls.slice(before):actual.append([n,soul.phase])
	compare8("source accelerating sixty souls",source.aura_births,actual,0.000001)
	check(sim.veznan.soul_aura.is_empty(),"source aura entity removed after final wait")
