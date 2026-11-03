extends "res://tests/verify_level08.gd"
func fresh(mode:int=1):
	var d:Dictionary=Levels.load_definition(10,mode)
	check(not d.is_empty(),"tenth definition %d: %s"%[mode,Levels.last_error])
	if d.is_empty():return null
	var sim=Sim.new(d,42);sim.notices.clear();return sim
func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level10_source.json")
	check(not source.is_empty(),"independent pinned source waves")
	for mode in [1,2,3]:
		var sim=fresh(mode)
		if sim==null:quit(1);return
		check(sim.gold==[800,1800,2200][mode-1] and sim.lives==[20,1,1][mode-1],"source economy %d"%mode)
		check(sim.towers.size()==14 and sim.data.waves.groups.size()==[19,6,1][mode-1],"source sites and waves %d"%mode)
		check(sim.controller.graveyards.size()==1,"source graveyard placement")
		check(sim.data.waves==source.modes[str(mode)],"complete source wave fields %d"%mode)
		var layout:Dictionary=sim.data.layout.duplicate(true)
		for e:Dictionary in layout.entities_list:e.template=str(e.template).split("__")[0]
		check(equivalent(layout,source.layout),"complete source layout %d"%mode)
		check(not sim.tower_locked("tower_tesla"),"Tesla unlocked in tenth")
		if mode==3:
			for kind:String in Sim.TYPES:check(sim.tower_locked("tower_build_"+kind)==(kind=="engineer"),"iron build restriction "+kind)
		timeline(mode)
	graveyard10();tesla10();demons10();progression10()
	for name:String in source.towers:source_tesla10(name)
	for rank:String in source.rays:source_ray10(int(rank))
	source_dps10()
	var hashes:Dictionary={}
	for path:String in ["tests/verify_level10.gd","tests/fixtures/level10_source.json","scripts/battle/dove_tesla.gd","scripts/battle/dove_wasteland.gd","scripts/battle/controllers/level10.gd","scripts/battle/dove_snow.gd","scripts/battle/dove_behaviors.gd","scripts/battle/dove_modifiers.gd","scripts/battle/level01_sim.gd","data/level10/definition.json","data/campaign_content.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("level10_logic",{"checks":checks,"failures":failures,"passed":failures.is_empty(),"independent_modes":3,"timeline_waves":26,"births":births,"full_replays":false,"source_hashes":hashes})
	write8("level10_timelines",timeline_report)
	print("LEVEL10: ",JSON.stringify({"checks":checks,"births":births,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
func graveyard10() -> void:
	var sim=fresh()
	for name:String in ["enemy_bandit","enemy_dark_knight","enemy_demon_wolf","enemy_skeleton"]:
		var e:Dictionary=sim._spawn_enemy(name,0);sim.damage(e,100000,1)
	sim.tick=14;sim.controller.step(sim)
	check(sim.enemies.size()==4,"graveyard waits source death age")
	sim.tick=22;sim.controller.step(sim)
	check(sim.enemies.size()==5 and sim.enemies[-1].template=="enemy_skeleton","small corpse threshold")
	var raised:Dictionary=sim.enemies[-1]
	check(raised.state=="raise" and raised.has("forced_waypoint") and raised.get("gold_override",-1)==-1,"source raise, waypoint and retained gold")
	var pos:Vector2=raised.pos;sim._enemy_step(raised)
	check(raised.pos==pos and raised.state=="raise","raise holds position and first animation")
	sim.tick+=4;sim.controller.step(sim)
	check(sim.enemies.size()==6 and sim.enemies[-1].template=="enemy_skeleton_big","large corpse threshold")
	sim.tick+=20;sim.controller.step(sim)
	check(sim.enemies.size()==6,"skeleton and wolf bans, consumed corpse never reused")
	sim.tick=int(raised.raise_until);sim._enemy_step(raised)
	check(not raised.has("raise_until") and raised.state!="raise","raise finishes into forced movement")
	sim.enemies.clear();sim.wave=sim.data.waves.groups.size();sim.spawn_queue.clear()
	check(not sim.controller.can_finish(sim),"graveyard source grace blocks immediate settlement")
	sim.tick+=24
	check(not sim.controller.can_finish(sim),"graveyard waits dead_time plus check interval and two ticks")
	sim.tick+=1
	check(sim.controller.can_finish(sim),"graveyard grace ends without waiting full corpse lifetimes")
	sim.reset();check(sim.controller.empty_at==-1 and sim.controller.graveyards[0].queue.is_empty(),"restart clears graveyard")
func tesla10() -> void:
	var sim=fresh();var tower:Dictionary=buy(sim,"engineer","1","tower_tesla")
	for power:String in ["bolt","overcharge"]:
		for rank in 3:check(sim.command("upgrade_power",{"id":"1","power":power}),"Tesla skill %s rank %d"%[power,rank+1])
		check(not sim.command("upgrade_power",{"id":"1","power":power}),"Tesla skill cap "+power)
		check(not sim.power_preview(tower,power).text.contains("%$"),"Tesla compiled preview "+power)
	sim.enemies.clear();sim.soldiers.clear();sim.tick=100;sim.Behaviors.Tesla.initialize(sim,tower)
	tower.pos=Vector2(500,350)
	for i in 8:
		var e:Dictionary=sim._spawn_enemy("enemy_gargoyle" if i==0 else "enemy_dark_knight",0)
		e.pos=Vector2(540+i*35,350);e.hp=10000;e.max_hp=10000;e.progress=100-i
	sim.tick=167;sim._tower_step(tower)
	check(not tower.tesla.cast.is_empty(),"Tesla can target air")
	var fire:int=int(tower.tesla.cast.fire)
	sim.tick=fire-1;sim._tower_step(tower);check(sim.projectiles.is_empty(),"Tesla source windup")
	sim.tick=fire;sim._tower_step(tower)
	check(sim.projectiles.size()==1,"Tesla fires at source shoot_time")
	var visited:Array=[]
	for tick in 45:
		sim.tick=fire+tick
		for p:Dictionary in sim.projectiles.duplicate():
			if not p.has("tesla_started") and sim.tick>=int(p.start_at):visited.append(p.target)
			sim._bullet_step(p)
		sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
		sim.modifiers.step(sim)
	check(visited.size()==3,"base Tesla initial hit plus two jumps")
	var unique:Dictionary={}
	for id:int in visited:unique[id]=true
	check(unique.size()==visited.size(),"Tesla never revisits chain targets")
	var target:Dictionary=sim.enemies[1];target.armor=0.8
	check(is_equal_approx(sim.damage(target,100,16),60),"electrical damage uses half physical armor")
	var before:float=target.hp
	sim.modifiers.apply(sim,"mod_demon_shield",target,1,"0")
	for i in 7:sim.damage(target,10,int(sim.data.constants.DAMAGE_ONE_SHIELD_HIT)|16,123)
	check(target.hp==before and sim.modifiers.active.any(func(m):return m.template=="mod_demon_shield"),"one electrical source consumes one shield hit")
	for i in 3:sim.damage(target,10,16,124+i)
	check(target.hp==before and not sim.modifiers.active.any(func(m):return m.template=="mod_demon_shield"),"fourth blocked hit removes shield")
	sim.damage(target,100,16);check(target.hp<before,"next hit reaches health after shield removal")
	# Forced random threshold isolates stun insertion/removal from probability sampling.
	sim.templates.mod_tesla_overcharge.stun_chance=1
	sim.modifiers.apply(sim,"mod_tesla_overcharge",target,1,"0")
	check(target.stun_count==1,"overcharge stun inserts once")
	sim.tick+=20;sim.modifiers.step(sim)
	check(target.stun_count==0,"overcharge expiry releases stun")
func demons10() -> void:
	var sim=fresh();var demon:Dictionary=sim._spawn_enemy("enemy_demon",0)
	demon.pos=Vector2(500,400)
	var soldier:Dictionary=sim._soldier("soldier_militia","",0,demon.pos,demon.pos)
	var hp:float=soldier.hp
	sim.damage(demon,10000,1);check(sim.wasteland.blasts.size()==1,"demon concurrent death spawn")
	sim.tick+=1;sim.wasteland.step(sim)
	check(soldier.hp<hp and sim.wasteland.blasts.is_empty(),"demon explosion damages friendly units once")
	var silenced:Dictionary=sim._spawn_enemy("enemy_demon",0);silenced.silence_count=1
	sim.damage(silenced,10000,1)
	check(silenced.hidden and sim.effects[-1].template=="fx_enemy_desintegrate" and sim.wasteland.blasts.size()==1,"silenced demon disintegrates while retaining concurrent blast")
	var mage:Dictionary=sim._spawn_enemy("enemy_demon_mage",0);mage.pos=Vector2(500,400)
	var wolf:Dictionary=sim._spawn_enemy("enemy_demon_wolf",0);wolf.pos=Vector2(550,400)
	sim.tick+=181;sim._enemy_step(mage)
	check(mage.state=="special","demon mage starts source shield cast")
	sim.tick=int(mage.shield_job.fire);sim._enemy_step(mage)
	check(sim.modifiers.active.any(func(m):return m.target==wolf.id and m.template=="mod_demon_shield"),"demon mage shields eligible demons")
	var big:Dictionary=sim._spawn_enemy("enemy_skeleton_big",0);big.pos=Vector2(600,400)
	var small:Dictionary=sim._spawn_enemy("enemy_skeleton",0);small.pos=Vector2(610,400)
	sim.tick+=30;sim.wasteland.step(sim)
	check(is_equal_approx(sim.DamageFactors.value(small,sim.templates[small.template],true),0.85),"big skeleton grants source multiplicative resistance")
	sim.damage(big,10000,1);sim.tick+=31;sim.modifiers.step(sim)
	check(is_equal_approx(sim.DamageFactors.value(small,sim.templates[small.template],true),1),"skeleton buff expires after source death")
func progression10() -> void:
	check(Levels.supports(10,3) and not Levels.supports(11),"published ten levels, eleventh preview")

func source_tesla10(scenario:String) -> void:
	var sim=fresh();var tower:Dictionary=buy(sim,"engineer","1","tower_tesla")
	sim.enemies.clear();sim.tick=0;tower.pos=Vector2(500,350);sim.Behaviors.Tesla.initialize(sim,tower)
	if scenario=="skills":tower.powers.bolt=3;tower.powers.overcharge=3
	var enemy:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);enemy.pos=Vector2(550,350);enemy.hp=10000;enemy.progress=100
	var replacement:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);replacement.pos=Vector2(570,350);replacement.hp=10000;replacement.progress=99
	if scenario=="empty":sim.enemies.clear()
	var actual:Array=[]
	for n in 601:
		sim.tick=n;tower.blocked=scenario=="blocked" and n>=50 and n<150
		if scenario=="retarget" and n==80:enemy.hp=0
		sim._tower_step(tower)
		for p:Dictionary in sim.projectiles:actual.append([n,p.template,p.target,p.level])
		for a:Dictionary in sim.auras:actual.append([n,a.template,0,a.level])
		sim.projectiles.clear();sim.auras.clear()
	compare8("tesla source coroutine "+scenario,source.towers[scenario] if source.towers[scenario] is Array else [],actual,0)

func source_ray10(level:int) -> void:
	var sim=fresh();sim.enemies.clear();sim.soldiers.clear()
	for i in 8:
		var e:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);e.pos=Vector2(530+i*30,350)
	var tower:Dictionary=sim.tower_by_id("1");tower.template="tower_tesla"
	sim.templates.ray_tesla.bounce_damage_min=81;sim.templates.ray_tesla.bounce_damage_max=81
	sim.tick=-1
	sim.Behaviors.Tesla.launch(sim,tower,sim.enemies[0],Vector2(500,350),level)
	var trace:Array=[]
	for tick in 41:
		sim.tick=tick
		for p:Dictionary in sim.projectiles.duplicate():
			var count:int=sim.modifiers.active.size()
			sim._bullet_step(p)
			if sim.modifiers.active.size()>count:
				var m:Dictionary=sim.modifiers.active[-1];trace.append([tick,m.target,m.damage])
		sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
	compare8("source ray level %d"%level,source.rays[str(level)],trace,0.00001)

func source_dps10() -> void:
	var sim=fresh();sim.enemies.clear();sim.soldiers.clear()
	var e:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);e.armor=0;e.hp=10000;e.pos=Vector2(530,350)
	sim.templates.ray_tesla.bounce_damage_min=81;sim.templates.ray_tesla.bounce_damage_max=81
	sim.tick=-1
	sim.Behaviors.Tesla.launch(sim,sim.tower_by_id("1"),e,Vector2(500,350),0)
	sim.tick=0;sim._bullet_step(sim.projectiles[-1])
	var trace:Array=[]
	for tick10 in range(1,21):
		sim.tick=tick10;var before:float=e.hp;sim.modifiers.step(sim)
		if e.hp<before:trace.append([tick10,before-e.hp])
	compare8("source Tesla actual DPS coroutine",source.dps,trace,0.00001)
