extends "res://tests/verify_level08.gd"
## Bounded source programs and lifecycle checks, without a victory search.
const Anim9=preload("res://scripts/battle/dove_animation.gd")

func fresh(mode:int=1):
	var data:=Levels.load_definition(9,mode)
	check(not data.is_empty(),"ninth definition loads %d: %s"%[mode,Levels.last_error])
	if data.is_empty():return null
	var sim=Sim.new(data,42);sim.notices.clear();return sim

func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level09_source.json")
	check(Levels.supports(9,3) and not Levels.supports(10),"ninth published; tenth preview")
	for mode in [1,2,3]:
		var sim=fresh(mode)
		if sim==null:quit(1);return
		check(sim.data.waves==source.modes[str(mode)],"complete ninth waves %d"%mode)
		var layout:Dictionary=source.layout.duplicate(true)
		layout.entities_list=layout.entities_list.filter(func(e):return int(e.get("editor.game_mode",0)) in [0,mode])
		var actual:Dictionary=sim.data.layout.duplicate(true)
		for e:Dictionary in actual.entities_list:e.template=str(e.template).split("__")[0]
		check(equivalent(actual,layout),"complete ninth layout %d"%mode)
		check(sim.gold==[800,2000,2400][mode-1] and sim.lives==(20 if mode==1 else 1),"ninth economy %d"%mode)
		check(sim.towers.size()==15 and sim.data.waves.groups.size()==[19,6,1][mode-1],"ninth sites and wave count %d"%mode)
		check(not sim.tower_locked("tower_sorcerer") and not sim.tower_locked("tower_sunray"),"new towers immediately usable %d"%mode)
		if mode==3:
			check(sim.towers.filter(func(t):return t.template=="tower_mage_1" and t.spent==0).size()==9,"nine free iron mages")
			for kind:String in Sim.TYPES:check(sim.tower_locked("tower_build_"+kind)==(kind!="mage"),"iron ban "+kind)
		timeline(mode)
	for scenario:String in source.towers:tower9(scenario)
	freeze9();cast9();death9();spawns9();polymorph9();elemental9();enemies9();frozen_branches9();dependencies9();progression9()
	var paths:Array=["scripts/battle/dove_jt.gd","scripts/battle/dove_sunray.gd","scripts/battle/dove_sorcerer.gd","scripts/battle/controllers/level09.gd","scripts/battle/dove_behaviors.gd","scripts/battle/level01_sim.gd","scripts/battle/dove_modifiers.gd","scripts/battle/dove_enemy_melee.gd","scripts/battle/dove_advanced_barrack.gd","data/campaign_content.json","data/level09/definition.json","tests/fixtures/level09_source.json","tests/verify_level09.gd"]
	var hashes:Dictionary={}
	for path:String in paths:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("level09_logic",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"independent_modes":3,"timeline_waves":26,"births":births,"source_tower_scenarios":source.towers.size(),"full_replays":false,"source_hashes":hashes})
	write8("level09_timelines",timeline_report);write8("level09_comparisons",comparisons)
	print("LEVEL09: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks," births=",births)
	quit(0 if failures.is_empty() else 1)

func tower9(scenario:String) -> void:
	var sim=fresh();var kind:String=scenario.split("_")[0]
	var tower:Dictionary=buy(sim,"mage","1","tower_"+kind)
	sim.enemies.clear();sim.soldiers.clear();sim.projectiles.clear();sim.tick=0
	tower.pos=Vector2(500,350);tower.rally=Vector2(500,350)
	sim.Behaviors.Sorcerer.initialize(sim,tower) if kind=="sorcerer" else sim.Behaviors.Sunray.initialize(sim,tower)
	if scenario.split("_")[1] in ["skills","lethal","border","boss"]:
		for power:String in tower.powers:
			tower.powers[power]=int(sim.tower_template(tower).powers[power].max_level)
			sim.behaviors.power_upgraded(sim,tower,power)
	if not scenario.ends_with("empty"):
		for i in range(1,4):
			var e:Dictionary=sim._spawn_enemy("enemy_slayer",0);e.id=i;e.pos=Vector2(560+i*10,350);e.hp=100000;e.max_hp=100000;e.progress=100-i
			if scenario.ends_with("lethal") or scenario.ends_with("boss"):e.hp=10
			if scenario.ends_with("border"):e.hp=320;e.magic_armor=0
			if scenario.ends_with("boss"):e.vis=sim.templates[e.template].vis.duplicate();e.vis.flags=int(e.vis.flags)|32
	var actual:Array=[]
	var initial_gold:int=sim.gold
	for n in 1001:
		sim.tick=n;sim.behaviors.tower_step(sim,tower)
		for p:Dictionary in sim.projectiles:
			var b:Dictionary=sim.templates[p.template].bullet
			actual.append([n,p.template,p.target,p.damage_factor,float(b.damage_min)+float(b.get("damage_inc",0))*int(p.get("level",0)) if kind=="sunray" else b.damage_min,float(b.damage_max)+float(b.get("damage_inc",0))*int(p.get("level",0)) if kind=="sunray" else b.damage_max])
		sim.projectiles.clear()
	var expected:Variant=source.towers[scenario].shots
	compare8("source tower "+scenario,[] if expected is Dictionary else expected,actual)
	if kind=="sunray":check(sim.gold-initial_gold==int(source.towers[scenario].gold),"source tower perks "+scenario)

func freeze9() -> void:
	var sim=fresh();var tower:Dictionary=buy(sim,"mage","1","tower_sorcerer")
	sim.tick=0;sim.jt.freeze(sim,tower,99)
	var actual:Array=[]
	for n in 181:
		sim.tick=n
		if n in [35,38,41]:check(sim.command("tower_click",{"id":"1"}),"freeze click proxy")
		sim.jt.step_freezes(sim)
		var f:Dictionary={} if sim.jt.freezes.is_empty() else sim.jt.freezes[0]
		actual.append([n,int(tower.get("block_count",0)),f.get("phase","") in ["wait","click_end"],f.get("state","end"),int(f.get("fade_at",65 if f.is_empty() else -1)),f.is_empty()])
	compare8("source frozen tower every frame",source.freezes,actual)
	check(not tower.blocked,"freeze releases tower")

func death9() -> void:
	var sim=fresh();sim.enemies.clear();sim.tick=0
	var jt:Dictionary=sim._spawn_enemy("eb_jt",0);jt.hp=12000;jt.max_hp=12000
	check(sim.damage(jt,12000,1)==0 and jt.hp==12000 and jt.dying,"JT lethal damage intercepted")
	var actual:Array=[]
	for n in 401:
		sim.tick=n
		if n==250:check(sim.command("unit_click",{"id":jt.id}),"JT final click accepted")
		sim._enemy_step(jt)
		actual.append([n,jt.hp,jt.state,jt.ignore_damage,jt.boss.death_handled])
	compare8("source JT death indefinite tap and end",source.jt_death,actual)
	check(jt.boss.death_handled,"JT signals cleanup")

func cast9() -> void:
	var sim=fresh();sim.enemies.clear();sim.tick=0
	var boss:Dictionary=sim._spawn_enemy("eb_jt",0);boss.pos=Vector2(500,350)
	for i in 5:
		var tower:Dictionary=sim.towers[i];tower.id=str(101+i);tower.template="tower_mage_1";tower.type="mage";tower.pos=Vector2(510+i*10,350)
	var actual:Array=[];var seen:int=0
	for n in 421:
		sim.tick=n;sim.Behaviors.Jt.step(sim,boss,sim.templates.eb_jt)
		for f:Dictionary in sim.jt.freezes.slice(seen):actual.append([n,int(f.tower)])
		seen=sim.jt.freezes.size()
	compare8("source JT freeze cast and three actual targets",source.jt_cast,actual)

func spawns9() -> void:
	var sim=fresh();sim.enemies.clear();sim.tick=0
	var jt:Dictionary=sim._spawn_enemy("eb_jt",0);sim.spawn_log.clear()
	for n in 1201:
		sim.tick=n
		if n==1000:jt.dying=true
		sim.Behaviors.Jt.spawn_step(sim)
	var actual:Array=[]
	for row:Dictionary in sim.spawn_log:actual.append([row.tick,row.type,row.path,row.subpath])
	compare8("source JT aura spawn timestamps routes",source.jt_spawns,actual)

func polymorph9() -> void:
	for name:String in ["enemy_slayer","enemy_rocketeer"]:
		var sim=fresh();var old:Dictionary=sim._spawn_enemy(name,0);old.hp=1000;old.max_hp=1000;old.gold_override=31
		var speed:float=sim.templates[name].motion.max_speed
		sim.modifiers.apply(sim,"mod_polymorph_sorcerer",old,1,"1")
		var sheep:Dictionary=sim.enemies[-1]
		check(sheep.template==("enemy_sheep_fly" if name=="enemy_rocketeer" else "enemy_sheep_ground") and sheep.hp==500 and sim.unit_gold(sheep)==31,"polymorph transfers side health gold "+name)
		check(is_equal_approx(sim.templates[sheep.template].motion.max_speed*sim.modifiers.speed(sheep.id,sim),speed*1.25),"polymorph current speed transfer")
		compare8("source polymorph "+name,[source.polymorph[name]],[[sheep.template,sheep.hp,sim.unit_gold(sheep),sheep.lives_cost,sim.templates[sheep.template].motion.max_speed*sim.modifiers.speed(sheep.id,sim)]])
		check(old.hidden and old.hp==0 and sheep.pos==old.pos and sheep.path==old.path,"polymorph replaces at same route")
		check(sim.command("unit_click",{"id":sheep.id}),"sheep click")
		sim._enemy_step(sheep);check(sheep.hp==0,"low HP sheep needs one click")

func elemental9() -> void:
	var sim=fresh();var tower:Dictionary=buy(sim,"mage","1","tower_sorcerer")
	check(sim.command("upgrade_power",{"id":"1","power":"elemental"}),"hire elemental")
	sim.behaviors.tower_step(sim,tower)
	var s:Dictionary=sim.unit_by_id(tower.slots[0])
	check(s.max_hp==600 and is_equal_approx(s.armor,0.4) and s.state=="raise","elemental level one and raise lifecycle")
	check(sim.command("upgrade_power",{"id":"1","power":"elemental"}),"upgrade elemental")
	check(s.max_hp==700 and s.hp==700 and is_equal_approx(s.armor,0.5),"elemental upgrade heals and increments")
	check(sim.can_rally(tower) and sim.command("rally",{"id":"1","pos":tower.rally}),"elemental uses mage rally")
	var pos:Vector2=s.pos;sim.damage(s,10000,1);sim.tick+=301;sim.behaviors.tower_step(sim,tower)
	var replacement:Dictionary=sim.unit_by_id(tower.slots[0])
	check(replacement.id!=s.id and replacement.pos==pos and replacement.max_hp==700,"elemental respawns at corpse for free")

func enemies9() -> void:
	var sim=fresh();var e:Dictionary=sim._spawn_enemy("enemy_rocketeer",0)
	var speed:float=sim.templates[e.template].motion.max_speed
	sim.damage(e,1,1)
	check(e.already_speed_up and is_equal_approx(sim.modifiers.speed(e.id,sim),3.6041666666666665),"rocketeer first hit boost")
	sim.tick+=61;sim.modifiers.step(sim)
	check(is_equal_approx(sim.modifiers.speed(e.id,sim),1),"rocketeer two second release")
	sim.damage(e,1,1);check(sim.modifiers.active.is_empty(),"rocketeer boost once ever")
	check(speed>0,"rocketeer source motion")
	var boss:Dictionary=sim._spawn_enemy("eb_jt",0);boss.pos=Vector2(500,350);boss.hp=1000;boss.max_hp=2000
	var soldier:Dictionary=sim._soldier("soldier_elemental","",0,Vector2(555,350),Vector2(555,350));soldier.hp=600;soldier.max_hp=600
	boss.blockers=[soldier.id];boss.blocker=soldier.id;soldier.target=boss.id;sim.tick=100
	sim.Behaviors.EnemyMelee.melee(sim,boss,soldier,sim.templates.eb_jt)
	sim.tick=boss.mixed_melee_job.hit_at;sim.Behaviors.EnemyMelee.step(sim,boss,sim.templates.eb_jt)
	check(is_equal_approx(soldier.hp,180) and boss.hp==1100,"JT eat respects instakill resistance and heals per hit")
	var slayer:Dictionary=sim._spawn_enemy("enemy_slayer",0);slayer.hp=500;slayer.max_hp=1000
	var guard:Dictionary=sim._soldier("soldier_militia","",0,Vector2(600,350),Vector2(600,350));guard.hp=10000;guard.max_hp=10000
	slayer.pending={"at":sim.tick};slayer.attack_at=sim.tick+100
	sim._melee(slayer,guard,sim.templates.enemy_slayer);check(slayer.hp==520,"slayer heals four percent missing HP")
	slayer.silence_count=1;slayer.pending={"at":sim.tick};sim._melee(slayer,guard,sim.templates.enemy_slayer);check(slayer.hp==520,"silence suppresses slayer healing")

func frozen_branches9() -> void:
	for row:Array in [["archer","tower_ranger"],["archer","tower_musketeer"],["engineer","tower_bfg"],["mage","tower_arcane_wizard"],["mage","tower_sorcerer"],["mage","tower_sunray"],["barrack","tower_paladin"]]:
		var sim=fresh();var tower:Dictionary=buy(sim,row[0],"1",row[1]);tower.blocked=true;sim.projectiles.clear();sim.tick=1000
		var e:Dictionary=sim._spawn_enemy("enemy_slayer",0);e.pos=tower.pos+Vector2(30,0)
		for n in 10:sim.tick+=1;sim._tower_step(tower)
		check(sim.projectiles.is_empty() and tower.pending.is_empty() and tower.get("bfg",{}).get("job",{}).is_empty() and tower.get("musketeer",{}).get("job",{}).is_empty() and tower.get("arcane",{}).get("casting",{}).is_empty() and tower.get("sorcerer",{}).get("casting",{}).is_empty() and tower.get("sunray",{}).get("casting",{}).is_empty(),"frozen branch starts no attacks "+row[1])
		check(not sim.command("sell",{"id":"1"}) and not sim.command("rally",{"id":"1","pos":tower.rally}),"frozen branch rejects sale and rally "+row[1])

func dependencies9() -> void:
	for name:String in ["mod_jt_tower","jt_spawner_aura","enemy_sheep_fly","fx_mod_polymorph_sorcerer_big","soldier_elemental"]:
		var data:=Levels.load_definition(9);data.templates.erase(name)
		check(not Sim.Behaviors.validate(data,Levels.catalog()).is_empty(),"missing dependency rejected "+name)

func progression9() -> void:
	var p=Progress.new();p.initialize("user://level09_logic_%d.json"%Time.get_ticks_usec())
	for id in range(1,9):preload("res://tests/slot_fixture.gd").complete(p,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	check(p.is_playable(9) and not p.is_playable(10),"ninth entry unlock and tenth preview")
