extends SceneTree
const Fixture = preload("res://tests/slot_fixture.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Replay = preload("res://tests/level05_playback.gd")
var checks := 0
var failures: Array[String] = []
var campaign_report := {}
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func fresh():
	var s = Sim.new(Levels.load_definition(5),42)
	while not s.notices.is_empty(): s.command("confirm")
	return s
func reject(s, kind: String, args: Dictionary, label: String) -> void:
	var before := [s.gold,s.towers.duplicate(true),s.soldiers.duplicate(true),s.rng.state]
	check(not s.command(kind,args),label)
	check(before == [s.gold,s.towers,s.soldiers,s.rng.state],label + " atomic")
func steps(s, n: int) -> void:
	for i in range(n): s.step()
func camp(s) -> Dictionary:
	check(s.command("upgrade",{"id":"5","upgrade_to":"tower_elf"}),"repair camp")
	return s.tower_by_id("5")
func enemy(s, type: String = "enemy_brigand") -> Dictionary:
	var e: Dictionary = s._spawn_enemy(type,1,0)
	e.pos = Vector2(350,530); e.hp = 10000; e.max_hp = 10000
	return e
func transactions() -> void:
	var s = fresh()
	check(s.gold == 700 and s.lives == 20 and s.towers.size() == 14,"source initial state")
	check(s.tower_by_id("4").template == "tower_archer_3" and s.tower_by_id("4").spent == 0,"free preplaced tier three")
	check(s.sell_refund(s.tower_by_id("4")) == 0,"preplaced tower no invented investment")
	check(s.tower_by_id("5").template == "tower_elf_holder","elf ruins exist once")
	reject(s,"build",{"id":"5","type":"archer"},"cannot build regular tower on ruins")
	var a := {"id":"5","upgrade_to":"tower_elf"}
	s.gold = 189; reject(s,"upgrade",a,"repair insufficient")
	s.gold = 190; s.paused = true; reject(s,"upgrade",a,"repair paused"); s.paused = false
	var t := camp(s); check(s.gold == 0 and s.soldiers.is_empty() and t.hired == 0,"repair buys no soldiers")
	reject(s,"upgrade",a,"repair duplicate")
	a = {"id":"5","type":"soldier_elf"}
	s.gold = 99; reject(s,"buy_soldier",a,"recruit insufficient")
	s.gold = 400
	for n in range(4): check(s.command("buy_soldier",a) and t.hired == n+1,"purchase slot " + str(n))
	check(s.gold == 0 and t.spent == 190,"hiring excluded from refund")
	reject(s,"buy_soldier",a,"capacity during opening reserved")
	steps(s,45); check(s.soldiers.size() == 4,"four soldiers emerge")
	var destinations: Array = s.soldiers.map(func(u): return u.dest)
	check(destinations.all(func(p): return destinations.count(p) == 1),"four distinct formation positions")
	for p in ["bleed","cripple"]:
		for rank in range(1,4):
			var price: int = 100 if p == "bleed" else (200 if rank == 1 else 125)
			s.gold = price-1; reject(s,"upgrade_power",{"id":"5","power":p},p + " insufficient")
			s.gold = price; check(s.command("upgrade_power",{"id":"5","power":p}),p + " rank " + str(rank))
			check(s.soldiers.all(func(u): return u.powers[p] == rank),"existing soldiers inherit " + p)
		reject(s,"upgrade_power",{"id":"5","power":p},p + " maximum")
	check(t.spent == 940 and s.sell_refund(t) == 940,"skills count in refund")
	s.wave = 1; check(s.sell_refund(t) == 564,"combat refund excludes hires")
	var u: Dictionary = s.soldiers[0]; var dead: int = s.tick
	s.damage(u,1000,1); steps(s,419)
	check(s.soldiers.filter(func(v): return v.hp > 0).size() == 3,"no respawn before corpse expires")
	steps(s,45)
	check(s.soldiers.filter(func(v): return v.hp > 0).size() == 4 and s.gold == 0,"purchased slot respawns without payment")
	check(s.soldiers.filter(func(v): return v.hp > 0).all(func(v): return v.powers.bleed == 3 and v.powers.cripple == 3),"respawn inherits both skills")
	check(s.tick > dead + 420,"source corpse lifetime")
	check(s.command("sell",{"id":"5"}) and s.gold == 564,"sell camp")
	check(s.tower_by_id("5").template == "tower_holder_grass" and s.soldiers.all(func(v): return v.hp <= 0),"sell restores grass and retires units")
	reject(s,"buy_soldier",a,"sold camp cannot recruit")
	check(s.command("build",{"id":"5","type":"archer"}),"grass accepts normal construction")
	var s2 = fresh(); camp(s2); s2.gold = 100
	s2.notices.append("modal"); reject(s2,"buy_soldier",a,"recruit notification blocked"); s2.notices.clear()
	s2.paused = true; reject(s2,"buy_soldier",a,"recruit paused"); s2.paused = false
	reject(s2,"buy_soldier",{"id":"4","type":"soldier_elf"},"wrong tower")
	reject(s2,"buy_soldier",{"id":"5","type":"soldier_knight"},"wrong unit")
func modifiers() -> void:
	var s = fresh(); var e := enemy(s)
	check(s.modifiers.apply(s,"mod_elf_bleed",e,1,"elf"),"bleed applied")
	steps(s,1); check(e.hp == 9990,"bleed first tick true damage")
	check(not s.modifiers.apply(s,"mod_elf_bleed",e,1,"elf2") and s.modifiers.count(e.id,"mod_elf_bleed") == 1,"frozen singular allows_duplicate has no stacking effect")
	check(s.modifiers.apply(s,"mod_elf_bleed",e,3,"elf"),"higher bleed replaces lower")
	check(not s.modifiers.apply(s,"mod_elf_bleed",e,2,"elf"),"lower bleed rejected")
	check(s.modifiers.apply(s,"mod_elf_cripple",e,1,"elf"),"cripple applied")
	check(is_equal_approx(s.modifiers.speed(e.id,s),0.6),"cripple slow")
	check(s.modifiers.apply(s,"mod_ranger_poison",e,1,"ranger"),"poison combines with elf states")
	check(is_equal_approx(s.modifiers.speed(e.id,s),0.54),"multiplicative slow")
	steps(s,76); check(is_equal_approx(s.modifiers.speed(e.id,s),0.9),"cripple expires independently")
	s.damage(e,100000,1); steps(s,1); check(s.modifiers.active.is_empty(),"death cleans all modifiers")
func combat() -> void:
	var s = fresh(); var t := camp(s); s.gold = 100
	s.command("buy_soldier",{"id":"5","type":"soldier_elf"}); steps(s,80)
	var u: Dictionary = s.soldiers[0]
	var e := enemy(s); e.pos = u.pos + Vector2(100,0)
	u.rallying = false; u.ranged_at = s.tick; s._soldier_step(u)
	check(u.pending.get("ranged",false),"elf acquires ranged target")
	var started: int = s.tick; s.tick += 7; s._soldier_step(u)
	check(s.projectiles.size() == 1 and s.projectiles[0].template == "arrow_elf","arrow after seven tick windup")
	var p: Dictionary = s.projectiles[0]; e.pos += Vector2(100,0); s.tick += p.duration; s._bullet_step(p)
	check(e.hp < 10000,"elf arrow tracks source reset position")
	u.pending = {}; u.ranged_at = s.tick+1000; u.rallying = false
	u.pos = s.melee_slot(u,e); u.target = e.id; e.blocker = u.id; e.blockers = [u.id]; u.attack_at = s.tick
	u.powers.bleed = 1; s._melee(u,e,s.templates.soldier_elf)
	check(not u.pending.has("dodge_at"),"elf melee bypasses bandit dodge")
	s.tick += 5; s._melee(u,e,s.templates.soldier_elf)
	check(s.modifiers.has(e.id,"mod_elf_bleed"),"melee applies bleed")
	u.pending = {}; u.ranged_at = s.tick; var swing_end: int = u.state_at+s.SpriteAnimation.duration(s.animations,s.SpriteAnimation.key(s.templates.soldier_elf.render.sprites[0],"attack"))
	s._soldier_step(u); check(u.pending.is_empty(),"melee animation completes before switching to ranged")
	s.tick = swing_end; s._soldier_step(u)
	check(u.pending.get("ranged",false) and e.blockers.has(u.id),"elf may shoot while retaining blocker")
	u.powers.bleed = 3; s.tick += 7; s._soldier_step(u)
	check(s.projectiles[-1].bleed_level == 3,"skill purchase during windup inherited at launch")
	check(started >= 0,"combat fixture advanced")
	# Fired projectiles and their levels outlive the source camp and its soldiers.
	for rank in range(1,4):
		var shot = fresh(); var home := camp(shot); shot.gold = 1000
		var victim := enemy(shot,"enemy_wolf"); victim.pos = Vector2(440,540)
		shot._projectile("arrow_elf_cripple",victim.id,Vector2(350,540),victim.pos + Sim.vec(shot.templates[victim.template].unit.hit_offset),8.0/30)
		var arrow: Dictionary = shot.projectiles[-1]; arrow.elf_level = rank; arrow.bleed_level = 0; arrow.source = "retired"
		shot.modifiers.apply(shot,"mod_elf_bleed",victim,rank,"retired")
		shot.command("sell",{"id":"5"})
		for i in range(180):
			shot.tick += 1; shot._bullet_step(arrow)
			if arrow.done: break
		check(arrow.done and victim.hp == 10000 - (55+15*rank),"cripple true no-dodge damage after sale rank " + str(rank))
		check(shot.modifiers.has(victim.id,"mod_elf_cripple"),"launched arrow retains cripple rank " + str(rank))
		shot.tick += 1; shot.modifiers.step(shot)
		check(victim.hp == 10000-(55+15*rank)-(5+5*rank),"applied bleed survives camp sale rank " + str(rank))
	var missile = fresh(); var first := enemy(missile); first.pos = Vector2(430,540)
	var second := enemy(missile); second.pos = Vector2(470,540)
	missile._projectile("arrow_elf_cripple",first.id,Vector2(350,540),first.pos,8.0/30)
	var seeking: Dictionary = missile.projectiles[-1]; seeking.elf_level = 1; seeking.bleed_level = 0; seeking.source = "elf"
	missile.damage(first,100000,1)
	for i in range(240):
		missile.tick += 1; missile._bullet_step(seeking)
		if seeking.done: break
	check(seeking.done and seeking.target == second.id and second.hp == 9930,"missile retargets after original target dies")
	check(not missile.effects.is_empty(),"missile emits source particle trail")
func spiders() -> void:
	var s = fresh(); var e := enemy(s,"enemy_spider_big")
	var period: int = e.egg_period
	check(period >= 150 and period <= 300,"random initial five to ten second egg period")
	s.tick = e.egg_at; s.Spider.lay(s,e); check(s.eggs.is_empty(),"strict cooldown boundary")
	s.tick += 1; s.Spider.lay(s,e); check(s.eggs.size() == 1,"mother lays egg")
	var egg: Dictionary = s.eggs[0]; var start: int = egg.next
	s.damage(e,100000,1)
	for offset in [0,6,12]: s.tick = start+offset; s.Spider.step(s)
	var babies: Array = s.enemies.filter(func(v): return v.template == "enemy_spider_tiny")
	check(babies.size() == 3 and babies.map(func(v): return v.subpath) == [0,1,2],"egg survives mother and cycles three subpaths")
	check(s.spawn_log.filter(func(v): return v.origin == "egg").size() == 3 and s.spawn_queue.is_empty(),"egg log independent of waves")
	var before: int = s.gold
	for baby: Dictionary in babies: s.damage(baby,100000,1)
	check(s.gold == before,"hatched spiders yield zero gold")
	var other := enemy(s,"enemy_spider_big"); other.blocker = 999; s.tick = other.egg_at+1; s.Spider.lay(s,other)
	check(other.eggs_laid == 0,"blocked mother cannot lay")
	other.blocker = 0
	for i in range(5): s.tick = other.egg_at+1; s.Spider.lay(s,other)
	check(other.eggs_laid == 3,"normal difficulty three egg limit")
	s.reset(42); check(s.eggs.is_empty() and s.spawn_log.is_empty() and s.modifiers.active.is_empty(),"restart clears spawners and statuses")
func roster() -> void:
	var s = fresh()
	for spec: Array in [["enemy_wolf",198,0.0,0.5,1],["enemy_spider_tiny",16,0.0,0.5,1],["enemy_spider_small",99,0.0,0.65,1],["enemy_spider_big",412,0.0,0.8,2],["enemy_marauder",990,0.6,0.0,3]]:
		var e: Dictionary = s._spawn_enemy(spec[0],0,0)
		check(e.hp == spec[1],"normal difficulty source health " + spec[0])
		check(is_equal_approx(s.damage(e,10,2),10*(1-spec[2])) and is_equal_approx(s.damage(e,10,4),10*(1-spec[3])),"source physical/magic protection " + spec[0])
		var route: Array = s.data.paths.paths[0][0]; e.node = route.size()-1; e.pos = Sim.vec(route[-1]); var lives: int = s.lives
		s._enemy_step(e); s._enemy_step(e)
		check(s.lives == lives-int(spec[4]),"source lives charged once " + spec[0])
	check(s.templates.enemy_wolf.dodge.chance == 0.5,"wolf source melee dodge chance")
func progress() -> void:
	var path := "user://level05_test_%d.json" % Time.get_ticks_usec()
	var p := Progress.new(); p.initialize(path)
	for id in range(1,5): Fixture.complete(p, {"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	var old := Progress.new(); old.initialize(path)
	check(old.total_stars() == 12 and old.is_playable(5),"settled fourth-stage slot opens fifth")
	Fixture.complete(p, {"generation":1,"level_id":5,"mode":1,"difficulty":2,"result":"victory","lives":20})
	old.initialize(path); check(old.total_stars() == 15 and old.is_unlocked(6) and not old.is_playable(6),"fifth persists and sixth preview")
	Fixture.complete(p, {"generation":1,"level_id":5,"mode":1,"difficulty":2,"result":"victory","lives":1})
	old.initialize(path); check(old.record(5).stars == 3,"fifth lower replay preserves best stars")
	check(not Levels.supports(5,2) and not Levels.supports(5,3),"challenge modes unavailable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
func campaign() -> void:
	var s = Sim.new(Levels.load_definition(5),42)
	for i in range(60000):
		Replay.commands(s); s.step()
		if s.result != "": break
	check(s.result == "victory" and not s.developer_used and Replay.failures.is_empty(),"legal normal-economy campaign replay")
	check(s.lives == int(Replay.outcome.lives) and s.tick == int(Replay.outcome.tick) and s.gold == int(Replay.outcome.gold) and s.spawn_log.size() == int(Replay.outcome.spawned),"recorded campaign outcome reproduced")
	check(s.spawn_log.filter(func(v): return v.origin == "wave").size() == 242,"all 242 wave enemies spawned")
	check(s.spawn_log.filter(func(v): return v.origin == "egg").size() > 0,"campaign contains real hatched spiders")
	campaign_report = {"result":s.result,"lives":s.lives,"tick":s.tick,"gold":s.gold,"wave_enemies":s.spawn_log.filter(func(v): return v.origin == "wave").size(),"hatched":s.spawn_log.filter(func(v): return v.origin == "egg").size(),"kills":s.kills,"leaks":s.leaks}
	for i in range(3):
		s.reset(42); check(s.gold == 700 and s.lives == 20 and s.towers.size() == 14 and s.eggs.is_empty() and s.soldiers.is_empty() and s.cooldowns.fire == 0,"campaign restart " + str(i))
	while not s.notices.is_empty(): s.command("confirm")
	s.command("wave")
	for i in range(20000):
		while not s.notices.is_empty(): s.command("confirm")
		s.step()
		if s.result != "": break
	check(s.result == "defeat" and s.lives == 0,"no purchases or powers loses despite preplaced archer")
	campaign_report.defeat_tick = s.tick
	var a = fresh(); var b = fresh(); a.command("wave"); b.command("wave"); b.command("speed")
	a.command("pause"); a.advance(1); check(a.tick == 0,"pause freezes fifth")
	a.command("pause")
	for i in range(200): a.advance(1.0/30); b.advance(1.0/60)
	check(a.tick == b.tick and a.spawn_log == b.spawn_log and a.rng.state == b.rng.state,"speed preserves fifth state")
func timeline() -> void:
	var s = fresh(); var counts := {}
	for group: Dictionary in s.data.waves.groups:
		check(s.command("wave"),"manual fifth wave accepted")
		while not s.notices.is_empty(): s.command("confirm")
		var expected: Array = []
		for wave: Dictionary in group.waves:
			var at: int = s.tick + int(wave.delay)
			for index in wave.spawns.size():
				var spawn: Dictionary = wave.spawns[index]
				for n in int(spawn.max):
					at += int(spawn.interval)
					var type: String = spawn.creep
					if spawn.has("creep_aux") and int(spawn.max_same)>0 and floori(float(n)/int(spawn.max_same))%2 == 1: type = spawn.creep_aux
					expected.append({"tick":at,"type":type,"path":int(wave.path_index)-1,"subpath":int(spawn.path)-1 if int(spawn.fixed_sub_path)==1 else -1,"order":expected.size()})
				if int(spawn.max)==0: at += int(spawn.interval)
				if index+1 < wave.spawns.size(): at += int(spawn.interval_next)
		expected.sort_custom(func(a,b): return a.tick < b.tick if a.tick != b.tick else a.order < b.order)
		var offset: int = s.spawn_log.size()
		while not s.spawn_queue.is_empty():
			s.enemies.clear(); s.eggs.clear(); s.step()
		var actual: Array = s.spawn_log.slice(offset)
		check(actual.size() == expected.size(),"fifth wave source count")
		for i in expected.size():
			var a: Dictionary = actual[i]; var e: Dictionary = expected[i]
			check(a.tick == e.tick and a.type == e.type and a.path == e.path and a.origin == "wave" and a.subpath >= 0 and a.subpath < 3 and (e.subpath < 0 or a.subpath == e.subpath),"fifth ordered birth tick/type/path/subpath")
			counts[a.type] = int(counts.get(a.type,0))+1
		s.enemies.clear(); s.eggs.clear()
	check(counts == {"enemy_brigand":39,"enemy_bandit":59,"enemy_spider_small":35,"enemy_wolf_small":55,"enemy_wolf":32,"enemy_spider_big":19,"enemy_marauder":3},"exact fifth wave roster")
func settlement() -> void:
	var s = fresh(); var mother := enemy(s,"enemy_spider_big")
	s.tick = mother.egg_at+1; s.Spider.lay(s,mother)
	var at: int = s.eggs[0].next
	s.command("pause"); var tick: int = s.tick; s.advance(20)
	check(s.tick == tick and s.eggs[0].next == at and s.eggs[0].spawned == 0,"pause freezes pending hatches")
	s.command("pause"); s.enemies.clear(); s.wave = 15; s.step()
	check(s.result == "victory" and s.eggs.size() == 1,"source victory ignores unhatched eggs without enemies")
	var result_tick: int = s.tick; s.advance(20)
	check(s.tick == result_tick and s.spawn_log.size() == 1,"result prevents new hatches")
	var due = fresh(); var parent := enemy(due,"enemy_spider_big")
	due.tick = parent.egg_at+1; due.Spider.lay(due,parent); due.enemies.clear()
	due.tick = due.eggs[0].next-1; due.wave = 15; due.step()
	check(due.result == "" and due.enemies.size() == 1,"same-tick pending hatch counts before settlement")
func run() -> void:
	transactions(); modifiers(); combat(); spiders(); roster(); progress(); timeline(); settlement(); campaign()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"campaign":campaign_report}
	var f := FileAccess.open("res://reports/level05_logic.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("LEVEL05_LOGIC: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
