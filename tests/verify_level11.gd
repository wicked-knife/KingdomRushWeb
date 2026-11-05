extends "res://tests/verify_level08.gd"
## Stage-eleven source configuration and bounded actual-coroutine comparisons.

func fresh(mode:int=1):
	var data:=Levels.load_definition(11,mode)
	check(not data.is_empty(),"eleventh loads %d: %s"%[mode,Levels.last_error])
	if data.is_empty():return null
	var sim=Sim.new(data,42);sim.notices.clear();return sim

func hashes11() -> Dictionary:
	var result:Dictionary={}
	for path:String in ["tests/verify_level11.gd","tests/fixtures/level11_source.json","scripts/battle/dove_necromancer.gd","scripts/battle/dove_spawner.gd","scripts/battle/dove_behaviors.gd","scripts/battle/dove_enemy_projectiles.gd","scripts/battle/dove_enemy_melee.gd","scripts/battle/level01_sim.gd","data/campaign_content.json","data/level11/definition.json"]:result[path]=FileAccess.get_sha256("res://"+path)
	return result

func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level11_source.json")
	check(not source.is_empty(),"eleventh independent source exists")
	var scalar_templates:Dictionary=Levels.load_definition(11).templates
	for name:String in source.enemy_fields:
		for field:String in source.enemy_fields[name]:
			var actual:Variant=scalar_templates[name]
			for part:String in field.replace("[", ".").replace("]", "").split("."):
				actual=actual[int(part)-1] if part.is_valid_int() else actual[part]
			check(equivalent(actual,source.enemy_fields[name][field]),"source evaluated scalar "+name+"."+field)
	check(Levels.supports(11,3) and not Levels.supports(12) and not Levels.supports(11,1,3),"eleven levels and normal difficulty")
	for mode:int in [1,2,3]:
		var sim=fresh(mode)
		if sim==null:quit(1);return
		check(sim.gold==[1300,2100,2600][mode-1] and sim.lives==[20,1,1][mode-1],"source economy %d"%mode)
		check(sim.towers.size()==18 and sim.data.waves.groups.size()==[19,6,1][mode-1],"source tower sites and waves %d"%mode)
		check(sim.data.waves==source.modes[str(mode)],"complete raw source waves %d"%mode)
		var layout:Dictionary=sim.data.layout.duplicate(true)
		for entity:Dictionary in layout.entities_list:entity.template=str(entity.template).split("__")[0]
		check(equivalent(layout,source.layout),"complete source layout and overrides %d"%mode)
		check(not sim.data.layout.locked_hero and sim.data.layout.level_mode_overrides[mode-1].max_upgrade_level==6,"hero allowed and technology cap six %d"%mode)
		check(sim.layout_spawners.size()==1 and sim.data.locations.entrances.size()==2,"layout generator and two entrances %d"%mode)
		for kind:String in Sim.TYPES:check(sim.tower_locked("tower_build_"+kind)==(mode==3 and kind in ["archer","engineer"]),"source build restriction %d/%s"%[mode,kind])
		timeline11(mode)
	for scenario:String in source.necromancers:necromancer11(scenario)
	for scenario:String in source.bolts:bolt11(scenario)
	for key:String in source.enemy_melee:enemy_melee_sample(key)
	for key:String in source.enemy_ranged:enemy_ranged_sample(key)
	lava11();integration11();progress11();negative11()
	write8("level11_comparisons",comparisons);write8("level11_timelines",timeline_report)
	write8("level11_logic",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"independent_modes":3,"timeline_waves":26,"births":births,"source_scenarios":35,"full_replays":false,"source_hashes":hashes11()})
	print("LEVEL11: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"births":births,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func timeline11(mode:int) -> void:
	var sim=fresh(mode);sim.towers.clear();sim.soldiers.clear();sim.layout_spawners.clear()
	var report:Array=[]
	for group:int in source.timelines[str(mode)].size():
		var start:int=sim.tick;var offset:int=sim.spawn_log.size()
		check(sim.command("wave"),"timeline starts %d/%d"%[mode,group+1])
		while not sim.spawn_queue.is_empty():sim.enemies.clear();sim.pending_entities.clear();ticks(sim,1)
		var actual:Array=[];var expected:Array=source.timelines[str(mode)][group]
		for entry:Dictionary in sim.spawn_log.slice(offset):
			if entry.origin=="wave":actual.append([entry.tick-start,entry.type,entry.path,entry.subpath])
		var normalized:Array=actual.duplicate(true)
		for i:int in mini(expected.size(),normalized.size()):
			if int(expected[i][3])==-1:
				check(int(normalized[i][3]) in [0,1,2],"random subpath legal %d/%d/%d"%[mode,group+1,i]);normalized[i][3]=-1
		compare8("source timeline %d/%d"%[mode,group+1],expected,normalized,0)
		report.append({"wave":group+1,"expected":expected,"actual":actual,"first_difference":comparisons["source timeline %d/%d"%[mode,group+1]].first_difference})
		births+=actual.size();sim.enemies.clear();sim.pending_entities.clear()
	timeline_report[str(mode)]=report

func necromancer11(scenario:String) -> void:
	var sim=fresh();sim.soldiers.clear();sim.enemies.clear()
	var enemy:Dictionary=sim._spawn_enemy("enemy_necromancer",0)
	enemy.node=sim.data.paths.paths[0][0].size() if scenario=="invalid_node" else 40
	enemy.pos=Vector2(500,350)
	var births11:Array=[];var children:Array=[];var animations:Array=[];var releases:Array=[]
	for n:int in (2101 if scenario=="cap" else 651):
		sim.tick=n
		enemy.blocker=99 if scenario=="blocked" and n<90 else 0
		enemy.silence_count=1 if scenario=="silenced" and n<300 or scenario=="silenced_cast" and n>=245 else 0
		enemy.stun_count=1 if scenario=="stun_windup" and n>=245 and n<255 or scenario=="stun_boundary" and n==257 or scenario=="stun_delay" and n>=259 and n<270 else 0
		if scenario=="dead_cast" and n==259 or scenario=="dead_after" and n==300:sim.damage(enemy,100000,1)
		var before:int=sim.enemies.size()
		sim.behaviors.enemy_step(sim,enemy,sim.templates.enemy_necromancer)
		if enemy.state=="summon" and enemy.state_at==n:animations.append([n,"summon"])
		for child:Dictionary in sim.enemies.slice(before):
			births11.append([n,child.template,child.path,child.subpath,child.node,child.gold_override,child.speed_override,0.7]);children.append(child)
	for i:int in children.size():births11[i][7]=sim.DamageFactors.value(children[i],sim.templates[children[i].template],true)
	var expected:Dictionary=source.necromancers[scenario]
	compare8("necromancer births "+scenario,expected.births if expected.births is Array else [],births11,0.00001)
	var expected_animations:Array=[]
	for row:Array in expected.events:
		if row[0]=="animation":expected_animations.append([row[1],row[2]])
	compare8("necromancer animations "+scenario,expected_animations,animations,0)
	if scenario=="cap":check(children.size()==30,"source actual lifetime list cap 30")
	if scenario=="dead_after":check(children.all(func(e):return is_equal_approx(sim.DamageFactors.value(e,sim.templates[e.template],true),1)),"owner death releases only owned living skeleton reduction")

func bolt11(scenario:String) -> void:
	var sim=fresh();sim.enemies.clear();sim.soldiers.clear()
	var target:Dictionary=sim._soldier("soldier_militia","",0,Vector2(650,350),Vector2(650,350));target.hp=10000
	sim.tick=-1
	var from:Vector2=Vector2(649 if scenario=="near" else 500,350)
	sim._projectile("bolt_necromancer",target.id,from,target.pos+sim.vec(sim.templates[target.template].unit.hit_offset),1)
	var projectile:Dictionary=sim.projectiles[-1];var actual:Array=[]
	for n:int in 61:
		sim.tick=n
		if scenario=="moving":target.pos.x=650+n
		if scenario=="dead" and n>=3:target.hp=0
		if scenario=="teleport" and n>=3:target.pos.x=1000
		sim._bullet_step(projectile)
		actual.append([n,projectile.pos.x,projectile.pos.y,projectile.to.x,projectile.to.y,projectile.done])
		if projectile.done:break
	compare8("enemy bolt "+scenario,source.bolts[scenario].frames,actual,0.0002)
	check(projectile.done,"enemy bolt cleans up "+scenario)

func lava11() -> void:
	var sim=fresh();var expected:Dictionary=source.lava_template
	var template:Dictionary=sim.templates.s11_lava_spawner
	for key:String in expected:check(template[key]==expected[key],"independently evaluated source generator field "+key)
	var actual:Array=[]
	for n:int in 15701:
		sim.tick=n;sim.wave=1 if n>=17 else 0
		var before:int=sim.enemies.size();sim.Behaviors.Spawner.step_layout(sim)
		for e:Dictionary in sim.enemies.slice(before):actual.append([n,e.template,e.path,e.subpath,e.node,e.pos.x,e.pos.y,e.state])
	compare8("source lava generator",source.lava_births,actual,0)
	var lava:Dictionary=sim.enemies[0]
	check(lava.state=="raise" and lava.playback_loop==false,"lava starts source non-looping rise")
	sim.tick=int(lava.raise_until);sim._enemy_step(lava)
	check(lava.state!="raise","lava rise ends into forced path movement")
	check(is_equal_approx(sim.damage(lava,100,16),48),"lava electrical coefficient 0.6 and half armor")
	sim.reset();check(sim.enemies.is_empty() and sim.layout_spawners[0].next==-1,"restart clears generator and actors")
	sim.wave=19;sim.spawn_queue.clear();check(sim.controller.can_finish(sim),"future generator timer does not block victory")

func integration11() -> void:
	var sim=fresh();sim.command("wave");sim.spawn_queue.clear();sim.layout_spawners.clear()
	var enemy:Dictionary=sim._spawn_enemy("enemy_necromancer",0);enemy.node=40;enemy.pos=sim.vec(sim.data.paths.paths[0][0][40])
	var point:Vector2=enemy.pos+Vector2(90,0)
	var soldier:Dictionary=sim._soldier("soldier_militia","",0,point,point);soldier.rallying=false;soldier.hp=10000
	for i:int in 100:sim.step()
	check(soldier.hp<10000,"normal simulation enemy magic projectile damages soldier")
	sim.enemies.clear();sim.soldiers.clear();sim.projectiles.clear()
	var lava:Dictionary=sim._spawn_enemy("enemy_lava_elemental",0);lava.node=40;lava.pos=sim.vec(sim.data.paths.paths[0][0][40])
	var guard:Dictionary=sim._soldier("soldier_militia","",0,lava.pos+Vector2(25,0),lava.pos+Vector2(25,0));guard.rallying=false;guard.hp=10000
	for i:int in 160:sim.step()
	check(guard.hp<10000 and lava.has("mixed_melee_job"),"normal simulation lava area melee connects")

func progress11() -> void:
	var p=Progress.new();var file:String="user://level11_logic_%d.json"%Time.get_ticks_usec()
	file="res://output/level11_logic_slot_%d.json"%Time.get_ticks_usec()
	p.initialize(file)
	for id:int in range(1,11):preload("res://tests/slot_fixture.gd").complete(p,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	check(p.is_playable(11) and not p.is_playable(11,2),"tenth settlement opens eleventh campaign")
	for mode:int in [1,2,3]:
		preload("res://tests/slot_fixture.gd").complete(p,{"generation":1,"level_id":11,"mode":mode,"difficulty":2,"result":"victory","lives":20 if mode==1 else 1})
	check(p.is_playable(11,2) and p.is_playable(11,3) and not p.is_playable(12),"eleventh challenges save and twelfth remains preview")
	for suffix:String in ["",".tmp",".bak"]:
		if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)

func negative11() -> void:
	var data:=Levels.load_definition(11)
	for name:String in ["enemy_skeleton","enemy_skeleton_big","bolt_necromancer","enemy_lava_elemental","s11_lava_spawner"]:
		var broken:Dictionary=data.duplicate(true);broken.templates.erase(name)
		check(not Sim.Behaviors.validate(broken,Levels.catalog()).is_empty(),"runtime refuses missing eleventh dependency "+name)

func enemy_ranged_sample(scenario:String) -> void:
	var sim=fresh();sim.tick=100
	var enemy:Dictionary=sim._spawn_enemy("enemy_necromancer",0);enemy.id=100;enemy.pos=Vector2(500,350);enemy.node=60
	var target:Dictionary=sim._soldier("soldier_militia","",0,Vector2(560,350),Vector2(560,350));target.id=1;target.hp=1000
	sim.templates[target.template].unit.hit_offset={"x":0,"y":13}
	var t:Dictionary=sim.templates[enemy.template];var actual:Array=[];var finished:int=-1
	for frame in range(100,151):
		sim.tick=frame
		enemy.stun_count=1 if (scenario=="stun_before" and frame>=103) or (scenario=="stun_endpoint" and frame>=109) or (scenario=="stun_after" and frame>=110) else 0
		if scenario=="escaped" and frame>=103:target.pos.x=800
		if scenario=="dead_target" and frame>=103:target.hp=0
		Sim.Behaviors.EnemyMelee.step(sim,enemy,t)
		for p:Dictionary in sim.projectiles:
			var b:Dictionary=sim.templates[p.template].bullet
			actual.append([frame,p.template,b.damage_min,b.damage_max,b.damage_type,p.get("level",b.get("level",0)),p.damage_factor,p.from.x,p.from.y,p.to.x,p.to.y,0,p.target,b.get("flight_time",0)])
		sim.projectiles.clear()
		if enemy.get("ranged_cast",{}).is_empty():finished=frame;break
	var expected:Dictionary=source.enemy_ranged[scenario]
	compare8("necromancer ranged "+scenario,expected.bullets if expected.bullets is Array else [],actual)
	check(finished==int(expected.finished) and enemy.ranged_at==int(expected.cooldown),"enemy source ranged completion/cooldown "+scenario)

