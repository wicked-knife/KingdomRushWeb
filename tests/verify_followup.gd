extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Writer = preload("res://tests/report_writer.gd")
var failures: Array[String] = []
var checks := 0
var comparisons: Array = []
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func fresh():
	var sim=Sim.new(Levels.load_definition(6))
	sim.notices.clear();sim.alerts.clear();sim.spawn_queue.clear();sim.gold=10000
	return sim
func buy(sim, kind: String, final: String="") -> Dictionary:
	check(sim.command("build",{"id":"1","type":kind}),"build "+kind)
	for frame in 30:sim.step()
	if final!="":
		for target in ["tower_"+kind+"_2","tower_"+kind+"_3",final]:check(sim.command("upgrade",{"id":"1","upgrade_to":target}),"upgrade "+target)
	return sim.tower_by_id("1")
func bombs(source: Dictionary) -> void:
	var sim=fresh()
	for row: Dictionary in source.bombs:
		var b: Dictionary=sim.templates[row.template].bullet
		var p: Dictionary={"from":Vector2(200,250),"to":Vector2(300,300),"initial_rotation":0.0}
		p.merge(Sim.Projectile.bomb_timing(row.flight,0,int(row.fps)))
		p.velocity=Sim.Projectile.launch(p.from,p.to,row.flight,b)
		var actual: Array=[];var first:=-1
		for i in row.samples.size():
			var expected: Array=row.samples[i];var sample:=Sim.Projectile.sample_bomb(p,b,expected[0])
			actual.append([expected[0],sample.pos.x,sample.pos.y,sample.rotation,sample.hidden])
			if first<0 and (sample.pos.distance_to(Vector2(expected[1],expected[2]))>0.002 or absf(sample.rotation-float(expected[3]))>0.002 or sample.hidden!=expected[4]):first=i
		check(first<0,"original bomb trajectory %s/%dfps first difference %d" % [row.template,row.fps,first])
		comparisons.append({"scenario":"%s/%dfps" % [row.template,row.fps],"first_difference":first,"expected":row.samples,"actual":actual})
	check(Sim.Projectile.BOMB_FPS==int(source.default_fps),"ordinary bombs use actual source default physics step")
	sim._projectile("bomb",0,Vector2(200,250),Vector2(300,300),sim.templates.bomb.bullet.flight_time)
	var p: Dictionary=sim.projectiles[-1]
	check(p.integration_fps==144,"production projectile uses source default")
	while not p.done:sim.tick+=1;sim._bullet_step(p)
	check(p.pos.y<307 and p.pos.y>300,"default source residual is under seven world units instead of 28")
	check(sim.effects.all(func(e):return e.pos.is_equal_approx(p.pos)),"actual impact, explosion and crater remain identical")
func casts(source: Dictionary) -> void:
	for row: Dictionary in source.casts:
		var sim=fresh();var tower:=buy(sim,"mage","tower_arcane_wizard")
		sim.tick=0;tower.ready=0;tower.pos=Vector2(400,300);tower.cooldown_factor=row.cooldown_factor
		Sim.Behaviors.Arcane.initialize(sim,tower)
		check(sim.command("upgrade_power",{"id":"1","power":"teleport"}),"buy teleport")
		var enemy=sim._spawn_enemy("enemy_marauder",0);enemy.pos=Vector2(450,310);enemy.node=49;enemy.progress=49;enemy.hp=100000
		var actual: Array=[]
		for frame in 1001:
			sim.tick=frame;var rays: int=sim.projectiles.size();var auras: int=sim.auras.size()
			Sim.Behaviors.Arcane.step(sim,tower)
			if sim.projectiles.size()>rays:actual.append([frame,sim.projectiles[-1].template])
			if sim.auras.size()>auras:actual.append([frame,sim.auras[-1].template])
		var first:=-1
		for i in maxi(actual.size(),row.events.size()):
			if i>=actual.size() or i>=row.events.size() or int(actual[i][0])!=int(row.events[i][0]) or actual[i][1]!=row.events[i][1]:first=i;break
		check(first<0,"original automatic arcane arbitration factor%s first difference%d actual%s expected%s" % [row.cooldown_factor,first,actual,row.events])
		check(actual.filter(func(e):return e[1]=="aura_teleport_arcane").size()>=2,"teleport automatically casts repeatedly alongside normal attacks")
		comparisons.append({"scenario":"arcane cooldown %s" % row.cooldown_factor,"first_difference":first,"expected":row.events,"actual":actual})
		var bad: Dictionary=sim.animations.duplicate();bad.erase("tower_arcane_wizard_teleport")
		check(not Sim.Behaviors.Arcane.animation_error(sim.templates.tower_arcane_wizard,bad).is_empty(),"missing cast animation blocks content")
func sales(source: Dictionary) -> void:
	check(int(source.sale.remaining)==0 and int(source.sale.removed[0])==10 and int(source.sale.removed[1])==11,"original sale removes garrison immediately")
	for final in ["","tower_paladin"]:
		var sim=fresh();var tower:=buy(sim,"barrack",final)
		for frame in 100:sim.step()
		var own: Array=sim.soldiers.filter(func(s):return s.home==tower.id)
		var guards: Array=sim.soldiers.filter(func(s):return s.home=="")
		check(own.size()==3,"sale fixture garrison "+final)
		var e=sim._spawn_enemy("enemy_fat_orc",0);e.pos=own[0].pos;own[0].target=e.id;e.blocker=own[0].id;e.blockers=[own[0].id]
		check(sim.command("sell",{"id":tower.id}),"sell "+final)
		check(sim.soldiers.size()==guards.size() and own.all(func(s):return sim.unit_by_id(s.id).is_empty()),"source removal without death animation or corpse "+final)
		check(e.blocker==0 and e.blockers.is_empty(),"sale releases blocking "+final)
		check(sim.soldiers==guards,"sale preserves preplaced guards "+final)
func _run() -> void:
	var source=Levels.read_json("res://tests/fixtures/followup_source.json")
	bombs(source);casts(source);sales(source)
	var hashes:={}
	for path in ["tests/verify_followup.gd","tests/fixtures/followup_source.json","scripts/battle/dove_projectile.gd","scripts/battle/dove_arcane.gd","scripts/battle/level01_sim.gd","scripts/battle/battle_view.gd","scripts/battle/battle_ui.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	Writer.json_file("res://reports/followup_logic.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"comparisons":comparisons,"source_hashes":hashes})
	print("FOLLOWUP_LOGIC ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
