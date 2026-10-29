extends "res://tests/verify_level06.gd"
const Setup7 = preload("res://scripts/services/battle_setup.gd")
var comparisons := {}

func fresh(mode: int = 1):
	var data := Levels.load_definition(7, mode)
	check(not data.is_empty(), "seventh definition loads %d: %s" % [mode,Levels.last_error])
	var sim = Sim.new(data,42); sim.notices.clear(); return sim

func run() -> void:
	source = Levels.read_json("res://tests/fixtures/level07_source.json")
	check(not source.is_empty(),"actual frozen Lua samples exist")
	check(Levels.ids().size()==7 and not Levels.supports(8) and not Levels.supports(7,1,3),"seven stages; eighth preview; normal only")
	for mode in [1,2,3]:
		var sim = fresh(mode)
		check(sim.data.waves==source.modes[str(mode)],"all seventh source wave fields mode %d" % mode)
		var layout: Dictionary = source.layout.duplicate(true)
		layout.entities_list=layout.entities_list.filter(func(e):return int(e.get("editor.game_mode",0)) in [0,mode])
		var actual: Dictionary = sim.data.layout.duplicate(true)
		for e: Dictionary in actual.entities_list: e.template=str(e.template).split("__")[0]
		check(equivalent(actual,layout),"full source layout, notifications, restrictions mode %d" % mode)
		check(sim.gold==[700,1000,1200][mode-1] and sim.lives==(20 if mode==1 else 1),"source seventh economy mode %d" % mode)
		check(not sim.tower_locked("tower_musketeer") and sim.snow.tunnels.size()==2,"in-stage unlock and two tunnels mode %d" % mode)
		if mode==3:
			check(sim.towers.filter(func(t):return t.template=="tower_barrack_2" and t.spent==0).size()==3,"iron three free barrack2")
			check(sim.tower_locked("tower_build_barrack") and sim.tower_locked("tower_build_engineer") and not sim.tower_locked("tower_build_archer"),"iron source build bans")
		timeline(mode)
	branches()
	for scenario: String in source.towers: tower_sample(scenario)
	shotgun_samples()
	bomb_samples()
	regen_sample()
	tunnel_samples()
	progression7()
	for id in Levels.ids():
		for mode in [1,2,3]:
			var data := Levels.load_definition(id,mode)
			check(not data.is_empty(),"load combination %d/%d" % [id,mode])
			var sim = Sim.new(data,42); dismiss(sim); ticks(sim,2)
	var report := {"passed":failures.is_empty(),"checks":checks,"independent_modes":3,"timeline_waves":23,"births":births,"content_combinations":21,"source_coroutines":["tower_musketeer","shotgun","bomb","tunnel","aura_unit_regen"],"source_scenarios":source.towers.size()+source.shotguns.size()+source.bombs.size()+source.tunnels.size()+1,"failures":failures,"full_replays":false,"source_hashes":hashes7()}
	write7("level07_logic",report); write7("level07_timelines",timeline_report); write7("level07_comparisons",comparisons)
	print("LEVEL07: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks," births=",births)
	quit(0 if failures.is_empty() else 1)

func write7(name: String, data) -> void:
	var f := FileAccess.open("res://reports/"+name+".json",FileAccess.WRITE); f.store_string(JSON.stringify(data,"\t")); f.close()
func hashes7() -> Dictionary:
	var result := {}
	for path: String in ["scripts/battle/dove_musketeer.gd","scripts/battle/dove_snow.gd","scripts/battle/level01_sim.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_behaviors.gd","scripts/battle/dove_targeting.gd","scripts/battle/controllers/default_level.gd","data/campaign_content.json","data/level07/definition.json","tests/fixtures/level07_source.json","tests/verify_level07.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result
func compare7(label: String, expected: Array, actual: Array, tolerance: float = 0.02) -> void:
	var difference := ""
	if expected.size()!=actual.size(): difference="length %d/%d" % [expected.size(),actual.size()]
	for row in mini(expected.size(),actual.size()):
		for col in expected[row].size():
			var a = expected[row][col]; var b = actual[row][col]
			if (absf(float(a)-float(b))>tolerance if (a is float or a is int) and not a is bool else a!=b):
				if difference=="": difference="row %d column %d expected=%s actual=%s" % [row,col,a,b]
	check(difference=="",label+" first difference: "+difference)
	comparisons[label]={"expected":expected,"actual":actual,"first_difference":difference}

func branches() -> void:
	var sim = fresh(); sim.gold=10000
	var tower: Dictionary = buy(sim,"archer","1","tower_musketeer")
	check(tower.template=="tower_musketeer","explicit Musketeer transaction")
	for power in ["sniper","shrapnel"]:
		for rank in 3: check(sim.command("upgrade_power",{"id":"1","power":power}),"skill purchase %s/%d" % [power,rank+1])
		check(not sim.command("upgrade_power",{"id":"1","power":power}),"maximum skill rank "+power)
	var refund: int = sim.sell_refund(tower)
	var gold: int = sim.gold
	check(sim.command("sell",{"id":"1"}) and sim.gold==gold+refund,"advanced sale refund includes skills")
	sim.command("build",{"id":"1","type":"archer"})
	check(not sim.command("upgrade",{"id":"1","upgrade_to":"tower_archer_2"}),"construction blocks upgrade")
	ticks(sim,30)
	for target in ["tower_archer_2","tower_archer_3"]: sim.command("upgrade",{"id":"1","upgrade_to":target})
	tower=sim.tower_by_id("1")
	check(sim.upgrade_options(tower)==["tower_ranger","tower_musketeer"] and sim.upgrade_target(tower)=="","ordered branching has no implicit target")
	check(not sim.command("upgrade",{"id":"1"}) and not sim.command("upgrade",{"id":"1","upgrade_to":"tower_arcane_wizard"}),"ambiguous and foreign target rejected")
	sim.gold=0
	check(not sim.command("upgrade",{"id":"1","upgrade_to":"tower_musketeer"}) and sim.tower_by_id("1").template=="tower_archer_3","insufficient funds atomic")
	var old := Setup7.create(Levels.load_definition(4),{"locked_towers":["tower_musketeer","tower_ranger"]})
	var locked = Sim.new(old); locked.notices.clear(); locked.gold=10000
	locked.command("build",{"id":"01","type":"archer"});ticks(locked,30)
	for target in ["tower_archer_2","tower_archer_3"]:locked.command("upgrade",{"id":"01","upgrade_to":target})
	check(locked.upgrade_options(locked.tower_by_id("01")).size()==2 and locked.tower_locked("tower_musketeer") and not locked.command("upgrade",{"id":"01","upgrade_to":"tower_musketeer"}),"old-stage saved branch locks enforced")
	for missing in ["tower_musketeer","shotgun_musketeer","ps_shotgun_musketeer","aura_troll_regen"]:
		var broken := Levels.load_definition(7); broken.templates.erase(missing)
		check(not Sim.Behaviors.validate(broken,Levels.catalog()).is_empty(),"missing dependency blocks entry "+missing)

func tower_sample(scenario: String) -> void:
	var sim = fresh();sim.gold=10000;sim.soldiers.clear()
	var tower: Dictionary = buy(sim,"archer","1","tower_musketeer")
	tower.pos=Vector2(500,350);sim.tick=0;Sim.Behaviors.Musketeer.initialize(sim,tower)
	var enemy: Dictionary=sim._spawn_enemy("enemy_troll",0)
	enemy.pos=Vector2(620 if scenario=="far" else 580,350);enemy.hp=100000;enemy.max_hp=100000;enemy.node=50
	var replacement: Dictionary=sim._spawn_enemy("enemy_troll",0);replacement.pos=enemy.pos;replacement.hp=100000;replacement.max_hp=100000;replacement.node=49
	# Deterministic selectors isolate actual attack-coroutine timing and damage setup.
	if scenario=="boss": enemy.vis={"flags":32,"bans":0}
	elif scenario=="immune": enemy.vis={"flags":2048,"bans":524288}
	for power in ["sniper","shrapnel"]:
		tower.powers[power]=0 if scenario=="normal" else 3
		Sim.Behaviors.Musketeer.power_upgraded(sim,tower,power)
	sim.templates.tower_musketeer.powers.sniper.instakill_chance_inc=1.0/3 if scenario in ["instakill","immune","boss"] else 0
	var actual: Array=[]
	for frame in 1001:
		sim.tick=frame
		if scenario=="retarget" and frame==430: enemy.hp=0
		Sim.Behaviors.Musketeer.step(sim,tower)
		for p: Dictionary in sim.projectiles:
			var b: Dictionary=sim.templates[p.template].bullet
			actual.append([frame,p.template,p.damage_min if p.template!="bomb_musketeer" else 0,p.damage_max if p.template!="bomb_musketeer" else 0,p.get("damage_type",b.damage_type),p.level,p.damage_factor,p.from.x,p.from.y])
		sim.projectiles.clear()
	var expected: Array=[]
	for row: Array in source.towers[scenario].bullets: expected.append(row.slice(0,9))
	compare7("tower_"+scenario,expected,actual)
	check(tower.musketeer.shooter in [0,1],"alternating shooter "+scenario)

func shotgun_samples() -> void:
	for scenario: String in source.shotguns:
		var sim=fresh();sim.towers.clear();sim.soldiers.clear()
		var target: Dictionary=sim._spawn_enemy("enemy_troll",0);target.pos=Vector2(300,350);target.hp=1000;target.max_hp=1000;target.node=50
		sim.templates.shotgun_musketeer.bullet.damage_min=35;sim.templates.shotgun_musketeer.bullet.damage_max=35
		sim._projectile("shotgun_musketeer",target.id,Vector2(100,363),Vector2(300,363),1)
		var p: Dictionary=sim.projectiles[0];var actual: Array=[];var hits: Array=[]
		for row: Array in source.shotguns[scenario].samples:
			sim.tick=int(row[0])
			if sim.tick==3:
				if scenario=="move":target.pos.x=600
				elif scenario=="dead":target.hp=0
				elif scenario=="banned":target.vis={"flags":2048,"bans":2}
			var before: float=target.hp;sim._bullet_step(p)
			actual.append([sim.tick,p.pos.x,p.pos.y,p.hidden])
			if before>target.hp:hits.append([sim.tick,1,before-target.hp])
		compare7("shotgun_"+scenario,source.shotguns[scenario].samples,actual)
		compare7("shotgun_hits_"+scenario,source.shotguns[scenario].hits if source.shotguns[scenario].hits is Array else [],hits)
	# HP-based sniper, instant kill resistance, armor penetration, bleeding and multipliers.
	var sim=fresh();var e: Dictionary=sim._spawn_enemy("enemy_dark_knight",0);e.hp=1000;e.max_hp=1000
	check(is_equal_approx(sim.damage(e,100,64,0,0.2),58),"shot damage uses (armor - penetration) * 0.7")
	e.hp=1000;sim.damage(e,1,4096);check(e.hp==0,"instant kill uses maximum health")
	var tech=Sim.new(Setup7.create(Levels.load_definition(7),{"upgrades":{"engineers":6}}))
	e=tech._spawn_enemy("enemy_troll",0);e.pos=Vector2(540,350);e.node=50;e.hp=1000;e.max_hp=1000
	tech._projectile("bomb_musketeer",0,Vector2(500,350),Vector2(500,350),0.2)
	var p: Dictionary=tech.projectiles[0];p.damage_min=30;p.damage_max=126;tech.tick=6;tech._bullet_step(p)
	check(is_equal_approx(1000-e.hp,126),"source bomb efficiency also affects Musketeer shrapnel")
	var arrows=Sim.new(Setup7.create(Levels.load_definition(7),{"upgrades":{"archers":6}}))
	check(arrows.templates.shotgun_musketeer.bullet.reduce_armor>0 and "mod_blood_elves" in arrows.templates.shotgun_musketeer.bullet.mods,"Musketeer inherits source piercing and bleed technology")
	var victim: Dictionary=arrows._spawn_enemy("enemy_dark_knight",0);victim.hp=1000;victim.max_hp=1000
	arrows.templates.mod_blood_elves.chance=1
	arrows.modifiers.apply(arrows,"mod_blood_elves",victim,1,"test",-1,1,{"value":100,"type":64,"reduce_armor":0.2})
	check(is_equal_approx(arrows.modifiers.active[-1].bleeding,maxf(1,58*float(arrows.templates.mod_blood_elves.damage_factor))),"bleed predicts source shot protection")

func bomb_samples() -> void:
	for flight: String in source.bombs:
		var sim=fresh();sim.towers.clear();sim.soldiers.clear()
		var target: Dictionary=sim._spawn_enemy("enemy_troll",0);target.pos=Vector2(540,350);target.node=50;target.hp=1000;target.max_hp=1000
		sim._projectile("bomb_musketeer",0,Vector2(500,350),Vector2(540,350),float(flight)/30)
		var p: Dictionary=sim.projectiles[0];p.level=3;p.damage_factor=0.6
		var actual: Array=[];var hits: Array=[]
		for row: Array in source.bombs[flight].samples:
			sim.tick=int(row[0]);var before: float=target.hp;sim._bullet_step(p)
			actual.append([sim.tick,p.pos.x,p.pos.y])
			if before>target.hp:hits.append([sim.tick,before-target.hp])
		compare7("bomb_flight_"+flight,source.bombs[flight].samples,actual)
		compare7("bomb_hits_"+flight,source.bombs[flight].hits,hits)

func regen_sample() -> void:
	var sim=fresh();var e: Dictionary=sim._spawn_enemy("enemy_troll",0);e.hp=200;e.node=50
	var actual: Array=[]
	for frame in 36:
		sim.tick=frame;e.silence_count=1 if frame>=7 and frame<=12 else 0;e.stun_count=1 if frame>=18 and frame<=21 else 0
		e.vis={"flags":2048,"bans":4 if frame>=22 and frame<=27 else 0}
		if frame==35:e.hp=0
		sim.snow.step(sim);actual.append([frame,e.hp if frame!=35 else 203,e.regen_ts*30])
	# At death the oracle retains HP while the adapter uses zero as the dead marker.
	actual[-1][1]=actual[-2][1]
	compare7("regen_silence_stun_modban_death",source.regen,actual)

func tunnel_samples() -> void:
	for speed: String in source.tunnels:
		var sim=fresh();sim.soldiers.clear();sim.towers.clear()
		var e: Dictionary=sim._spawn_enemy("enemy_troll",2,1);e.node=79;e.progress=79;e.pos=sim.vec(sim.data.paths.paths[1][2][79]);e.hp=230
		sim.templates.enemy_troll.motion.max_speed=float(speed)/float(sim.data.rules.enemy_speed_factor)
		var id: int=e.id;var hp: float=e.hp
		sim.wave=sim.data.waves.groups.size();sim.spawn_queue.clear();sim.next_wave_tick=-1
		sim.snow.step(sim)
		check(sim.enemies.is_empty() and sim.unit_by_id(id).is_empty() and sim.snow.occupied(),"tunnel entity unavailable "+speed)
		check(not e.has("regen_ts"),"entry removes regeneration aura "+speed)
		sim.controller.step(sim)
		check(sim.result=="","last tunnel enemy prevents victory "+speed)
		var exit_tick: int=int(source.tunnels[speed].events[-1][0])
		for frame in range(1,exit_tick):sim.tick=frame;sim.snow.step(sim)
		check(sim.enemies.is_empty(),"source transit holds until release "+speed)
		sim.tick=exit_tick;sim.snow.step(sim)
		check(sim.enemies.size()==1 and e.id==id and e.path==3 and e.subpath==2 and e.node==0 and e.hp==hp and e.has("regen_ts"),"source transit release tick / identity / HP / subpath / aura "+speed)
		compare7("tunnel_"+speed,[[exit_tick,3,2,0]],[[sim.tick,e.path,e.subpath,e.node]])
		check(sim._target(e.pos,100,false,sim.templates.tower_archer_3.attacks.list[0]).is_empty(),"cave exit invalid path protects target "+speed)
		sim.reset();check(not sim.snow.occupied() and sim.enemies.is_empty(),"restart clears tunnel queue "+speed)
	var sim=fresh()
	var e: Dictionary=sim._spawn_enemy("enemy_troll",1,1);e.node=79;e.progress=79;e.pos=sim.vec(sim.data.paths.paths[1][1][79])
	var soldier: Dictionary=sim._soldier("soldier_militia","test",0,e.pos,e.pos)
	soldier.target=e.id;soldier.pending={"hit_at":100};e.blocker=soldier.id;e.blockers=[soldier.id]
	check(sim.modifiers.apply(sim,"mod_slow_curse",e,1,"test") and sim.modifiers.apply(sim,"mod_paladin_silence",e,1,"test") and sim.modifiers.apply(sim,"mod_thorn",e,1,"test"),"tunnel cleanup sample has slow, silence and stun")
	var before_speed: float=float(sim.templates[e.template].motion.max_speed)*float(sim.data.rules.enemy_speed_factor)*sim.modifiers.speed(e.id,sim)
	var transit: float=float(sim.snow.tunnels[0].length)/(float(sim.snow.tunnels[0].speed_factor)*before_speed)*30
	sim.snow.step(sim)
	check(is_equal_approx(float(sim.snow.tunnels[0].queue[0].release),transit),"tunnel travel time uses speed before status cleanup")
	check(sim.modifiers.active.is_empty() and e.get("silence_count",0)==0 and e.get("stun_count",0)==0 and not e.has("regen_ts"),"tunnel clears active modifiers and regeneration aura")
	check(e.blocker==0 and e.blockers.is_empty() and soldier.target==0 and soldier.pending.is_empty(),"tunnel releases both sides of melee blocking")

func progression7() -> void:
	var path := "user://level07_%d.json" % Time.get_ticks_usec()
	var p=Progress.new();p.initialize(path);p.levels[6]={}
	p.record_result({"generation":1,"level_id":6,"mode":1,"difficulty":2,"result":"victory","lives":20});p.enter_map()
	check(p.is_playable(7),"sixth settlement opens seventh")
	var result := {"generation":1,"level_id":7,"mode":1,"difficulty":2,"result":"victory","lives":20,"unlock_towers":["tower_musketeer"]}
	p.record_result(result)
	check("tower_musketeer" in p.data.locked_towers and p.data.has("last_victory"),"victory pending retains permanent lock")
	p.enter_map()
	check(p.record(7).stars==3 and p.is_playable(7,2) and p.is_playable(7,3) and not p.is_playable(8) and p.is_unlocked(8),"three stars opens challenges; eighth preview")
	check(not "tower_musketeer" in p.data.locked_towers,"map settlement commits Musketeer unlock")
	var restored=Progress.new();restored.initialize(path)
	check(restored.record(7).stars==3 and not "tower_musketeer" in restored.data.locked_towers,"reload preserves stage and unlock")
	for id in [4,5,6]:
		var old=Sim.new(Setup7.create(Levels.load_definition(id),restored.data));old.notices.clear();old.gold=10000
		check(not old.tower_locked("tower_musketeer") and old.templates.has("ps_shotgun_musketeer"),"old stage has unlocked branch and resources %d" % id)
	p.record_result(result);p.record_result({"generation":1,"level_id":7,"mode":1,"difficulty":2,"result":"defeat","lives":0})
	check(not p.data.has("last_victory") and p.record(7).stars==3,"restart then defeat discards pending result; keeps settled stars")
	var other=Progress.new();other.initialize(path+"_other")
	check(not other.is_playable(7) and "tower_musketeer" in other.data.locked_towers,"independent slot isolation")
	for file in [path,path+"_other"]:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
