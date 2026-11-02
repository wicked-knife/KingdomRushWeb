extends "res://tests/verify_level06.gd"
## Bounded source comparisons, transactions and lifecycle tests; no victory search.
const Setup8=preload("res://scripts/services/battle_setup.gd")
var comparisons:Dictionary={}

func fresh(mode:int=1):
	var data:=Levels.load_definition(8,mode)
	check(not data.is_empty(),"eighth definition loads %d: %s"%[mode,Levels.last_error])
	if data.is_empty():return null
	var sim=Sim.new(data,42);sim.notices.clear();return sim

func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level08_source.json")
	check(not source.is_empty(),"actual frozen source fixture exists")
	if OS.get_cmdline_user_args().has("--enemies-only"):
		for scenario:String in source.enemy_melee:enemy_melee_sample(scenario)
		for scenario:String in source.enemy_ranged:enemy_ranged_sample(scenario)
		write8("level08_enemy_comparisons",comparisons)
		print("LEVEL08_ENEMIES: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks)
		quit(0 if failures.is_empty() else 1);return
	var missing:=Levels.load_definition(8)
	missing.callbacks.missile_bfg.erase("remove")
	check(Sim.Behaviors.validate(missing,Levels.catalog()).contains("required runtime callback"),"runtime rejects missing source missile removal callback")
	missing=Levels.load_definition(8);missing.templates.erase("axe_barbarian_rude")
	check(Sim.Behaviors.validate(missing,Levels.catalog()).contains("axe_barbarian_rude"),"runtime rejects missing dual-axe projectile")
	check(Levels.supports(8,3) and not Levels.supports(10) and not Levels.supports(8,1,3),"eight levels, three modes, normal difficulty")
	for mode in [1,2,3]:
		var sim=fresh(mode)
		if sim==null:quit(1);return
		check(sim.data.waves==source.modes[str(mode)],"all eighth wave fields %d"%mode)
		var layout:Dictionary=source.layout.duplicate(true)
		layout.entities_list=layout.entities_list.filter(func(e):return int(e.get("editor.game_mode",0)) in [0,mode])
		var actual:Dictionary=sim.data.layout.duplicate(true)
		for e:Dictionary in actual.entities_list:e.template=str(e.template).split("__")[0]
		check(equivalent(actual,layout),"all eighth layout and restrictions %d"%mode)
		check(sim.gold==[800,1100,1200][mode-1] and sim.lives==(20 if mode==1 else 1),"source eighth economy %d"%mode)
		check(sim.snow.tunnels.size()==1 and sim.towers.size()==13,"source tunnel and tower sites %d"%mode)
		check(not sim.tower_locked("tower_barbarian") and not sim.tower_locked("tower_bfg"),"new towers available in stage %d"%mode)
		if mode==3:
			check(sim.tower_by_id("20").template=="tower_mage_2" and sim.tower_by_id("20").spent==0,"iron free mage2")
			for kind:String in Sim.TYPES:check(sim.tower_locked("tower_build_"+kind)==(kind in ["archer","mage"]),"iron source bans "+kind)
		timeline(mode)
	transactions()
	for name:String in source.towers:tower_sample(name)
	for name:String in source.powers:power_sample(name)
	for count:String in source.clusters:cluster_sample(count)
	for scenario:String in source.missiles:missile_sample(scenario)
	for name:String in source.melee:melee_sample(name)
	for scenario:String in source.melee_interrupts:melee_interrupt_sample(scenario)
	for scenario:String in source.ranged:ranged_sample(scenario)
	for scenario:String in source.enemy_melee:enemy_melee_sample(scenario)
	for scenario:String in source.enemy_ranged:enemy_ranged_sample(scenario)
	for scenario:String in source.chieftains:chieftain_sample(scenario)
	modifiers_and_regen()
	chief_target_filters()
	tunnel_rage_lifecycle()
	sasquash()
	progression8()
	var source_scenarios:int=0
	for key:String in ["towers","powers","clusters","missiles","melee","melee_interrupts","ranged","enemy_melee","enemy_ranged","chieftains"]:source_scenarios+=source[key].size()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"independent_modes":3,"births":births,"timeline_waves":source.timelines["1"].size()+7,"source_scenarios":source_scenarios,"failures":failures,"full_replays":false,"source_hashes":hashes8()}
	write8("level08_logic",report);write8("level08_timelines",timeline_report);write8("level08_comparisons",comparisons)
	print("LEVEL08: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks," births=",births)
	quit(0 if failures.is_empty() else 1)

func hashes8() -> Dictionary:
	var result:Dictionary={}
	for path:String in ["scripts/battle/dove_bfg.gd","scripts/battle/dove_missile.gd","scripts/battle/dove_advanced_barrack.gd","scripts/battle/dove_sasquash.gd","scripts/battle/dove_chieftain.gd","scripts/battle/dove_enemy_melee.gd","scripts/battle/dove_enemy_ranged.gd","scripts/battle/dove_modifiers.gd","scripts/battle/dove_snow.gd","scripts/battle/dove_behaviors.gd","scripts/battle/level01_sim.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","data/campaign_content.json","data/level08/definition.json","tests/fixtures/level08_source.json","tests/verify_level08.gd"]:result[path]=FileAccess.get_sha256("res://"+path)
	return result

func write8(name:String,value:Variant) -> void:
	var f:=FileAccess.open("res://reports/"+name+".json",FileAccess.WRITE);f.store_string(JSON.stringify(value,"\t"));f.close()

func compare8(label:String,expected:Array,actual:Array,tolerance:float=0.02) -> void:
	var difference:=""
	if expected.size()!=actual.size():difference="length %d/%d"%[expected.size(),actual.size()]
	for row in mini(expected.size(),actual.size()):
		if expected[row].size()!=actual[row].size():
			if difference=="":difference="columns row %d"%row
			continue
		for col in expected[row].size():
			var a:Variant=expected[row][col];var b:Variant=actual[row][col]
			if (absf(float(a)-float(b))>tolerance if (a is float or a is int) and not a is bool else a!=b):
				if difference=="":difference="row %d column %d expected=%s actual=%s"%[row,col,a,b]
	check(difference=="",label+" first difference: "+difference)
	comparisons[label]={"expected":expected,"actual":actual,"first_difference":difference}

func transactions() -> void:
	for kind:String in ["barrack","engineer"]:
		var sim=fresh();sim.gold=20000
		var name:String="tower_barbarian" if kind=="barrack" else "tower_bfg"
		var tower:Dictionary=buy(sim,kind,"11",name)
		check(tower.template==name,"explicit new tower branch "+name)
		if kind=="barrack":check(tower.slots.size()==4,"four barbarian slots")
		for power:String in tower.powers:
			for rank in 3:check(sim.command("upgrade_power",{"id":tower.id,"power":power}),"purchase "+power+str(rank+1))
			check(not sim.command("upgrade_power",{"id":tower.id,"power":power}),"power cap "+power)
		var refund:int=sim.sell_refund(tower);var gold:int=sim.gold
		check(sim.command("sell",{"id":tower.id}) and sim.gold==gold+refund,"new tower sale includes skills "+name)
	var sim=fresh();sim.gold=10000
	var tower:Dictionary=buy(sim,"barrack","11","tower_barbarian")
	ticks(sim,100)
	check(sim.soldiers.filter(func(s):return s.home=="11").size()==4,"four barbarians spawn")
	var soldier:Dictionary=sim.soldiers.filter(func(s):return s.home=="11")[0]
	sim.damage(soldier,10000,1)
	check(soldier.state=="death" and soldier.source_corpse,"source corpse retained")
	ticks(sim,299)
	check(sim.soldiers.has(soldier) and sim.tower_by_id("11").slots[0]<0,"corpse and respawn wait full ten seconds")
	ticks(sim,30)
	check(not sim.soldiers.has(soldier) and sim.soldiers.filter(func(s):return s.home=="11" and s.hp>0).size()==4,"barbarian respawn after source lifetime and door")

func tower_sample(scenario:String) -> void:
	var sim=fresh();sim.gold=10000
	var tower:Dictionary=buy(sim,"engineer","11","tower_bfg")
	tower.pos=Vector2(500,350);sim.tick=0;Sim.Behaviors.Bfg.initialize(sim,tower)
	var enemy:Dictionary=sim._spawn_enemy("enemy_gargoyle" if scenario=="flying" else "enemy_troll",0)
	enemy.pos=Vector2(580,350);enemy.node=60;enemy.hp=100000
	var other:Dictionary=sim._spawn_enemy(enemy.template,0);other.pos=enemy.pos;other.node=59;other.hp=100000
	if scenario!="normal":
		for power:String in tower.powers:tower.powers[power]=3;Sim.Behaviors.Bfg.power_upgraded(sim,tower,power)
	if scenario=="empty":sim.enemies.clear()
	var actual:Array=[]
	for frame in 1001:
		sim.tick=frame
		if scenario=="retarget" and frame==315:enemy.hp=0
		Sim.Behaviors.Bfg.step(sim,tower)
		for p:Dictionary in sim.projectiles:
			var b:Dictionary=sim.templates[p.template].bullet
			actual.append([frame,p.template,p.get("damage_min",b.damage_min),p.get("damage_max",b.damage_max),b.damage_type,p.get("level",0),p.damage_factor,p.from.x,p.from.y])
		sim.projectiles.clear()
	var expected:Array=[]
	for row:Array in source.towers[scenario].bullets:expected.append(row.slice(0,9))
	compare8("bfg tower "+scenario,expected,actual)

func power_sample(name:String) -> void:
	var sim=fresh()
	var tower:Dictionary={"powers":{"dual":0,"twister":0,"throwing":0}}
	var s:Dictionary=sim._soldier("soldier_barbarian","",0,Vector2(500,350),Vector2(500,350))
	var rows:Array=[]
	for power:String in source.powers[name].sequence:
		tower.powers[power]+=1
		Sim.Behaviors.AdvancedBarrack._apply_power(sim,s,power,int(tower.powers[power]))
		var t:Dictionary=s.combat_template
		var a:Dictionary=t.melee.attacks[0];var b:Dictionary=t.melee.attacks[1];var r:Dictionary=t.ranged.attacks[0]
		rows.append([power,tower.powers[power],a.damage_min,a.damage_max,a.damage_type,a.animation,b.damage_min,b.damage_max,b.chance,b.get("disabled",false),b.animation,r.max_range,r.get("disabled",false),r.animation,r.bullet,t.soldier.melee_slot_offset.x,t.render.sprites[0].angles.walk[0],"idle2" if s.get("dual_applied",false) else "idle"])
	compare8("barbarian power order "+name,source.powers[name].rows,rows)

func cluster_sample(count:String) -> void:
	var sim=fresh();sim.tick=0
	sim._projectile("bomb_bfg_cluster",0,Vector2(500,350),Vector2(580,350),float(sim.templates.bomb_bfg_cluster.bullet.flight_time))
	var p:Dictionary=sim.projectiles[-1];p.fragment_count=int(count);p.damage_factor=0.6
	var expected:Dictionary=source.clusters[count]
	check(p.to.is_equal_approx(sim.vec(expected.to)) and p.pred_pi==expected.pred_pi and p.pred_ni==expected.pred_ni,"cluster source path snapping "+count)
	var actual:Array=[]
	for frame in 51:
		sim.tick=frame;sim._bullet_step(p)
		actual.append([frame,p.pos.x,p.pos.y,p.rotation,p.hidden])
		if p.done:break
	compare8("cluster parent trajectory "+count,expected.samples,actual)
	var children:Array=sim.projectiles.filter(func(child):return child!=p)
	check(children.size()==int(count),"cluster fragment count "+count)
	for i in mini(children.size(),expected.fragments.size()):
		var child:Dictionary=children[i];var row:Array=expected.fragments[i]
		check(absf(child.to.x-float(row[9]))<=6.01 and absf(child.to.y-float(row[10]))<=6.01,"fragment source node and spread %s/%d"%[count,i])
		check(child.duration>=10+i+1 and child.duration<=10+2*(i+1) and is_equal_approx(child.damage_factor,0.6),"fragment flight domain and inherited damage %s/%d"%[count,i])
	comparisons["cluster fragments "+count]={"expected":expected.fragments,"actual":children}

func missile_sample(scenario:String) -> void:
	var sim=fresh();sim.tick=0
	var enemy:Dictionary=sim._spawn_enemy("enemy_troll",0);enemy.pos=Vector2(300,350);enemy.node=60;enemy.hp=10000
	var other:Dictionary=sim._spawn_enemy("enemy_troll",0);other.pos=Vector2(340,350);other.node=59;other.hp=10000
	if scenario=="efficiency":sim.upgrades.effective.engineers=5
	sim._projectile("missile_bfg",enemy.id,Vector2(100,350),Vector2(112,460),1)
	var p:Dictionary=sim.projectiles[-1];p.damage_min=126;p.damage_max=154;p.damage_factor=0.6
	var actual:Array=[];var hits:Array=[]
	for frame in 251:
		sim.tick=frame
		if frame==15:
			if scenario=="retarget":enemy.hp=0
			elif scenario=="banned":enemy.vis={"flags":2048,"bans":2}
		var before:=[enemy.hp,other.hp]
		sim._bullet_step(p);actual.append([frame,p.pos.x,p.pos.y,p.rotation])
		for i in 2:
			var e:Dictionary=[enemy,other][i]
			if e.hp!=before[i]:hits.append([frame,e.id,before[i]-e.hp,sim.templates[p.template].bullet.damage_type])
		if p.done:break
	compare8("missile trajectory "+scenario,source.missiles[scenario].samples,actual,0.08)
	compare8("missile damage "+scenario,source.missiles[scenario].hits,hits)
	check(p.done==source.missiles[scenario].removed,"missile removal "+scenario)
	var children:Array=sim.projectiles.filter(func(child):return child!=p)
	check(children.size()==3,"BFG source removal spawns three secondary missiles "+scenario)
	for child:Dictionary in children:
		check(child.template=="missile_bfg_second" and is_equal_approx(child.damage_min,42) and is_equal_approx(child.damage_max,154.0/3) and is_equal_approx(child.damage_factor,0.6),"secondary missile inherited damage "+scenario)
	comparisons["missile children "+scenario]={"expected":source.missiles[scenario].children,"actual":children}

func melee_interrupt_sample(name:String) -> void:
	var split:int=name.find("_");var kind:String=name.substr(0,split);var scenario:String=name.substr(split+1)
	var sim=fresh();sim.tick=100
	var s:Dictionary=sim._soldier("soldier_sasquash" if kind=="sasquash" else "soldier_barbarian","",0,Vector2(500,350),Vector2(500,350));s.id=5;s.rallying=false;s.dest=s.pos
	var target:Dictionary=sim._spawn_enemy("enemy_troll",0);target.id=1;target.pos=Vector2(520,350);target.node=60;target.hp=10000;target.blockers=[5];target.blocker=5;s.target=1
	var t:Dictionary=s.combat_template;var index:int=1 if kind=="twister" else 0;var a:Dictionary=t.melee.attacks[index];a.damage_min=40;a.damage_max=40;a.disabled=false
	Sim.Behaviors.AdvancedBarrack._begin(sim,s,t,a,{"kind":"melee","target":1,"entity":target,"index":index},float(a.hit_time))
	var hit_tick:int=s.advanced_job.hit_at;var actual:Array=[];var finished:int=-1
	for frame in range(100,161):
		sim.tick=frame
		s.stun_count=1 if (scenario=="stun_before" and frame>=103) or (scenario=="stun_after" and frame>=hit_tick+1) or (scenario=="stun_endpoint" and frame>=hit_tick) else 0
		s.rally_pending=(scenario=="rally_before" and frame>=103) or (scenario=="rally_after" and frame>=hit_tick+1)
		if scenario=="unblocked" and frame>=103:target.blockers=[]
		var before:float=target.hp;sim._soldier_step(s)
		if target.hp!=before:actual.append([frame,1,before-target.hp,a.damage_type])
		if s.advanced_job.is_empty():finished=frame;break
	var expected:Dictionary=source.melee_interrupts[name]
	compare8("melee interruption "+name,expected.hits if expected.hits is Array else [],actual)
	check(finished==int(expected.finished) and is_equal_approx(float(s.melee_ts[index]),float(expected.cooldown)),"source melee completion and cooldown "+name+" actual=%d/%s expected=%s/%s"%[finished,s.melee_ts[index],expected.finished,expected.cooldown])

func chief_target_filters() -> void:
	var sim=fresh();var chief:Dictionary=sim._spawn_enemy("enemy_troll_chieftain",0);chief.pos=Vector2(500,350);chief.node=60
	var slow:Dictionary=sim._spawn_enemy("enemy_troll",0);slow.pos=chief.pos;slow.node=60
	var raged:Dictionary=sim._spawn_enemy("enemy_troll",0);raged.pos=chief.pos;raged.node=60
	var banned:Dictionary=sim._spawn_enemy("enemy_troll",0);banned.pos=chief.pos;banned.node=60;banned.vis={"flags":2048,"bans":4}
	var spider:Dictionary=sim._spawn_enemy("enemy_spider_small",0);spider.pos=chief.pos;spider.node=60
	check(sim.modifiers.apply(sim,"mod_slow_curse",slow,1,"10") and sim.modifiers.apply(sim,"mod_troll_rage",raged,1,"10"),"chief filtering setup")
	var found:Array=Sim.Behaviors.Chieftain.targets(sim,chief,sim.templates[chief.template].timed_attacks.list[0])
	check(found.size()==1 and found[0].id==chief.id,"chief can buff itself and excludes slow/rage/banned/unlisted targets")

func tunnel_rage_lifecycle() -> void:
	var sim=fresh();var tunnel:Dictionary=sim.snow.tunnels[0]
	var chief:Dictionary=sim._spawn_enemy("enemy_troll_chieftain",1,int(tunnel.pick_pi))
	chief.node=int(tunnel.pick_ni);chief.pos=sim.vec(sim.data.paths.paths[chief.path][chief.subpath][chief.node]);chief.hp-=100
	check(sim.modifiers.apply(sim,"mod_troll_rage",chief,1,"10"),"source rage before eighth tunnel")
	sim.snow.step(sim)
	check(sim.unit_by_id(chief.id).is_empty() and tunnel.queue.size()==1 and not chief.has("regen_ts"),"tunnel removes chief and regeneration aura")
	check(sim.modifiers.active.is_empty() and is_zero_approx(chief.speed_bonus) and is_zero_approx(chief.melee_damage_min_bonus),"tunnel removes modifiers and reverses rage bonuses")
	sim.tick=ceili(tunnel.queue[0].release);sim.snow.step(sim)
	check(sim.unit_by_id(chief.id)==chief and chief.path==tunnel.place_pi and chief.node==tunnel.place_ni and chief.subpath==1,"eighth source tunnel destination preserves subpath")
	check(chief.has("regen_ts") and chief.regen_template=="aura_troll_chieftain_regen" and chief.rage_ts==sim.tick and chief.rage_job.is_empty(),"tunnel reinsertion recreates chief aura and attack coroutine")

func ranged_sample(scenario:String) -> void:
	var sim=fresh();sim.tick=100
	var s:Dictionary=sim._soldier("soldier_barbarian","",0,Vector2(500,350),Vector2(500,350));s.id=5;s.rallying=false;s.dest=s.pos
	var target:Dictionary=sim._spawn_enemy("enemy_troll",0);target.id=1;target.pos=Vector2(560,350);target.node=60;target.hp=10000
	var t:Dictionary=s.combat_template;var a:Dictionary=t.ranged.attacks[0];a.disabled=false;a.level=1
	if scenario=="dual":a.animation="shoot2";a.bullet="axe_barbarian_rude"
	var actual:Array=[];var finished:int=-1
	for frame in range(100,151):
		sim.tick=frame
		s.stun_count=1 if (scenario=="stun_before" and frame>=103) or (scenario=="stun_after" and frame>=110) or (scenario=="stun_endpoint" and frame>=107) else 0
		s.rally_pending=(scenario=="rally_before" and frame>=103) or (scenario=="rally_after" and frame>=110)
		if scenario=="escaped" and frame>=103:target.pos.x=800
		sim._soldier_step(s)
		for p:Dictionary in sim.projectiles:
			var b:Dictionary=sim.templates[p.template].bullet
			actual.append([frame,p.template,b.damage_min,b.damage_max,b.damage_type,p.level,p.damage_factor,p.from.x,p.from.y,p.to.x,p.to.y,0,p.target,b.flight_time])
		sim.projectiles.clear()
		if s.advanced_job.is_empty():finished=frame;break
	var expected:Dictionary=source.ranged[scenario]
	compare8("barbarian ranged "+scenario,expected.bullets if expected.bullets is Array else [],actual)
	check(finished==int(expected.finished) and is_equal_approx(float(s.ranged_ts),float(expected.cooldown)),"source ranged completion and cooldown "+scenario)

func enemy_melee_sample(key:String) -> void:
	var name:String=key.split(":")[0];var scenario:String=key.split(":")[1]
	var sim=fresh();sim.tick=100
	var enemy:Dictionary=sim._spawn_enemy(name,0);enemy.pos=Vector2(500,350);enemy.node=60;enemy.id=100
	var t:Dictionary=sim.templates[name];var a:Dictionary=t.melee.attacks[0];a.damage_min=40;a.damage_max=40
	var point:=Vector2(500+(-30 if scenario=="flipped" else 30),350)
	for i in (12 if scenario=="capped" else 4):
		var pos:=Vector2(point.x+12-i,350) if scenario=="capped" else Vector2(point.x+[0,10,40,0][i],390 if i==3 else 350)
		var soldier:Dictionary=sim._soldier("soldier_militia","",0,pos,pos);soldier.id=i+1;soldier.hp=1000;soldier.armor=0;soldier.vis={"flags":0,"bans":0}
		if scenario=="visibility" and i==1:soldier.vis.flags=128
		if scenario=="visibility" and i==2:soldier.vis.bans=2
	var target:Dictionary=sim.soldiers[0];enemy.blocker=1;enemy.blockers=[1];target.target=enemy.id
	if scenario=="dodged":sim.templates[target.template].dodge={"chance":1}
	var hit_tick:int=100+sim.source_wait_ticks(100,float(a.hit_time))
	var actual:Array=[];var effects:Array=[];var finished:int=-1
	for frame in range(100,171):
		sim.tick=frame
		enemy.stun_count=1 if (scenario=="stun_before" and frame>=103) or (scenario=="stun_endpoint" and frame>=hit_tick) or (scenario=="stun_after" and frame>=hit_tick+1) else 0
		if frame>=103 and scenario=="primary_dead":target.hp=0;enemy.blocker=0;enemy.blockers=[]
		if frame>=103 and scenario=="unblocked":enemy.blocker=0;enemy.blockers=[]
		var before:Array=sim.soldiers.map(func(s):return s.hp)
		if frame==100:sim._melee(enemy,target,t)
		else:Sim.Behaviors.EnemyMelee.step(sim,enemy,t)
		for i in sim.soldiers.size():
			if sim.soldiers[i].hp!=before[i]:actual.append([frame,i+1,before[i]-sim.soldiers[i].hp,a.damage_type])
		for effect:Dictionary in sim.effects:effects.append([frame,effect.template,effect.pos.x,effect.pos.y])
		sim.effects.clear()
		if enemy.mixed_melee_job.is_empty():finished=frame;break
	var expected:Dictionary=source.enemy_melee[key]
	compare8("enemy melee hits "+key,expected.hits if expected.hits is Array else [],actual)
	compare8("enemy melee effects "+key,expected.effects if expected.effects is Array else [],effects)
	check(finished==int(expected.finished) and enemy.mixed_melee_ts==int(expected.cooldown),"enemy source melee completion/cooldown "+key)
	if scenario not in ["stun_before"]:check(enemy.state=="idle" and enemy.playback_loop,"enemy melee returns to looping idle "+key)

func enemy_ranged_sample(scenario:String) -> void:
	var sim=fresh();sim.tick=100
	var enemy:Dictionary=sim._spawn_enemy("enemy_troll_axe_thrower",0);enemy.id=100;enemy.pos=Vector2(500,350);enemy.node=60
	var target:Dictionary=sim._soldier("soldier_militia","",0,Vector2(560,350),Vector2(560,350));target.id=1;target.hp=1000
	sim.templates[target.template].unit.hit_offset={"x":0,"y":13}
	var t:Dictionary=sim.templates[enemy.template];var actual:Array=[];var finished:int=-1
	for frame in range(100,151):
		sim.tick=frame
		enemy.stun_count=1 if (scenario=="stun_before" and frame>=103) or (scenario=="stun_endpoint" and frame>=107) or (scenario=="stun_after" and frame>=110) else 0
		if scenario=="escaped" and frame>=103:target.pos.x=800
		if scenario=="dead_target" and frame>=103:target.hp=0
		Sim.Behaviors.EnemyMelee.step(sim,enemy,t)
		for p:Dictionary in sim.projectiles:
			var b:Dictionary=sim.templates[p.template].bullet
			actual.append([frame,p.template,b.damage_min,b.damage_max,b.damage_type,p.get("level",b.get("level",0)),p.damage_factor,p.from.x,p.from.y,p.to.x,p.to.y,0,p.target,b.flight_time])
		sim.projectiles.clear()
		if enemy.get("ranged_cast",{}).is_empty():finished=frame;break
	var expected:Dictionary=source.enemy_ranged[scenario]
	compare8("enemy axe ranged "+scenario,expected.bullets if expected.bullets is Array else [],actual)
	check(finished==int(expected.finished) and enemy.ranged_at==int(expected.cooldown),"enemy source ranged completion/cooldown "+scenario)

func chieftain_sample(scenario:String) -> void:
	var sim=fresh();sim.tick=0
	for i in 8:
		var target:Dictionary=sim._spawn_enemy("enemy_troll",0)
		target.pos=Vector2(511+i,350);target.node=60;target.hp=1;target.max_hp=10000
		if scenario=="no_targets":target.vis={"flags":2048,"bans":4}
	var chief:Dictionary=sim._spawn_enemy("enemy_troll_chieftain",0)
	chief.pos=Vector2(500,350);chief.node=60;chief.vis={"flags":2048,"bans":4}
	var actual:Array=[];var animations:Array=[];var clock:Array=[0]
	sim.event.connect(func(kind:String,payload:Dictionary):
		if kind=="modifier_applied":actual.append([clock[0],payload.template,payload.target])
		elif kind=="chieftain_animation":animations.append([clock[0],1,payload.state]))
	for frame in 501:
		sim.tick=frame;clock[0]=frame;sim.modifiers.step(sim);chief.pos=Vector2(500,350)
		chief.blocker=100 if scenario=="blocked" and frame<200 else 0
		chief.stun_count=1 if (scenario=="stunned" and frame>=185 and frame<=195) or (scenario=="after_hit_stun" and frame>=192 and frame<=205) or (scenario=="cast_tick_stun" and frame>=190 and frame<=195) else 0
		chief.silence_count=1 if (scenario=="silenced" and frame>=175 and frame<=250) or (scenario=="mid_cast_silence" and frame>=185 and frame<=250) else 0
		sim._enemy_step(chief)
	var expected:Array=source.chieftains[scenario].casts if source.chieftains[scenario].casts is Array else []
	compare8("chieftain casts "+scenario,expected,actual)
	var expected_animations:Array=source.chieftains[scenario].animations if source.chieftains[scenario].animations is Array else []
	compare8("chieftain animations "+scenario,expected_animations,animations)

func melee_sample(name:String) -> void:
	var sim=fresh();sim.tick=0
	var s:Dictionary=sim._soldier(name,"",0,Vector2(500,350),Vector2(500,350));s.rallying=false
	var target:Dictionary=sim._spawn_enemy("enemy_troll",0);target.pos=Vector2(520,350);target.node=60;target.hp=10000
	var other:Dictionary=sim._spawn_enemy("enemy_troll",0);other.pos=target.pos;other.node=59;other.hp=10000
	var index:=1 if name=="soldier_barbarian" else 0
	var t:Dictionary=s.combat_template;var a:Dictionary=t.melee.attacks[index]
	a.damage_min=40;a.damage_max=40;a.disabled=false
	Sim.Behaviors.AdvancedBarrack._begin(sim,s,t,a,{"kind":"melee","target":target.id,"entity":target,"index":index},float(a.hit_time))
	var actual:Array=[]
	for frame in 61:
		sim.tick=frame
		var before:=[target.hp,other.hp]
		Sim.Behaviors.AdvancedBarrack._job(sim,s,t)
		for i in 2:
			var enemy:Dictionary=[target,other][i]
			if enemy.hp!=before[i]:actual.append([frame,i+1,before[i]-enemy.hp,a.damage_type])
		if s.advanced_job.is_empty():
			check(frame==int(source.melee[name].finished),"area attack source animation finishes "+name);break
	compare8("area melee hits "+name,source.melee[name].hits,actual)

func modifiers_and_regen() -> void:
	for name:String in ["enemy_troll","enemy_troll_axe_thrower","enemy_troll_chieftain"]:
		var sim=fresh();var e:Dictionary=sim._spawn_enemy(name,0);e.node=60;e.pos=sim.vec(sim.data.paths.paths[0][0][60]);e.hp-=100
		var hp:float=e.hp
		for frame in range(1,8):sim.tick=frame;sim.snow.step(sim)
		check(e.hp-hp==[1,2,4][["enemy_troll","enemy_troll_axe_thrower","enemy_troll_chieftain"].find(name)],"distinct source regeneration "+name)
		check(sim.modifiers.apply(sim,"mod_troll_rage",e,1,"10"),"rage applies "+name)
		check(is_equal_approx(sim.modifiers.speed(e.id,sim),(float(sim.templates[name].motion.max_speed)+30)/float(sim.templates[name].motion.max_speed)),"rage speed "+name)
		check(float(e.get("armor",0))==(0 if name=="enemy_troll_chieftain" else 0.5),"chieftain armor exception "+name)
		check(e.melee_damage_min_bonus==15 and e.melee_damage_max_bonus==30,"rage melee bonuses "+name)
		check(not sim.modifiers.apply(sim,"mod_slow_curse",e,1,"10"),"rage excludes slow curse")
		sim.tick+=181;sim.modifiers.step(sim)
		check(is_zero_approx(e.speed_bonus) and is_zero_approx(e.melee_damage_min_bonus) and is_zero_approx(e.armor),"rage removal reverses all bonuses "+name)

func sasquash() -> void:
	var sim=fresh();sim.gold=1000
	var frozen:Dictionary=sim.tower_by_id("91")
	check(frozen.type=="holder_sasquash" and not frozen.get("terrain_base",true),"frozen camp retains source art")
	check(not sim.command("sell",{"id":"91"}) and not sim.command("buy_soldier",{"id":"91","type":"soldier_sasquash"}),"frozen camp cannot be sold or hired")
	check(sim.valid_power_point("fire",Vector2(345,535)) and not sim.valid_power_point("reinforcements",Vector2(345,535)),"source fire-only thaw rectangle")
	sim.add_effect("fx_fireball_explosion",Vector2(500,550));sim._tower_step(frozen)
	check(sim.tower_by_id("91").template=="tower_sasquash_holder","distant fire does not thaw")
	sim.add_effect("fx_fireball_explosion",frozen.pos);sim._tower_step(frozen)
	var tower:Dictionary=sim.tower_by_id("91")
	check(tower.template=="tower_sasquash" and tower.get("hired",0)==0,"nearby source explosion thaws without free soldier")
	check(sim.command("buy_soldier",{"id":"91","type":"soldier_sasquash"}) and sim.gold==600,"Sasquatch source hire costs 400")
	check(not sim.command("buy_soldier",{"id":"91","type":"soldier_sasquash"}) and not sim.command("sell",{"id":"91"}),"camp hire cap and non-sale")
	sim._tower_step(tower)
	var s:Dictionary=sim.soldiers[-1]
	check(s.template=="soldier_sasquash" and s.pos==tower.pos+Vector2(-60,0) and s.dest==tower.rally,"doorless camp spawn and single rally formation")
	sim.damage(s,10000,1);sim.tick+=359;sim._tower_step(tower)
	check(sim.soldiers.size()==1,"camp waits source twelve seconds")
	sim.tick+=1;sim._tower_step(tower)
	check(sim.soldiers.size()==2 and sim.soldiers[-1].hp==2500 and sim.gold==600,"free automatic camp respawn")
	sim.reset();check(sim.tower_by_id("91").template=="tower_sasquash_holder" and sim.soldiers.is_empty(),"restart resets frozen camp and hire")
	var real=fresh()
	check(real.command("wave"),"real fire scenario starts first wave")
	dismiss(real)
	check(real.command("cast",{"power":"fire","pos":real.tower_by_id("91").pos}),"real fire rain accepts frozen camp rectangle")
	for frame in 150:
		ticks(real,1)
		if real.tower_by_id("91").template=="tower_sasquash":break
	check(real.tower_by_id("91").template=="tower_sasquash" and real.tower_by_id("91").get("hired",0)==0,"actual fire projectile explosion thaws camp without free hire")

func progression8() -> void:
	var progress:=Progress.new();progress.initialize("user://level08_logic_%d.json"%Time.get_ticks_usec())
	progress.levels[8]={"stars":0}
	progress.record_result({"generation":1,"level_id":8,"mode":1,"difficulty":2,"result":"victory","lives":20,"unlock_towers":["tower_bfg","tower_barbarian"]})
	check(progress.data.last_victory.level_idx==8 and "tower_bfg" in progress.data.locked_towers,"victory remains pending")
	progress.enter_map()
	check(progress.levels[8].stars==3 and progress.levels.has(9),"map commits eighth stars and ninth preview")
	check("tower_bfg" not in progress.data.locked_towers and "tower_barbarian" not in progress.data.locked_towers,"permanent eighth tower unlock")
	for id in [4,5,6,7]:
		var replay=Sim.new(Setup8.create(Levels.load_definition(id),{"locked_towers":progress.data.locked_towers,"upgrades":{"engineers":6,"barracks":6}}),42)
		check(not replay.tower_locked("tower_bfg") and not replay.tower_locked("tower_barbarian"),"permanent new tower replay availability %d"%id)
		check(replay.data.callbacks.missile_bfg.remove.ends_with("missile_bfg.remove") and replay.templates.has("soldier_barbarian") and replay.templates.has("mod_bfg_stun"),"replay tower callbacks and skill dependencies %d"%id)
	for mode in [1,2,3]:
		var data:=Setup8.create(Levels.load_definition(8,mode),{"heroes":{"selected":["hero_malik"]},"upgrades":{"engineers":6,"barracks":6}})
		var sim=Sim.new(data,42)
		check(sim.upgrades.effective.engineers==(6 if mode==1 else 5) and sim.upgrades.effective.barracks==(6 if mode==1 else 5),"eighth source technology cap %d"%mode)
		check(sim.soldiers.any(func(s):return s.has("hero"))==(mode==1),"eighth source hero restrictions %d"%mode)
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(progress.path+suffix):DirAccess.remove_absolute(progress.path+suffix)
