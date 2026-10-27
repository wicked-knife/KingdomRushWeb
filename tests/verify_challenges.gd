extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Playback = preload("res://tests/challenge_playback.gd")
const CASH := {2: [230,310,400,750,1000], 3: [360,275,660,1500,1500]}
const IRON_BANS := {1:["archer","mage"],2:["barrack"],3:["engineer"],4:["mage","engineer"],5:["barrack"]}
const SOURCE_LOCKS := {
	"1/2":["tower_archer_2","tower_barrack_2","tower_engineer_2","tower_mage_2"],
	"1/3":["tower_barrack_2","tower_engineer_2","tower_build_archer","tower_build_mage"],
	"2/2":["tower_archer_3","tower_barrack_3","tower_mage_3","tower_engineer_3"],
	"2/3":["tower_archer_3","tower_build_barrack","tower_mage_3","tower_engineer_3"],
	"3/2":["tower_archer_3","tower_barrack_3","tower_mage_3","tower_engineer_3"],
	"3/3":["tower_archer_3","tower_barrack_3","tower_mage_3","tower_build_engineer"],
	"4/2":[],"4/3":["tower_build_mage","tower_build_engineer"],"5/2":[],"5/3":["tower_build_barrack"]}
const COUNTS := {
	"1/2":{"enemy_goblin":86,"enemy_fat_orc":20}, "1/3":{"enemy_fat_orc":16,"enemy_goblin":70},
	"2/2":{"enemy_wolf_small":60,"enemy_goblin":58,"enemy_fat_orc":18}, "2/3":{"enemy_wolf_small":9,"enemy_goblin":99,"enemy_fat_orc":35},
	"3/2":{"enemy_wolf_small":10,"enemy_goblin":146,"enemy_fat_orc":34,"enemy_shaman":29,"enemy_ogre":11}, "3/3":{"enemy_goblin":80,"enemy_shaman":6,"enemy_ogre":4,"enemy_fat_orc":45},
	"4/2":{"enemy_goblin":61,"enemy_wolf_small":30,"enemy_fat_orc":50,"enemy_bandit":19,"enemy_brigand":33,"enemy_shaman":5,"enemy_ogre":8}, "4/3":{"enemy_goblin":150,"enemy_wolf_small":135},
	"5/2":{"enemy_bandit":65,"enemy_brigand":32,"enemy_spider_small":76,"enemy_marauder":9,"enemy_spider_big":11,"enemy_wolf":8}, "5/3":{"enemy_marauder":7,"enemy_bandit":55,"enemy_brigand":39,"enemy_spider_big":10,"enemy_spider_small":35}}
var failures: Array[String] = []
var checks := 0
var report := {"modes": {}, "passed": false, "acceptance_basis": "dove_configuration_and_functionality", "victory_replays_required": false, "replays_run": false}
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func dismiss(s) -> void:
	while not s.notices.is_empty(): s.command("confirm")

func timeline(s, key: String) -> void:
	var counts := {}
	dismiss(s)
	for group: Dictionary in s.data.waves.groups:
		var started: int = s.tick
		check(s.command("wave"), key + " starts next source group")
		var expected: Array = []
		for w: Dictionary in group.waves:
			var at: int = started + int(w.delay)
			for index in w.spawns.size():
				var spawn: Dictionary = w.spawns[index]
				for n in int(spawn.max):
					at += int(spawn.interval)
					var type: String = spawn.creep
					if spawn.get("max_same",0) > 0 and spawn.has("creep_aux") and (n / int(spawn.max_same)) % 2 == 1: type = spawn.creep_aux
					expected.append({"tick":at,"type":type,"path":int(w.path_index)-1,"subpath":int(spawn.path)-1 if int(spawn.fixed_sub_path)==1 else -1,"order":expected.size()})
				if int(spawn.max)==0: at += int(spawn.interval)
				if index+1 < w.spawns.size(): at += int(spawn.interval_next)
		expected.sort_custom(func(a,b): return a.tick < b.tick if a.tick != b.tick else a.order < b.order)
		var before: int = s.spawn_log.size()
		while not s.spawn_queue.is_empty():
			dismiss(s); s.enemies.clear(); s.step()
		var actual: Array = s.spawn_log.slice(before)
		var mismatch := "count %d != %d" % [actual.size(),expected.size()] if actual.size()!=expected.size() else ""
		for i in actual.size():
			var a: Dictionary = actual[i]
			if i < expected.size() and mismatch.is_empty():
				var e: Dictionary = expected[i]
				for field in ["tick","type","path","subpath"]:
					if field=="subpath" and e.subpath<0: continue
					if a[field]!=e[field]:
						mismatch="enemy %d %s: %s != %s" % [i,field,str(a[field]),str(e[field])];break
			counts[a.type]=int(counts.get(a.type,0))+1
		check(mismatch.is_empty(),key+" wave %d complete spawn timeline: " % s.wave+mismatch)
		s.enemies.clear()
	check(counts==COUNTS[key],key+" frozen source roster")

func run() -> void:
	var with_replays := OS.get_cmdline_user_args().has("--with-replays")
	report.replays_run=with_replays
	for id in range(1,6):
		check(Levels.load_definition(id).waves.lives==20,"%d challenge loading preserves campaign fields" % id)
		for mode in [2,3]:
			var key := "%d/%d" % [id,mode]
			var d := Levels.load_definition(id,mode)
			check(not d.is_empty(),key+" manifest loads")
			var representative: bool=(id==1 and mode==2) or (id==5 and mode==3)
			if representative:
				var isolated:=Levels.load_definition(id,mode)
				isolated.waves.cash=-1;isolated.layout.entities_list.clear();isolated.templates.tower_archer_1.tower.price=-1
				var pristine:=Levels.load_definition(id,mode)
				check(pristine.waves.cash==CASH[mode][id-1] and not pristine.layout.entities_list.is_empty() and pristine.templates.tower_archer_1.tower.price==70,key+" mode data and templates are isolated")
			var s = Sim.new(d,42)
			check(s.gold==CASH[mode][id-1] and s.lives==1 and s.data.level.mode==mode,key+" identity and initial economy")
			check(s.data.waves.groups.size()==(6 if mode==2 else 1),key+" group count")
			var rules: Dictionary = s.data.layout.level_mode_overrides[mode-1]
			var actual_locks: Array=[]
			for locked in rules.get("locked_towers",[]):actual_locks.append(locked)
			var expected_locks: Array=SOURCE_LOCKS[key].duplicate()
			actual_locks.sort();expected_locks.sort()
			check(rules.locked_hero and rules.max_upgrade_level==[2,3,3,3,4][id-1] and actual_locks==expected_locks,key+" frozen source hero, technology and target-template locks")
			check(s.data.layout.entities_list.all(func(e): return int(e.get("editor.game_mode",0)) in [0,mode]),key+" layout only uses active mode")
			check(not s.notices.any(func(n): return str(n).begins_with("TUTORIAL_")),key+" campaign tutorials absent")
			dismiss(s)
			var bans: Array=IRON_BANS[id] if mode==3 else []
			check(Sim.TYPES.filter(func(kind):return s.tower_locked("tower_build_"+kind))==bans,key+" frozen Dove build bans")
			for kind: String in Sim.TYPES:
				if kind not in bans: continue
				var tower: Dictionary = s.towers.filter(func(t): return t.type=="")[0]
				var before: int = s.gold
				check(not s.command("build",{"id":tower.id,"type":kind}) and s.gold==before and tower.type=="",key+" forbidden build is atomic "+kind)
			check(not s.unlocked.fire and not s.unlocked.reinforcements,key+" preparation skills locked")
			check(s.command("wave") and s.unlocked.fire and s.unlocked.reinforcements,key+" first group unlocks skills")
			if mode==3: check(not s.command("wave"),key+" iron has only one wave")
			if representative: _clock(d,key)
			for kind: String in Sim.TYPES:
				var transaction=Sim.new(d,42);dismiss(transaction)
				if transaction.tower_locked("tower_build_"+kind):continue
				transaction.gold=2000
				var site: Dictionary=transaction.towers.filter(func(t):return t.type=="")[0]
				transaction.command("build",{"id":site.id,"type":kind})
				for i in range(25):transaction.step()
				var target: String=transaction.upgrade_target(site)
				if transaction.tower_locked(target):
					var before: Array=[transaction.gold,transaction.towers.duplicate(true)]
					check(not transaction.command("upgrade",{"id":site.id,"upgrade_to":target}) and before==[transaction.gold,transaction.towers],key+" forbidden upgrade is atomic "+kind)
				else:
					check(transaction.command("upgrade",{"id":site.id,"upgrade_to":target}),key+" source upgrade locks take precedence over technology cap "+kind)
			for i in range(3 if id==5 and mode==3 else 1):
				dismiss(s);s.command("wave");s._spawn_enemy("enemy_goblin",0,0)
				s.gold=1;s.cooldowns.fire=200;s.command("speed");s.command("pause")
				s.reset(42)
				check(s.gold==CASH[mode][id-1] and s.lives==1 and s.tick==0 and s.wave==0 and s.enemies.is_empty() and s.eggs.is_empty() and s.cooldowns.fire==0 and s.speed==1 and not s.paused and s.data.level.mode==mode,key+" dirty restart")
			timeline(Sim.new(d,42),key)
			if representative:
				var defeat = Sim.new(d,42);dismiss(defeat);defeat.command("wave")
				for i in range(12000):
					dismiss(defeat);defeat.step()
					if defeat.result!="": break
				check(defeat.result=="defeat" and defeat.lives==0 and defeat.leaks==1,key+" first leak loses")
			if id==5 and mode==3:
				var archers: Array=s.towers.filter(func(t):return t.template=="tower_archer_3")
				var archer_sites: Array=archers.map(func(t):return t.id)
				var camp_sites: Array=s.towers.filter(func(t):return t.template=="tower_elf_holder").map(func(t):return t.id)
				archer_sites.sort();camp_sites.sort()
				check(archer_sites==["1","3","4"] and camp_sites==["5","7"] and archers.all(func(t):return t.spent==0 and s.sell_refund(t)==0),key+" exact free archer/camp sites and zero refund")
				for site in ["5","7"]:
					check(s.command("upgrade",{"id":site,"upgrade_to":"tower_elf"}) and s.command("buy_soldier",{"id":site,"type":"soldier_elf"}),key+" camps unaffected by barrack ban "+site)
			report.modes[key]={"replay_available":FileAccess.file_exists(Playback.path_for(id,mode)),"replay_verified":null}
			if with_replays and report.modes[key].replay_available:
				var played := Playback.replay(id,mode)
				var win = played.sim
				var valid: bool = win.result=="victory" and win.lives==1 and win.leaks==0 and not win.developer_used and played.rejected.is_empty() and played.consumed
				check(valid,key+" existing recorded victory regression")
				report.modes[key].merge({"replay_verified":valid,"gold":win.gold,"ticks":win.tick,"spawned":win.spawn_log.size(),"kills":win.kills,"lives":win.lives},true)
	var unresolved=Sim.new(Levels.load_definition(1,3),42);dismiss(unresolved);unresolved.wave=1
	var final_enemy: Dictionary=unresolved._spawn_enemy("enemy_fat_orc",0,0);unresolved.step()
	check(unresolved.result=="" and final_enemy.hp>0,"last spawned enemy must be cleared before victory")
	unresolved.damage(final_enemy,final_enemy.hp,1);unresolved.step();check(unresolved.result=="victory","victory after final enemy is cleared")
	_progress()
	_locked_third_tier()
	var flag = preload("res://scripts/map/dove_map_flag.gd").new(true,42)
	flag.iron=true;flag.set_hovered(true);check(flag.frame()=="map_flag_0182","iron hover uses source frame")
	flag.set_hovered(false);check(flag.frame().begins_with("map_flag_016"),"iron idle uses source animation")
	report.passed=failures.is_empty();report.checks=checks;report.failures=failures
	var f:=FileAccess.open("res://reports/challenges_logic.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("CHALLENGES_LOGIC: ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func _clock(d: Dictionary, key: String) -> void:
	var normal=Sim.new(d,42);var fast=Sim.new(d,42);dismiss(normal);dismiss(fast)
	normal.command("wave");fast.command("wave");fast.command("speed")
	for i in range(120): normal.advance(1.0/30);fast.advance(1.0/60)
	var before: Array=[normal.tick,normal.enemies.duplicate(true),normal.cooldowns.duplicate(true)]
	normal.command("pause");normal.advance(2)
	check(before==[normal.tick,normal.enemies,normal.cooldowns],key+" pause freezes populated battle")
	normal.command("pause")
	check(not normal.enemies.is_empty() and normal.tick==fast.tick and normal.spawn_log==fast.spawn_log and normal.enemies==fast.enemies and normal.rng.state==fast.rng.state,key+" populated battle speed equivalence")

func _locked_third_tier() -> void:
	var s=Sim.new(Levels.load_definition(2,3),42);dismiss(s);s.gold=2000
	var site: Dictionary=s.towers.filter(func(t):return t.type=="")[0]
	s.command("build",{"id":site.id,"type":"archer"})
	for i in range(25):s.step()
	s.command("upgrade",{"id":site.id,"upgrade_to":"tower_archer_2"})
	for i in range(25):s.step()
	var before: Array=[s.gold,s.towers.duplicate(true)]
	check(s.tower_by_id(site.id).template=="tower_archer_2" and s.tower_locked("tower_archer_3") and not s.command("upgrade",{"id":site.id,"upgrade_to":"tower_archer_3"}) and before==[s.gold,s.towers],"second iron source tier-three archer ban is atomic")

func _progress() -> void:
	var path := "user://challenges_%d.json" % Time.get_ticks_usec()
	var p=Progress.new();p.initialize(path)
	for id in range(1,6):
		check(not p.is_playable(id,2),"three-star challenge gate")
		p.levels[id]={"stars":2,1:2};check(not p.is_playable(id,3),"two stars cannot enter iron")
		p.levels[id].stars=3
		for mode in [2,3]:
			check(p.is_playable(id,mode) and not p.is_playable(id,mode,3),"only normal challenge available")
			var outcome: Dictionary={"generation":1,"level_id":id,"mode":mode,"difficulty":2,"result":"victory","lives":1}
			var before: int=p.total_stars()
			p.record_result(outcome)
			if id==1:
				check(p.total_stars()==before and p.summary().stars==before+1,"pending challenge summary")
				var loaded=Progress.new();loaded.initialize(path)
				check(loaded.data.has("last_victory"),"pending result survives reload")
			var changes: Dictionary=p.enter_map()
			check(p.record(id)[mode]==2 and p.record(id).stars==3 and p.total_stars()==before+1 and changes["heroic" if mode==2 else "iron"]==[id] and changes.stars.is_empty(),"mode badge settlement preserves campaign stars and grants one star")
			if id==1:
				p.record_result(outcome);var again: Dictionary=p.enter_map()
				check(p.total_stars()==before+1 and again.heroic.is_empty() and again.iron.is_empty(),"repeated victory does not duplicate reward")
	check(p.total_stars()==25 and not p.is_playable(6,2),"fifteen completions total 25 stars and sixth remains preview")
	var prior: Dictionary=p.record(5).duplicate(true)
	p.record(5)[2]=3
	p.record_result({"generation":1,"level_id":5,"mode":2,"difficulty":2,"result":"victory","lives":1});p.enter_map()
	check(p.record(5)[2]==3,"lower difficulty retains highest score")
	p.record_result({"generation":1,"level_id":5,"mode":3,"difficulty":2,"result":"victory","lives":1})
	p.record_result({"result":"defeat"});check(not p.data.has("last_victory") and p.record(5)[3]==prior[3],"defeat clears pending result only")
	p.save();var restored=Progress.new();restored.initialize(path);check(restored.total_stars()==25 and restored.record(5)[2]==3,"challenge scores persist")
	for slot in [2,3]:
		var other=Progress.new();other.initialize(path+"_slot"+str(slot));check(other.total_stars()==0 and other.record(1).is_empty(),"independent slot untouched "+str(slot))
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
