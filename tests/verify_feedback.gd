extends SceneTree
## Bounded source-function comparisons for the eight reported issues.
const Levels=preload("res://scripts/services/campaign_levels.gd")
const Sim=preload("res://scripts/battle/level01_sim.gd")
var checks:=0
var failures: Array[String]=[]
var comparisons: Array=[]
var source: Dictionary
func _init(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures.append(label);push_error(label)
func fresh(id: int=6,mode: int=1):
	var sim=Sim.new(Levels.load_definition(id,mode),42);sim.notices.clear();return sim
func close(a: float,b: float):return absf(a-b)<0.0002
func powers():
	var simulations := {}
	for row: Dictionary in source.powers:
		if not simulations.has(row.content): simulations[row.content]=fresh(int(row.content))
		var sim=simulations[row.content]
		var tower: Dictionary={}
		for name: String in sim.templates:
			if sim.templates[name].has("tower") and sim.templates[name].get("powers",{}).has(row.power):
				tower={"template":name,"type":sim.templates[name].tower.type,"powers":{row.power:int(row.level)-1},"damage_factor":row.factor,"cooldown_factor":row.cooldown};break
		check(not tower.is_empty(),"source power owner "+row.power)
		if tower.is_empty():continue
		var before:=var_to_str([sim.templates,sim.rng.state,tower])
		var actual: Dictionary=sim.power_preview(tower,row.power)
		var rich:=""
		for span: Dictionary in actual.runs:rich+=span.text
		check(actual.text==row.text,"original formatter %s/%s level%d factor%s" % [row.content,row.power,row.level,row.factor])
		check(rich==row.comparison,"original numeric diff "+row.power+str(row.level))
		check(before==var_to_str([sim.templates,sim.rng.state,tower]),"preview is read-only "+row.power)
		if int(row.level)==3:
			tower.powers[row.power]=3;actual=sim.power_preview(tower,row.power)
			check(actual.maxed and not actual.runs.any(func(r):return r.text=="→"),"maxed current data "+row.power)
	var sim=fresh();var tower={"template":"tower_arcane_wizard","type":"arcane_wizard","powers":{"disintegrate":1}}
	check(sim.power_preview(tower,"disintegrate").text.contains("4.7%"),"fraction formatted as source percentage")
	check(sim.data.ui.strings.TOWER_PALADIN_NAME=="神圣秩序","source Paladin tower title retained")
	for prefix in ["TOWER_ARCANE_WIZARD","TOWER_PALADIN"]:check(not sim.data.ui.strings[prefix+"_EXTRA"].begins_with("TOWER_"),"dual tower copy "+prefix)

func bombs():
	for row: Dictionary in source.bombs:
		var sim=fresh();sim.soldiers.clear();sim.towers.clear()
		var enemy: Dictionary=sim._spawn_enemy("enemy_goblin",0);enemy.pos=Vector2(300,300);enemy.hp=1000;enemy.max_hp=1000
		sim._projectile(row.template,enemy.id,Vector2(200,250),Vector2(300,300),sim.templates[row.template].bullet.flight_time)
		var p: Dictionary=sim.projectiles[-1];p.initial_rotation=0.0
		# Retain this original 30-fps oracle; production defaults are additionally
		# compared at 30/60/144 fps by verify_followup.gd.
		p.merge(Sim.Projectile.bomb_timing(sim.templates[row.template].bullet.flight_time,sim.tick/30.0,30),true)
		var first:=-1
		for sample: Array in row.samples:
			sim.tick=int(sample[0]);sim._bullet_step(p)
			if not close(p.pos.x,sample[1]) or not close(p.pos.y,sample[2]) or sim.tick>0 and not close(p.rotation,sample[3]) or p.hidden!=sample[4]:
				if first<0:first=sim.tick
		check(first<0,"original bomb flight first difference %s=%d" % [row.template,first])
		check(p.done and close(1000-enemy.hp,row.hits[0][1]),"source explosion falloff "+row.template)
		check(sim.effects.size()==row.effects.size() and sim.effects.all(func(e):return e.pos.is_equal_approx(p.pos)),"actual impact and decal agree "+row.template)
		comparisons.append({"behavior":row.template,"first_difference":first,"frames":row.samples.size()})

func cannons():
	for row: Dictionary in source.foremost:
		var sim=fresh();var a: Dictionary=sim._spawn_enemy("enemy_goblin",0);var b: Dictionary=sim._spawn_enemy("enemy_goblin",0)
		a.pos=Vector2(300,300);b.pos=Vector2(310,300);a.node=10;a.progress=10.1;b.node=10 if row.scenario=="same_node" else 11;b.progress=float(b.node)+0.9
		if row.scenario=="mocking":a.vis=sim.templates[a.template].vis.duplicate();a.vis.flags=int(a.vis.flags)|64
		var target: Dictionary=sim._target(Vector2(300,300),160,false,sim.templates.tower_engineer_1.attacks.list[0],true)
		check(target.id==(a.id if int(row.target)==101 else b.id),"actual source cannon priority "+row.scenario)
	for row: Dictionary in source.cannons:
		var sim=fresh();sim.soldiers.clear();sim.towers.clear()
		sim.data.paths.paths=[[[ ]]];sim.data.paths.active=[true];sim.data.layout.invalid_path_ranges=[]
		for i in 80:sim.data.paths.paths[0][0].append({"x":200+i*8,"y":300})
		var tower: Dictionary=sim._holder({"id":"probe","pos":Vector2(200,200),"rally":Vector2.ZERO,"holder":"tower_holder_grass"})
		tower.type="engineer";tower.template="tower_engineer_1";tower.ready=0;tower.inserted=true;tower.attack_at=90;sim.towers.append(tower)
		var enemy: Dictionary=sim._spawn_enemy("enemy_goblin",0);enemy.pos=Vector2(283,300);enemy.node=10;enemy.progress=10;enemy.last_dir=Vector2(1,0) if row.scenario=="moving" else Vector2.ZERO
		for frame in range(90,106):
			sim.tick=frame
			if frame==102 and row.scenario in ["reselect","dead_without_replacement"]:
				sim.damage(enemy,9999,1)
				if row.scenario=="reselect":
					var other: Dictionary=sim._spawn_enemy("enemy_goblin",0);other.pos=Vector2(296,300);other.node=12;other.progress=12
			sim._tower_step(tower)
			if not sim.projectiles.is_empty():break
		check(sim.projectiles.size()==1,"source cannon emits "+row.scenario)
		if sim.projectiles.is_empty():continue
		var p: Dictionary=sim.projectiles[0]
		var actual: Array=[sim.tick,p.from.x,p.from.y,p.to.x,p.to.y]
		var first:=-1
		for index in actual.size():
			if not close(float(actual[index]),float(row.shot[index])):first=sim.tick;break
		check(first<0,"source firing tick and node destination "+row.scenario+" actual "+str(actual)+" expected "+str(row.shot))
		comparisons.append({"behavior":"cannon","scenario":row.scenario,"expected":row.shot,"actual":actual,"first_difference":first})

func guards():
	for mode in [1,2]:
		for row: Dictionary in source.guards:
			var sim=fresh(6,mode);sim.towers.clear()
			var guard: Dictionary=sim.soldiers[0];guard.rallying=false
			var a: Dictionary=sim._spawn_enemy("enemy_goblin",0);a.pos=guard.rally_center+Vector2(20,0);a.node=10;a.progress=10
			var b: Dictionary=sim._spawn_enemy("enemy_goblin",0);b.pos=guard.rally_center+Vector2(40,0);b.node=11;b.progress=11
			if row.scenario in ["primary","secondary","invalid_block"]:
				guard.target=a.id;a.blockers=[999,guard.id] if row.scenario=="secondary" else [guard.id];a.blocker=a.blockers[0]
			if row.scenario=="invalid_block":a.vis=sim.templates[a.template].vis.duplicate();a.vis.bans=1
			if row.scenario=="no_walk":
				var cell_x:=ceili((b.pos.x-float(sim.data.terrain.ox))/16)-1;var cell_y:=ceili((b.pos.y-float(sim.data.terrain.oy))/16)-1
				sim.data.terrain.grid[cell_x][cell_y]=256
			if row.scenario=="cliff":b.vis=sim.templates[b.template].vis.duplicate();b.vis.flags=256
			if row.scenario=="outside":a.pos.x=400;b.pos.x=420
			if row.scenario=="dead":a.hp=0;b.node=9;b.progress=9
			sim.tick=90;sim._soldier_step(guard)
			var target:=101 if guard.target==a.id else 102 if guard.target==b.id else 0
			check(target==int(row.target),"source guard selection %d/%s actual%d expected%d" % [mode,row.scenario,target,row.target])
		# Real placements: a passing ground enemy must be acquired by every idle guard.
		var sim=fresh(6,mode)
		for guard: Dictionary in sim.soldiers:
			guard.rallying=false;sim.enemies.clear()
			var e: Dictionary=sim._spawn_enemy("enemy_goblin",0);e.pos=guard.rally_center+Vector2(20,0);e.node=20;e.progress=20
			sim.tick=90;sim._soldier_step(guard)
			check(guard.target==e.id and guard.id in e.blockers,"real preplaced guard intercepts mode%d id%d" % [mode,guard.id])
			sim.damage(e,9999,1);sim.tick+=60;sim._soldier_step(guard)
			check(guard.target==0,"guard releases killed target mode%d id%d" % [mode,guard.id])
	for row: Array in source.slots:
		var sim=fresh();var s: Dictionary=sim.soldiers[0];var e: Dictionary=sim._spawn_enemy("enemy_goblin",0);e.pos=Vector2(300,390);e.last_dir=Vector2.RIGHT if float(row[1])==0 else Vector2.LEFT;e.blockers=[-1,-2,-3,-4];e.blockers[int(row[0])-1]=s.id
		check(sim.melee_slot(s,e).distance_to(Vector2(row[2],row[3]))<0.001,"source melee slot rank "+str(row[0])+" angle"+str(row[1]))
	for row: Dictionary in source.guard_motion:
		var sim=fresh();var s: Dictionary=sim.soldiers[0];s.pos=Vector2(326-float(row.offset),390);s.rallying=false;s.rally_center=Vector2(300,390)
		var e: Dictionary=sim._spawn_enemy("enemy_goblin",0);e.pos=Vector2(300,390);e.last_dir=Vector2.RIGHT;e.node=20;e.progress=20
		var first:=-1
		for sample: Array in row.samples:
			sim.tick=90+int(sample[0]);sim._soldier_step(s)
			var moving: bool=s.pending.is_empty()
			if not close(s.pos.x,sample[1]) or not close(s.pos.y,sample[2]) or moving!=sample[3]:
				if first<0:first=int(sample[0])
		check(first<0,"actual source guard movement and arrival yield offset%s first difference%d" % [row.offset,first])
		comparisons.append({"behavior":"guard_slot_movement","offset":row.offset,"frames":row.samples.size(),"first_difference":first})

func run():
	create_timer(150).timeout.connect(func():push_error("Feedback logic timeout");quit(1))
	source=Levels.read_json("res://tests/fixtures/feedback_source.json")
	powers();bombs();cannons();guards()
	for id in range(1,8):
		for mode in [1,2,3]:check(not Levels.load_definition(id,mode).is_empty(),"content load %d/%d" % [id,mode])
	var hashes:={}
	for path in ["tests/verify_feedback.gd","tests/fixtures/feedback_source.json","scripts/battle/level01_sim.gd","scripts/battle/dove_paladin.gd","scripts/battle/dove_projectile.gd","scripts/battle/dove_power_preview.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd","scripts/battle/dove_ui_layout.gd","scripts/map/upgrades_room.gd","scripts/map/map_interface.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	var file=FileAccess.open("res://reports/feedback_logic.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_hashes":hashes,"source_power_rows":source.powers.size(),"source_cannon_scenarios":source.cannons.size(),"source_bomb_scenarios":source.bombs.size(),"source_guard_scenarios":source.guards.size(),"source_priority_scenarios":source.foremost.size(),"source_guard_motion_scenarios":source.guard_motion.size(),"source_slot_rows":source.slots.size(),"comparisons":comparisons,"content_combinations":21},"\t"));file.close()
	print("FEEDBACK: ","PASS" if failures.is_empty() else failures," checks=",checks)
	quit(0 if failures.is_empty() else 1)
