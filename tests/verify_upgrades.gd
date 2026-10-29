extends SceneTree
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Setup = preload("res://scripts/services/battle_setup.gd")
const Tech = preload("res://scripts/battle/dove_upgrades.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
var failures: Array[String] = []
var checks := 0
var comparisons := {}
var source_rows := 0
var behavior_scenarios := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func dismiss(sim) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")
func full_definition() -> Dictionary:
	var data := Levels.load_definition(6)
	var fifth := Levels.load_definition(5)
	for key in ["templates", "behaviors", "dependencies", "callbacks"]: data[key].merge(fifth.get(key, {}), false)
	return data
func battle(bought: Dictionary, id: int = 6, mode: int = 1):
	return Sim.new(Setup.create(Levels.load_definition(id, mode), {"upgrades":bought}), 42)

func run() -> void:
	var reference := Levels.read_json("res://tests/fixtures/dove_upgrades_source.json")
	if reference.is_empty(): push_error("Missing actual-source fixture"); quit(1); return
	check(reference.source == Levels.catalog().source, "reference uses current Dove source")
	check(Tech.definition().techs.size() == 36 and Tech.IDS.size() == 36, "complete default tree")
	for id: String in Tech.definition().techs:
		check(id in Tech.IDS, "explicit adapter " + id)
		check(not Tech.definition().techs[id].title.is_empty() and not Tech.definition().techs[id].description.is_empty(), "source localized metadata " + id)
	var base := full_definition()
	var frozen := var_to_str(base.templates)
	for row: Dictionary in reference.cases:
		var data := Setup.create(base, {"upgrades":row.levels})
		if data.is_empty(): push_error(Setup.last_error); quit(1); return
		data.layout.level_mode_overrides[0].max_upgrade_level = row.limit
		var sim = Sim.new(data, 42)
		var actual := {}
		for name: String in row.templates: actual[name] = project(sim.templates[name], row.templates[name])
		var difference := first_difference(row.templates, actual, "templates")
		check(difference == "", "source patch " + row.name + ": " + difference)
		check(sim.upgrades.reinforcement == row.reinforcement, "source reinforcement " + row.name)
		comparisons[row.name] = {"expected":row.templates,"actual":actual,"first_difference":difference}
		source_rows += row.templates.size()
	check(var_to_str(base.templates) == frozen, "source templates remain immutable")
	var combined := Tech.levels({})
	for key: String in combined: combined[key] = 6
	for id in Levels.ids():
		for mode in [1,2,3]:
			var definition := Levels.load_definition(id, mode)
			check(not definition.is_empty(), "load technology resources %d/%d" % [id,mode])
			var sim = Sim.new(Setup.create(definition, {"upgrades":combined}), 42)
			var once := var_to_str(sim.templates)
			sim.reset(42)
			check(once == var_to_str(sim.templates), "reset never accumulates %d/%d" % [id,mode])
			check(sim.upgrades.effective.archers <= int(definition.layout.level_mode_overrides[mode-1].max_upgrade_level), "source mode technology cap %d/%d" % [id,mode])
	save_cases()
	isolation_cases()
	behavior_cases()
	lifecycle_cases()
	source_behavior_cases(reference.behaviors)
	var file := FileAccess.open("res://reports/upgrades_source_comparison.json", FileAccess.WRITE)
	assert(file!=null,"Cannot write technology comparison: "+str(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(comparisons)); file.close()
	var hashes := preload("res://tests/upgrades_test_support.gd").hashes()
	for path: String in ["tests/verify_upgrades.gd","tests/fixtures/dove_upgrades_source.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	var report := {"passed":failures.is_empty(),"checks":checks,"source_patch_scenarios":reference.cases.size(),"source_template_rows":source_rows,"behavior_scenarios":behavior_scenarios,"content_combinations":Levels.ids().size()*3,"failures":failures,"source_hashes":hashes,"browser_tested":false}
	if not preload("res://tests/report_writer.gd").json_file("res://reports/upgrades_logic.json",report):quit(1);return
	print("UPGRADES: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func project(t: Dictionary, fields: Dictionary) -> Dictionary:
	var result := {}
	for key: String in fields:
		match key:
			"price": result[key] = t.tower.price
			"range": result[key] = t.attacks.range
			"rally_range": result[key] = t.barrack.rally_range
			"control":
				result[key] = {}
				for field: String in fields[key]: result[key][field] = t.get(field)
			_:
				if fields[key] is Dictionary:
					result[key] = {}
					for field: String in fields[key]: result[key][field] = t.get(key, {}).get(field)
				else: result[key] = t.get(key)
	return result

func first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary:
		if not actual is Dictionary: return path + " type"
		for key in expected:
			var result := first_difference(expected[key], actual.get(key), path + "." + str(key))
			if result != "": return result
	elif expected is Array:
		if not actual is Array or expected.size() != actual.size(): return path + " length"
		for index in expected.size():
			var result := first_difference(expected[index],actual[index],path + "[%d]" % index)
			if result != "": return result
	elif expected is float or expected is int:
		if not (actual is float or actual is int) or absf(float(expected)-float(actual)) > 0.0000001: return path + " expected=%s actual=%s" % [expected,actual]
	elif expected != actual: return path + " expected=%s actual=%s" % [expected,actual]
	return ""

func save_cases() -> void:
	var folder := "user://upgrades_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var p := Progress.new(); p.initialize(folder + "/slot1.json")
	var second := Progress.new(); second.initialize(folder + "/slot2.json")
	var third := Progress.new(); third.initialize(folder + "/slot3.json")
	p.data.last_victory = {"level_idx":1,"level_mode":1,"level_difficulty":2,"stars":3,"unlock_towers":[]}
	check(not p.set_upgrade_level("archers", 1), "pending stars cannot be spent")
	p.enter_map(); check(p.set_upgrade_level("archers", 2), "cross-level purchase sums preceding prices")
	check(p.upgrade_summary().spent == 2 and p.upgrade_summary().available == 1, "settled star accounting")
	var before: Dictionary = p.data.upgrades.duplicate(true)
	check(not p.set_upgrade_level("mages", 3) and p.data.upgrades == before, "insufficient stars is atomic")
	second.data.levels[1] = {"stars":3,1:2}; third.data.levels[1] = {"stars":3,1:2}
	check(second.set_upgrade_level("mages",2) and third.set_upgrade_level("engineers",1), "other slots purchase their own branches")
	check(second.data.upgrades.archers == 0 and third.data.upgrades.archers == 0 and p.data.upgrades.mages == 0 and third.data.upgrades.mages == 0, "technology three-slot isolation")
	p.data.upgrades.future = {"keep":true}; p.save()
	var restored := Progress.new(); restored.initialize(p.path)
	check(first_difference(p.data.upgrades,restored.data.upgrades,"slot") == "", "levels and unknown fields survive reload")
	check(p.reset_upgrades() and p.data.upgrades.archers == 0 and p.data.upgrades.future.keep, "reset preserves unknown keys")
	check(p.restore_upgrades(before) and p.data.upgrades.archers == 2, "undo restores opening snapshot")
	p.save() # Keep a valid technology snapshot in the backup before corruption.
	var file := FileAccess.open(p.path,FileAccess.WRITE); file.store_string("broken"); file.close()
	var recovered := Progress.new(); recovered.initialize(p.path)
	check(recovered.data.upgrades.archers == 2 and recovered.data.upgrades.future.keep and not recovered.notice.is_empty(), "backup recovery retains technology and unknown fields")
	p.data.last_victory = {"level_idx":1,"level_mode":2,"level_difficulty":2,"stars":1,"unlock_towers":[]}
	check(p.upgrade_summary().total == 3 and p.summary().stars == 4, "pending challenge star is excluded from technology budget")
	p.enter_map(); check(p.upgrade_summary().total == 4, "settled heroic star funds technology")
	p.data.last_victory = {"level_idx":1,"level_mode":3,"level_difficulty":2,"stars":1,"unlock_towers":[]}
	p.enter_map(); p.enter_map(); check(p.upgrade_summary().total == 5, "iron star funds technology once")
	check(not p.set_upgrade_level("archers", 7) and not p.restore_upgrades({"archers":-1}), "invalid target rejected")
	p.data.upgrade_list_id = "2"; before = p.data.duplicate(true)
	check(not p.is_playable(1) and not p.reset_upgrades() and p.data == before, "unsupported tree remains unchanged and blocks play")
	check(Setup.create(Levels.load_definition(1), p.data).is_empty(), "battle boundary rejects unsupported tree")
	p.save(); restored.initialize(p.path)
	check(restored.data.upgrade_list_id == "2" and first_difference(before.upgrades,restored.data.upgrades,"unsupported")=="", "unsupported scheme round-trips intact")
	for slot in [p,second,third]:
		for suffix in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(slot.path+suffix): DirAccess.remove_absolute(slot.path+suffix)
	DirAccess.remove_absolute(folder)

func isolation_cases() -> void:
	var slot := {"upgrades":{"archers":6,"mages":6},"seen":{"NOTICE":true},"locked_towers":["tower_musketeer"]}
	var base := Levels.load_definition(6)
	var frozen := var_to_str(base)
	var setup := Setup.create(base,slot)
	slot.upgrades.archers=0; slot.seen.NOTICE=false; slot.locked_towers.clear()
	var sim := Sim.new(setup,42)
	check(sim.upgrades.effective.archers == 6 and sim.data.seen.NOTICE and sim.data.slot_locked_towers == ["tower_musketeer"], "battle snapshot does not follow live slot mutations")
	var once := var_to_str(sim.templates);sim.reset(42)
	check(var_to_str(sim.templates)==once and var_to_str(base)==frozen, "restart reapplies from immutable base")
	var zero := Sim.new(base,42)
	var other = battle({"reinforcements":5},5,2)
	check(zero.upgrades.effective.values().all(func(v):return v==0) and zero.templates.tower_archer_1.tower.price==base.templates.tower_archer_1.tower.price, "direct simulator retains zero-technology default")
	check(other.upgrades.effective.archers==0 and sim.upgrades.effective.archers==6 and other.data.level.id==5 and other.data.level.mode==2,"level/mode/slot switch does not leak technology")
	check(Setup.create(base,{"upgrades":{"archers":2.5}}).is_empty(),"malformed technology rejected at battle boundary")

func lifecycle_cases() -> void:
	var sim = battle({"mages":6}); dismiss(sim); sim.gold=10000
	var base: float=sim.templates.bolt_1.bullet.damage_max
	var site: String=sim.towers.filter(func(t):return t.type=="")[0].id
	check(sim.command("build",{"id":site,"type":"mage"}),"brilliance real mage construction")
	sim.tick=sim.tower_by_id(site).ready;sim.upgrades.refresh_mages(sim)
	check(is_equal_approx(sim.templates.bolt_1.bullet.damage_max,base*1.18),"completed construction enters mage count")
	var first: Dictionary=sim.tower_by_id(site)
	sim._projectile("bolt_1",0,first.pos,first.pos+Vector2(100,0),1,first)
	var shot: Dictionary=sim.projectiles[-1];var snapshot: float=shot.damage_max
	var second: String=sim.towers.filter(func(t):return t.type=="")[0].id
	check(sim.command("build",{"id":second,"type":"mage"}),"brilliance second construction")
	sim.tick=sim.tower_by_id(second).ready;sim.upgrades.refresh_mages(sim)
	check(is_equal_approx(sim.templates.bolt_1.bullet.damage_max,base*1.21) and shot.damage_max==snapshot,"launched projectile keeps damage snapshot when brilliance changes")
	check(sim.command("upgrade",{"id":site,"upgrade_to":"tower_mage_2"}) and sim.upgrades.mage_count==2,"mage upgrade replaces one tower without double count")
	check(sim.command("sell",{"id":second}) and is_equal_approx(sim.templates.bolt_1.bullet.damage_max,base*1.18),"mage sale recomputes damage through transaction")
	var definition := Levels.load_definition(6,3)
	definition.layout.level_mode_overrides[2].max_upgrade_level=6 # Isolated fixture exercises preplaced towers with brilliance.
	var preplaced := Sim.new(Setup.create(definition,{"upgrades":{"mages":6}}),42)
	check(preplaced.upgrades.mage_count==2 and is_equal_approx(preplaced.templates.bolt_1.bullet.damage_max,base*1.21),"preplaced mage towers counted once on initialization")
	behavior_scenarios+=1
	sim=battle({"engineers":5});var enemy: Dictionary=sim._spawn_enemy("enemy_dark_knight",0);enemy.armor=0;enemy.hp=1000
	var point: Vector2=enemy.pos+Vector2(float(sim.templates.bomb.bullet.damage_radius)*0.9,0)
	sim._projectile("bomb",0,point,point,1.0/30);sim.tick+=1
	var hp: float=enemy.hp;sim._bullet_step(sim.projectiles[-1])
	check(is_equal_approx(hp-enemy.hp,sim.templates.bomb.bullet.damage_max),"engineer efficiency retains maximum damage at explosion edge");behavior_scenarios+=1
	sim=battle({"mages":5,"archers":6});enemy=sim._spawn_enemy("enemy_dark_knight",0)
	sim.templates.fixture_rage={"modifier":{"type":"rage"}};sim.modifiers.active.append({"target":enemy.id,"template":"fixture_rage"})
	check(not sim.modifiers.apply(sim,"mod_slow_curse",enemy,1,"0"),"rage prevents slow curse")
	sim.modifiers.active.clear()
	for attempt in range(200):sim.modifiers.apply(sim,"mod_blood_elves",enemy,1,"0",-1,1,{"value":100,"type":2})
	check(sim.modifiers.count(enemy.id,"mod_blood_elves")==5,"blood maximum is shared across repeated applications")
	enemy.hp=0;sim.modifiers.step(sim);check(sim.modifiers.active.is_empty(),"death releases all stacked statuses");behavior_scenarios+=1
	sim=battle({"reinforcements":6});var soldier: Dictionary=sim._soldier("re_legionnaire_ranged","",0,Vector2(500,300),Vector2(500,300));soldier.rallying=false
	enemy=sim._spawn_enemy("enemy_fat_orc",0);enemy.pos=soldier.pos+Vector2(5,0)
	check(not sim.upgrades.reinforcement_step(sim,soldier,sim.templates[soldier.template]),"reinforcement prioritizes available melee blocker")
	sim._soldier_step(soldier);soldier.expires=sim.tick+1;sim.tick+=1;sim._soldier_step(soldier)
	check(soldier.hp==0 and enemy.blockers.is_empty() and soldier.pending.is_empty(),"expiring reinforcement releases blocker and pending attack");behavior_scenarios+=1
	sim=battle({"reinforcements":5});soldier=sim._soldier("re_legionnaire_ranged","",0,Vector2(500,300),Vector2(500,300));soldier.rallying=false
	var near: Dictionary=sim._spawn_enemy("enemy_gargoyle",0);near.pos=soldier.pos+Vector2(5,0);near.progress=100
	var far: Dictionary=sim._spawn_enemy("enemy_gargoyle",0);far.pos=soldier.pos+Vector2(90,0)
	check(sim.upgrades.reinforcement_step(sim,soldier,sim.templates[soldier.template]) and soldier.pending.target==far.id,"ranged minimum distance filters before target selection")
	for id in [5,6]:
		var bought := {};for branch: String in Tech.definition().classes:bought[branch]=6
		sim=battle(bought,id);dismiss(sim);sim.gold=10000
		for kind: String in Sim.TYPES:
			var empty: Dictionary=sim.towers.filter(func(t):return t.type=="")[0]
			check(sim.command("build",{"id":empty.id,"type":kind}),"mixed technology build %d/%s" % [id,kind])
		check(sim.command("wave"),"mixed technology starts short battle %d" % id);dismiss(sim)
		check(sim.command("cast",{"power":"reinforcements","pos":sim.vec(sim.data.paths.paths[0][0][40])}),"mixed reinforcement cast %d" % id)
		for frame in range(360):dismiss(sim);sim.step()
		check(sim.tick==360 and sim.upgrades.mage_count==1 and sim.upgrades.reinforcement=="re_legionnaire_ranged","mixed technology short combat %d" % id);behavior_scenarios+=1

func behavior_cases() -> void:
	var sim = battle({"archers":5})
	var tower: Dictionary = sim.towers[0]; tower.type = "archer"; tower.template = "tower_archer_1"
	var critical := 0
	for index in range(100):
		sim._projectile("arrow_1", 0, Vector2.ZERO, Vector2(100,0), 1, tower)
		var p: Dictionary = sim.projectiles[-1]
		if p.get("critical",false): critical += 1; check(p.damage_max == sim.templates.arrow_1.bullet.damage_max * 2, "critical snapshots projectile damage")
	check(critical > 0 and critical < 100, "critical deterministic chance path"); behavior_scenarios += 1
	sim = battle({"archers":3})
	var enemy: Dictionary = sim._spawn_enemy("enemy_dark_knight",0)
	var hp: float = enemy.hp
	sim.damage(enemy, 100, 2, 0, 0.1)
	check(is_equal_approx(hp-enemy.hp, 100*(1-float(sim.templates[enemy.template].health.armor)+0.1)), "armor penetration uses reduced protection"); behavior_scenarios += 1
	sim = battle({"mages":5})
	enemy = sim._spawn_enemy("enemy_dark_knight",0)
	var armor: float = sim.templates[enemy.template].health.armor
	sim.modifiers.apply(sim,"mod_arcane_shatter",enemy,1,"0")
	check(is_equal_approx(enemy.armor, armor - 0.035), "arcane shatter permanently reduces armor")
	check(sim.modifiers.apply(sim,"mod_slow_curse",enemy,1,"0") and sim.modifiers.speed(enemy.id,sim) < 1, "slow curse applied")
	sim.tick += 31; sim.modifiers.step(sim); check(sim.modifiers.speed(enemy.id,sim) == 1, "slow expires"); behavior_scenarios += 1
	sim = battle({"archers":6})
	enemy = sim._spawn_enemy("enemy_dark_knight",0)
	var bleeds := 0
	for index in range(200):
		if sim.modifiers.apply(sim,"mod_blood_elves",enemy,1,"0",-1,1,{"value":100,"type":2}): bleeds += 1
	check(bleeds == 5, "bloodletting chance and five-stack ceiling")
	hp = enemy.hp; sim.tick += 1; sim.modifiers.step(sim)
	check(enemy.hp < hp, "bloodletting deals periodic damage"); behavior_scenarios += 1
	sim = battle({"barracks":5})
	enemy = sim._spawn_enemy("enemy_fat_orc",0)
	var soldier: Dictionary = sim._soldier("soldier_militia","",0,Vector2.ZERO,Vector2.ZERO)
	hp = enemy.hp; sim.damage(soldier,10,2,enemy.id)
	check(enemy.hp == hp and sim.upgrades.reflected.size() == 1,"reflection is deferred")
	sim.upgrades.step(sim); check(is_equal_approx(enemy.hp,hp-1),"reflection uses raw incoming damage"); behavior_scenarios += 1
	sim = battle({"mages":6})
	var base_damage: float = sim.templates.bolt_1.bullet.damage_max
	for index in range(2):
		tower = sim.towers[index]; tower.type="mage"; tower.template="tower_mage_1"; tower.ready=0
		sim.upgrades.refresh_mages(sim)
	check(is_equal_approx(sim.templates.bolt_1.bullet.damage_max, base_damage*1.21),"brilliance counts mage towers")
	sim.towers[1].template=sim.towers[1].holder; sim.towers[1].type=""; sim.upgrades.refresh_mages(sim)
	check(is_equal_approx(sim.templates.bolt_1.bullet.damage_max,base_damage*1.18),"selling mage recomputes from base")
	sim.upgrades.refresh_mages(sim); check(is_equal_approx(sim.templates.bolt_1.bullet.damage_max,base_damage*1.18),"brilliance never accumulates"); behavior_scenarios += 1
	sim = battle({"rain":6}); sim.upgrades.cast_fire(sim,Vector2(500,300))
	for tick in range(61): sim.tick=tick; sim.upgrades.step(sim)
	check(sim.projectiles.size()==12,"extra fireballs and cataclysm count")
	sim.upgrades.scorched(sim,Vector2(500,300)); enemy=sim._spawn_enemy("enemy_fat_orc",0); enemy.pos=Vector2(500,300)
	hp=enemy.hp; sim.tick+=1; sim.upgrades.step(sim); check(enemy.hp<hp,"scorched ground deals area damage"); behavior_scenarios += 1
	sim = battle({"reinforcements":6}); dismiss(sim); sim.command("wave"); dismiss(sim)
	check(sim.command("cast",{"power":"reinforcements","pos":sim.vec(sim.data.paths.paths[0][0][40])}),"advanced reinforcement cast")
	check(sim.soldiers.filter(func(s): return s.template=="re_legionnaire_ranged").size()==2,"advanced reinforcement template")
	check(sim.cooldowns.reinforcements==240 and sim.soldiers[-1].expires==750,"level six duration and cooldown")
	soldier=sim.soldiers[-1]; soldier.rallying=false; enemy=sim._spawn_enemy("enemy_gargoyle",0); enemy.pos=soldier.pos+Vector2(90,0)
	check(sim.upgrades.reinforcement_step(sim,soldier,sim.templates[soldier.template]),"reinforcement acquires flying ranged target")
	sim.tick+=3; sim.upgrades.reinforcement_step(sim,soldier,sim.templates[soldier.template]); check(not sim.projectiles.is_empty() and sim.projectiles[-1].template=="spear_legionnaire","reinforcement launches spear"); behavior_scenarios += 1

func source_behavior_cases(reference: Dictionary) -> void:
	var sim = battle({"archers":6, "mages":6, "rain":6})
	var precision_samples: Array=[]
	for row: Dictionary in reference.precision:
		for seed_value in range(1000):
			sim.rng.seed=seed_value
			var critical: bool=sim.rng.randf()<float(sim.upgrades.get_tech("archer_precision").chance)
			if critical!=row.critical:continue
			sim.templates.arrow_1.bullet.damage_min=4;sim.templates.arrow_1.bullet.damage_max=6;sim.rng.seed=seed_value
			sim._projectile("arrow_1",0,Vector2.ZERO,Vector2(100,0),1,{"id":0,"type":"archer","template":"tower_archer_1"})
			var shot: Dictionary=sim.projectiles[-1]
			precision_samples.append({"draw":row.draw,"min":shot.damage_min,"max":shot.damage_max,"critical":shot.get("critical",false)})
			break
	var precision_difference := first_difference(reference.precision,precision_samples,"precision")
	check(precision_difference=="","actual source precision helper: "+precision_difference)
	comparisons.source_precision={"expected":reference.precision,"actual":precision_samples,"first_difference":precision_difference}
	var enemy: Dictionary = sim._spawn_enemy("enemy_dark_knight",0)
	enemy.hp=10000; enemy.max_hp=10000; enemy.armor=0.8; enemy.received_damage_factor=1.2
	var hp: float = enemy.hp
	sim.damage(enemy,100,2,0,0.1)
	check(is_equal_approx(hp-enemy.hp,reference.penetration),"actual source armor prediction")
	var applied := false
	for attempt in range(100):
		if sim.modifiers.apply(sim,"mod_blood_elves",enemy,1,"0",-1,1,{"value":100,"type":2,"reduce_armor":0.1}): applied=true; break
	check(applied and is_equal_approx(sim.modifiers.active[0].bleeding, reference.bleeding_damage),"actual source blood damage derivation")
	var pulses: Array = []
	for tick in range(1,92):
		sim.tick=tick; hp=enemy.hp; sim.modifiers.step(sim)
		if enemy.hp<hp: pulses.append({"tick":tick,"value":roundf((hp-enemy.hp)/1.2 * 1000000)/1000000,"kind":1})
	var difference := first_difference(reference.bleeding_pulses,pulses,"bleeding")
	check(difference=="","actual source blood coroutine: "+difference)
	comparisons.source_bleeding={"expected":reference.bleeding_pulses,"actual":pulses,"first_difference":difference}; behavior_scenarios+=1
	check(sim.modifiers.apply(sim,"mod_slow_curse",enemy,1,"0")==reference.slow_insert,"actual source slow insert")
	check(60*sim.modifiers.speed(enemy.id,sim)==reference.slow_speed,"actual source slow factor")
	sim.tick+=15; sim.modifiers.step(sim)
	check(60*sim.modifiers.speed(enemy.id,sim)==reference.slow_removed_speed,"actual source slow removal"); behavior_scenarios+=1
	# Fix the random roll range, keeping the actual source aura values and timing.
	sim=battle({"rain":6}); sim.templates.power_scorched_earth.aura.damage_min=25; sim.templates.power_scorched_earth.aura.damage_max=25
	enemy=sim._spawn_enemy("enemy_dark_knight",0); enemy.pos=Vector2(500,300); enemy.hp=10000; enemy.armor=0
	var flying: Dictionary=sim._spawn_enemy("enemy_gargoyle",0); flying.pos=enemy.pos
	var immune: Dictionary=sim._spawn_enemy("enemy_dark_knight",0); immune.pos=enemy.pos; immune.vis=sim.templates[immune.template].vis.duplicate(); immune.vis.bans=4
	var flying_hp: float=flying.hp; var immune_hp: float=immune.hp
	sim.tick=60; sim.upgrades.scorched(sim,enemy.pos); pulses=[]
	for tick in range(61,363):
		sim.tick=tick; hp=enemy.hp; sim.upgrades.step(sim)
		if enemy.hp<hp:pulses.append({"tick":tick,"value":hp-enemy.hp,"kind":2})
	difference=first_difference(reference.scorched_pulses,pulses,"scorched")
	check(difference=="" and flying.hp==flying_hp and immune.hp==immune_hp,"actual source aura timing and visibility: "+difference)
	comparisons.source_scorched={"expected":reference.scorched_pulses,"actual":pulses,"first_difference":difference};behavior_scenarios+=1
	sim=battle({"rain":6});sim.templates.power_fireball_control.max_spread=0
	sim.data.terrain.grid=sim.data.terrain.grid.duplicate(true)
	for column: Array in sim.data.terrain.grid: column.fill(1)
	var path: Array=[]
	for index in range(300):path.append({"x":500,"y":index*6})
	sim.data.paths.paths=[[path,path,path]];sim.data.paths.active=[true]
	enemy=sim._spawn_enemy("enemy_dark_knight",0);enemy.node=50;enemy.pos=Vector2(500,300);enemy.last_dir=Vector2(0,1)
	sim.templates[enemy.template].motion.max_speed=30;sim.data.rules.enemy_speed_factor=1
	sim.upgrades.cast_fire(sim,Vector2(500,300))
	for tick in range(71):sim.tick=tick;sim.upgrades.step(sim)
	var bursts: Array=[]
	for p: Dictionary in sim.projectiles:bursts.append({"tick":p.at,"to":{"x":p.to.x,"y":p.to.y}})
	difference=first_difference(reference.fire_bursts,bursts,"fire")
	check(difference=="","actual source fire control and prediction: "+difference)
	comparisons.source_fire={"expected":reference.fire_bursts,"actual":bursts,"first_difference":difference};behavior_scenarios+=1
	sim=battle({"mages":6});var base: float=sim.templates.bolt_1.bullet.damage_max;var factors: Array=[]
	for operation: Array in [[true,0],[true,1],[false,0],[false,1],[true,2]]:
		var tower: Dictionary=sim.towers[operation[1]]
		tower.template="tower_mage_1" if operation[0] else tower.holder;tower.type="mage" if operation[0] else "";tower.ready=0
		sim.upgrades.refresh_mages(sim);factors.append(sim.templates.bolt_1.bullet.damage_max/base)
	difference=first_difference(reference.brilliance,factors,"brilliance")
	check(difference=="","actual source brilliance insert/remove: "+difference)
	comparisons.source_brilliance={"expected":reference.brilliance,"actual":factors,"first_difference":difference};behavior_scenarios+=1
