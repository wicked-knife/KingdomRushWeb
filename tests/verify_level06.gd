extends SceneTree
## Source data/timelines and bounded mechanism scenarios. No victory search.
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const UnitInfo = preload("res://scripts/battle/dove_unit_info.gd")
const Progress = preload("res://scripts/services/campaign_progress.gd")
var failures: Array[String] = []
var checks := 0
var timeline_report := {}
var births := 0
var source: Dictionary
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func fresh(mode: int = 1):
	var data := Levels.load_definition(6, mode)
	check(not data.is_empty(), "sixth definition loads %d: %s" % [mode, Levels.last_error])
	var sim = Sim.new(data, 42)
	sim.notices.clear()
	return sim
func dismiss(sim) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")
func ticks(sim, count: int) -> void:
	for index in count: dismiss(sim); sim.step()
func run() -> void:
	source = Levels.read_json("res://tests/fixtures/level06_source.json")
	check(not source.is_empty(), "independent frozen-source oracle exists")
	check(Levels.supports(6, 3) and not Levels.supports(8) and not Levels.supports(6, 1, 3), "published range and difficulty")
	for mode in [1, 2, 3]:
		var sim = fresh(mode)
		check(sim.data.waves == source.modes[str(mode)], "all wave fields match frozen Lua mode %d" % mode)
		var expected_layout: Dictionary = source.layout.duplicate(true)
		expected_layout.entities_list = expected_layout.entities_list.filter(func(e): return int(e.get("editor.game_mode", 0)) in [0, mode])
		var actual_layout: Dictionary = sim.data.layout.duplicate(true)
		for entity: Dictionary in actual_layout.entities_list: entity.template = str(entity.template).split("__")[0]
		check(equivalent(actual_layout, expected_layout), "complete layout, restrictions, rally points and notifications source mode %d" % mode)
		check(sim.gold == [700, 1200, 800][mode - 1] and sim.lives == (20 if mode == 1 else 1), "mode economy %d" % mode)
		check(sim.data.waves.groups.size() == [17, 6, 1][mode - 1], "mode waves %d" % mode)
		check(sim.towers.size() == 15 and sim.soldiers.size() == (0 if mode == 3 else 7), "source placements %d" % mode)
		check(not sim.valid_power_point("reinforcements",Vector2(100,100)) and sim.valid_power_point("reinforcements",sim.towers[0].rally),"sixth road and off-road placement %d" % mode)
		check(not sim.tower_locked("tower_paladin") and not sim.tower_locked("tower_arcane_wizard"), "new towers unlocked in-level %d" % mode)
		if mode == 3:
			check(sim.towers.filter(func(t): return t.template == "tower_mage_3" and t.spent == 0).size() == 2, "steel free mages")
			for kind in Sim.TYPES: check(sim.tower_locked("tower_build_" + kind) == (kind != "barrack"), "steel build ban " + kind)
		timeline(mode)
	targets_and_units()
	towers_and_skills()
	source_attacks()
	boss_and_payloads()
	progression()
	var report = {"passed": failures.is_empty(), "checks": checks, "independent_modes": 3, "timeline_waves": 24, "births": births, "timeline_report": "reports/level06_timelines.json", "failures": failures, "full_replays": false}
	var output = FileAccess.open("res://reports/level06_logic.json", FileAccess.WRITE); output.store_string(JSON.stringify(report, "\t")); output.close()
	output = FileAccess.open("res://reports/level06_timelines.json", FileAccess.WRITE); output.store_string(JSON.stringify(timeline_report)); output.close()
	print("LEVEL06: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " checks=", checks, " births=", births)
	quit(0 if failures.is_empty() else 1)
func equivalent(a, b) -> bool:
	# Lua empty tables have no array/object distinction.
	if (a is Dictionary or a is Array) and (b is Dictionary or b is Array):
		if a.is_empty() and b.is_empty(): return true
		if typeof(a) != typeof(b) or a.size() != b.size(): return false
		if a is Dictionary:
			for key in a:
				if not b.has(key) or not equivalent(a[key], b[key]): return false
		else:
			for i in a.size():
				if not equivalent(a[i], b[i]): return false
		return true
	return a == b
func timeline(mode: int) -> void:
	var sim = fresh(mode); sim.towers.clear(); sim.soldiers.clear()
	var report: Array = []
	for group_index in source.timelines[str(mode)].size():
		var start: int = sim.tick
		var offset: int = sim.spawn_log.size()
		check(sim.command("wave"), "timeline starts %d/%d" % [mode, group_index + 1])
		while not sim.spawn_queue.is_empty(): sim.enemies.clear(); sim.spawners.clear(); sim.pending_entities.clear(); ticks(sim, 1)
		var actual: Array = []
		var expected: Array = source.timelines[str(mode)][group_index]
		for entry: Dictionary in sim.spawn_log.slice(offset): actual.append([entry.tick - start, entry.type, entry.path, entry.subpath])
		var difference = -1
		for i in maxi(actual.size(), expected.size()):
			if i >= actual.size() or i >= expected.size(): difference = i; break
			var normalized: Array = actual[i].duplicate()
			if expected[i][3] == -1 and actual[i][3] >= 0 and actual[i][3] < 3: normalized[3] = -1
			for column in 4:
				if normalized[column] != expected[i][column]: difference = i; break
			if difference != -1: break
		check(difference == -1, "source full birth timeline %d/%d first difference %d" % [mode, group_index + 1, difference])
		births += actual.size(); report.append({"wave": group_index + 1, "expected": expected, "actual": actual, "first_difference": difference})
		sim.enemies.clear(); sim.spawners.clear(); sim.pending_entities.clear()
	timeline_report[str(mode)] = report
func targets_and_units() -> void:
	var sim = fresh(); sim.soldiers.clear()
	var guard: Dictionary = sim._soldier("soldier_s6_imperial_guard", "", 0, Vector2(500, 400), Vector2(500, 400)); guard.rallying = false
	var flying: Dictionary = sim._spawn_enemy("enemy_gargoyle", 0)
	flying.pos = guard.pos; flying.progress = 50
	check(sim._soldier_target(guard).is_empty(), "flying cannot be blocked")
	check(sim._target(guard.pos, 200, false, sim.templates.tower_engineer_3.attacks.list[0]).is_empty(), "artillery cannot aim at flying")
	check(not sim._target(guard.pos, 200, false, sim.templates.tower_archer_3.attacks.list[0]).is_empty(), "archer can aim at flying")
	check(UnitInfo.snapshot(flying, sim.templates, sim.data.ui.strings).damage_min == 0, "passive flying information has no melee dependency")
	sim.enemies.clear()
	var archer: Dictionary = sim._spawn_enemy("enemy_shadow_archer", 0)
	archer.pos = guard.pos + Vector2(-90, 0); sim.tick = 43
	sim._enemy_step(archer)
	check(not archer.get("ranged_cast", {}).is_empty() and archer.state == "shoot", "ranged enemy holds advance and starts shooting")
	var pos: Vector2 = archer.pos
	sim.tick += 7; sim._enemy_step(archer)
	check(sim.projectiles.size() == 1 and archer.pos == pos, "source seven-frame ranged windup")
	if not sim.projectiles.is_empty():
		var arrow: Dictionary = sim.projectiles[0]; arrow.to = guard.pos + sim.vec(sim.templates[guard.template].unit.hit_offset)
		var before: float = guard.hp; sim.tick = int(arrow.at) + int(arrow.duration); sim._bullet_step(arrow)
		check(guard.hp < before and archer.hp == archer.max_hp, "enemy arrow damages friendly side only")
	sim.damage(guard, 9999, 1); ticks(sim, 100)
	check(sim.soldiers.is_empty(), "standalone guard corpse expires with no respawn")
	var s = fresh(); s.soldiers.clear()
	guard = s._soldier("soldier_s6_imperial_guard", "", 0, Vector2(500,400), Vector2(500,400))
	archer = s._spawn_enemy("enemy_shadow_archer", 0); archer.pos = guard.pos - Vector2(90,0); s.tick = 43
	s._enemy_step(archer); s.damage(guard,9999,1); s.tick += 7; s._enemy_step(archer)
	check(s.projectiles.size() == 1 and s.projectiles[0].target == guard.id, "ranged windup retains dead target until arrow impact")
func buy(sim, kind: String, id: String, target: String) -> Dictionary:
	sim.gold = 10000
	check(sim.command("build", {"id": id, "type": kind}), "build " + kind)
	ticks(sim, 30)
	for next in ["tower_" + kind + "_2", "tower_" + kind + "_3", target]: check(sim.command("upgrade", {"id": id, "upgrade_to": next}), "upgrade " + next)
	return sim.tower_by_id(id)
func towers_and_skills() -> void:
	var sim = fresh(); sim.soldiers.clear()
	var paladin: Dictionary = buy(sim, "barrack", "1", "tower_paladin")
	for power in ["healing", "holystrike", "shield"]:
		for level in int(sim.tower_template(paladin).powers[power].max_level): check(sim.command("upgrade_power", {"id": "1", "power": power}), "paladin power " + power)
		check(not sim.command("upgrade_power", {"id": "1", "power": power}), "power maximum " + power)
	ticks(sim, 90)
	var soldiers: Array = sim.soldiers.filter(func(s): return s.home == "1" and s.hp > 0)
	check(soldiers.size() == 3, "paladin three-man garrison")
	if not soldiers.is_empty():
		var soldier: Dictionary = soldiers[0]
		check(is_equal_approx(soldier.armor, 0.6) and is_equal_approx(soldier.magic_armor, 0.6), "shield inherited on spawned garrison")
		sim.modifiers.active.append({"template":"mod_ranger_poison", "target":soldier.id, "level":1})
		soldier.rallying = false; soldier.hp = 170; sim.tick = 400
		Sim.Behaviors.Paladin.step(sim, soldier, sim.templates.soldier_paladin)
		check(soldier.state == "healing", "source health threshold starts healing")
		sim.tick += 16; Sim.Behaviors.Paladin.step(sim, soldier, sim.templates.soldier_paladin); check(soldier.hp == 170, "healing waits seventeen frames")
		sim.tick += 1; Sim.Behaviors.Paladin.step(sim, soldier, sim.templates.soldier_paladin)
		check(soldier.hp >= 302 and soldier.hp <= 368, "source level-three healing allows overflow")
		check(not sim.modifiers.has(soldier.id,"mod_ranger_poison"), "healing cleanses source banned poison type")
		var victim: Dictionary = sim._spawn_enemy("enemy_shaman",0); victim.pos = soldier.pos + Vector2(22,0)
		sim.templates.soldier_paladin.melee.attacks[2].chance = 1.0; sim.templates.soldier_paladin.melee.attacks[2].chance_inc = 0
		soldier.pending = {}; soldier.melee_end = 0; sim.tick += 100
		Sim.Behaviors.Paladin.melee(sim,soldier,victim,sim.templates.soldier_paladin)
		check(soldier.state == "holystrike", "controlled holystrike chance selects source area attack")
		var hp: float = victim.hp; sim.tick += 15; Sim.Behaviors.Paladin.melee(sim,soldier,victim,sim.templates.soldier_paladin)
		var protection: float = 0.85 * (0.2 * 0.85 + 0.4)
		check(hp - victim.hp >= 50 * (1 - protection) and hp - victim.hp <= 80 * (1 - protection) and victim.get("silence_count",0) == 1, "holystrike level-three magical explosion protection and silence")
		soldier.stun_count = 1; soldier.healing_cast = {"at":sim.tick}; sim._soldier_step(soldier)
		check(soldier.pending.is_empty() and soldier.healing_cast.is_empty() and soldier.state == "idle", "stun interrupts new soldier attacks and timed action")
		soldier.stun_count = 0
		soldier.pending={}; soldier.melee_end=0; soldier.healing_cast={}; soldier.hp=soldier.max_hp; sim.tick+=100
		var doomed: Dictionary=sim._spawn_enemy("enemy_goblin",0); doomed.pos=soldier.pos+Vector2(22,0)
		var bystander: Dictionary=sim._spawn_enemy("enemy_marauder",0); bystander.pos=doomed.pos
		doomed.blockers=[soldier.id]; doomed.blocker=soldier.id; soldier.target=doomed.id
		Sim.Behaviors.Paladin.melee(sim,soldier,doomed,sim.templates.soldier_paladin)
		sim.damage(doomed,99999,1); var hp_before: float=bystander.hp
		sim.tick+=15; sim._soldier_step(soldier)
		check(bystander.hp<hp_before and bystander.get("silence_count",0)==1,"holystrike continues area hit after original target dies during windup")
	var arcane: Dictionary = buy(sim, "mage", "2", "tower_arcane_wizard")
	for power in ["disintegrate", "teleport"]:
		for level in 3: check(sim.command("upgrade_power", {"id": "2", "power": power}), "arcane power " + power)
	var enemy: Dictionary = sim._spawn_enemy("enemy_dark_knight", 0)
	enemy.pos = arcane.pos + Vector2(30, 0); enemy.node = 50
	check(sim.modifiers.apply(sim, "mod_ray_arcane", enemy, 1, "2"), "arcane beam modifier applies")
	check(sim.modifiers.apply(sim,"mod_ray_arcane",enemy,1,"other") and sim.modifiers.count(enemy.id,"mod_ray_arcane")==2,"source ordinary beams allow multi-tower duplicates")
	sim.modifiers.active.pop_back() # The following single-beam sample isolates total damage.
	var before: float = enemy.hp
	for index in 12: sim.tick += 1; sim.modifiers.step(sim)
	check(before - enemy.hp >= 92 and before - enemy.hp <= 156, "arcane total source magical ray damage ignores physical armor")
	enemy.hp = 300
	check(sim.modifiers.apply(sim, "mod_ray_arcane_disintegrate", enemy, 3, "2"), "death ray applies")
	for index in 5: sim.tick += 1; sim.modifiers.step(sim)
	check(enemy.hp == 0, "death ray ordinary target dies after source delay")
	check(enemy.get("hidden",false) and sim.effects.any(func(e):return e.template.begins_with("fx_")), "death ray hides corpse and creates source disintegration effect")
	var boss: Dictionary = sim._spawn_enemy("eb_juggernaut", 0)
	var boss_hp: float = boss.hp
	sim.modifiers.apply(sim, "mod_ray_arcane_disintegrate", boss, 3, "2")
	for index in 5: sim.tick += 1; sim.modifiers.step(sim)
	check(is_equal_approx(boss_hp - boss.hp, 642 + boss.max_hp * 0.047), "death ray source boss damage formula")
	check(not sim.modifiers.apply(sim, "mod_teleport_arcane", boss, 3, "2"), "boss teleport immunity")
	enemy = sim._spawn_enemy("enemy_marauder", 0); enemy.node = 80; enemy.pos = sim.vec(sim.data.paths.paths[0][0][80])
	for level in 3:
		check(sim.modifiers.apply(sim, "mod_teleport_arcane", enemy, 1, "2"), "teleport allowed count %d" % level)
		var teleported_hp: float = enemy.hp
		check(not sim.modifiers.apply(sim,"mod_teleport_arcane",enemy,1,"2") and enemy.hp == teleported_hp and enemy.teleport_count == level + 1,"active teleport duplicate does not consume count or damage")
		for index in 16: sim.tick += 1; sim.modifiers.step(sim)
		check(not enemy.get("hidden", false) and enemy.get("stun_count", 0) == 0, "teleport restores visibility and stun")
	check(enemy.node < 80 and not sim.modifiers.apply(sim, "mod_teleport_arcane", enemy, 1, "2"), "teleport moves backwards and stops after three applications")
	var reset = fresh()
	check(reset.templates.soldier_paladin.health.armor == 0.45 and not reset.tower_by_id("1").has("powers"), "new battle has unmodified templates and no powers")
func boss_and_payloads() -> void:
	var sim = fresh(); sim.towers.clear(); sim.soldiers.clear()
	var boss: Dictionary = sim._spawn_enemy("eb_juggernaut", 0, 4)
	boss.pos = Vector2(500, 400); sim.tick = 120; sim._enemy_step(boss)
	check(not boss.boss.casting.is_empty() and boss.boss.casting.index == 1, "boss four-second bomb cooldown")
	sim.damage(boss, 99999, 1)
	sim.tick += 24; sim._enemy_step(boss)
	check(not sim.projectiles.is_empty(), "lethal hit during unconditional windup preserves source shot")
	sim.tick += 120; sim._enemy_step(boss)
	check(boss.boss.death_handled, "boss death callback runs once after cast")
	var gold: int = sim.gold
	var other: Dictionary = sim._spawn_enemy("enemy_dark_knight", 0)
	sim.pending_entities.append({"kind":"enemy", "template":"enemy_golem_head"})
	sim.controller.enemy_died(sim, boss)
	check(other.hp == 0 and sim.gold == gold and sim.pending_entities.is_empty(), "source clear removes pending enemies without bonus gold")
	var s = fresh(); s.towers.clear(); s.soldiers.clear()
	var owner: Dictionary = s._spawn_enemy("eb_juggernaut", 0)
	var pos: Vector2 = s.vec(s.data.paths.paths[0][0][60])
	Sim.Behaviors.Spawner.insert(s, {"template":"juggernaut_bomb_spawner", "pos":pos, "owner":owner.id, "level":7})
	check(s.spawners[0].count == 12, "source bomb level seven count is twelve")
	Sim.Behaviors.Spawner.step(s)
	check(s.pending_entities.size() == 1 and s.enemies.size() == 1, "summons wait for pending insertion boundary")
	Sim.Behaviors.Spawner.flush(s)
	check(s.enemies.size() == 2 and s.enemies[1].gold_override == 7, "source summon gold override")
	s.damage(owner, 99999, 1); s.tick += 6; Sim.Behaviors.Spawner.step(s)
	check(s.pending_entities.is_empty(), "owner death stops remaining summons")
	var edge = fresh(); edge.towers.clear(); edge.soldiers.clear()
	var eb: Dictionary = edge._spawn_enemy("eb_juggernaut",0)
	Sim.Behaviors.Spawner.insert(edge,{"template":"juggernaut_bomb_spawner","pos":pos,"owner":eb.id,"level":0})
	Sim.Behaviors.Spawner.step(edge)
	edge._projectile("bomb_juggernaut",0,eb.pos,pos,1); edge.projectiles[-1].owner = eb.id
	var cash: int = edge.gold; edge.damage(eb,99999,1); edge._enemy_step(eb)
	check(edge.pending_entities.is_empty() and edge.gold - cash == 250,"same-frame pending summon cleared; only boss reward paid")
	var bomb: Dictionary = edge.projectiles[-1]; edge.tick = bomb.at + bomb.duration; edge._bullet_step(bomb)
	Sim.Behaviors.Spawner.flush(edge); Sim.Behaviors.Spawner.step(edge); Sim.Behaviors.Spawner.flush(edge)
	check(edge.enemies.all(func(e):return e.hp <= 0) and edge.pending_entities.is_empty(), "bomb in flight at boss death cannot generate living summons")
	edge.projectiles.clear() # The normal frame removes a completed projectile.
	edge.wave = 17; edge.spawn_queue.clear(); edge.step()
	check(edge.result == "victory", "boss clear victory does not wait for corpse lifetime")
	var leaked = fresh(); leaked.towers.clear(); leaked.soldiers.clear(); leaked.wave = 17
	var escaping: Dictionary = leaked._spawn_enemy("eb_juggernaut",0)
	escaping.progress = leaked.data.paths.paths[0][0].size() - 1; escaping.node = int(escaping.progress)
	leaked.step()
	check(leaked.result == "defeat" and leaked.lives <= 0,"boss leak costs twenty lives and loss takes priority")
	s.wave = 17; s.spawn_queue.clear(); s.enemies.clear()
	s.pending_entities.append({"kind":"enemy"})
	check(not s.controller.can_finish(s), "pending enemy blocks victory")
	s.pending_entities.clear(); s.lives = 0; s.step()
	check(s.result == "defeat", "zero lives wins over victory boundary")

func source_attacks() -> void:
	for death_at in [-1,6]:
		var s = fresh(); s.towers.clear(); s.soldiers.clear()
		var owner: Dictionary = s._spawn_enemy("eb_juggernaut",0)
		Sim.Behaviors.Spawner.insert(s,{"template":"juggernaut_bomb_spawner","pos":s.vec(s.data.paths.paths[0][0][60]),"owner":owner.id,"level":7})
		var actual: Array = []
		for frame in 91:
			s.tick=frame
			if frame==death_at: s.damage(owner,99999,1)
			Sim.Behaviors.Spawner.step(s)
			for item: Dictionary in s.pending_entities: actual.append([frame,item.template,item.path,item.subpath,item.node,item.gold])
			s.pending_entities.clear()
		check(equivalent(actual,source.spawners[str(death_at)]),"original Lua complete summon timeline owner death=%d" % death_at)
	for hp in [50, 1000]:
		var sim = fresh(); sim.soldiers.clear(); sim.towers.clear()
		var enemy: Dictionary = sim._spawn_enemy("enemy_marauder", 0)
		enemy.hp = hp; enemy.max_hp = hp; enemy.magic_armor = 0
		sim.templates.mod_ray_arcane.dps.damage_min = 101; sim.templates.mod_ray_arcane.dps.damage_max = 101
		sim.modifiers.apply(sim, "mod_ray_arcane", enemy, 1, "source-oracle")
		var actual: Array = []
		for tick in range(1, 21):
			sim.tick = tick
			var before: float = enemy.hp
			var had: bool = not sim.modifiers.active.is_empty()
			sim.modifiers.step(sim)
			if enemy.hp != before or had and sim.modifiers.active.is_empty() and enemy.hp > 0: actual.append([tick, before - enemy.hp])
		var expected: Array = source.rays[str(hp)]
		var same: bool = actual.size() == expected.size()
		for i in mini(actual.size(), expected.size()):
			same = same and actual[i][0] == expected[i][0] and actual[i][1] == expected[i][1]
		check(same, "original Lua ray full pulse list hp=%d: %s" % [hp, actual])
	var sim = fresh(); sim.soldiers.clear(); sim.towers.clear()
	for pos in [Vector2(300,350), Vector2(180,260)]:
		var unit: Dictionary = sim._soldier("soldier_s6_imperial_guard", "", 0, pos, pos)
		unit.hp = 1000; unit.max_hp = 1000; unit.armor = 0
	sim._projectile("missile_juggernaut", sim.soldiers[0].id, Vector2(100,100), Vector2(112,270), 1)
	var p: Dictionary = sim.projectiles[0]
	var first_difference := -1
	for sample: Array in source.missile.samples:
		sim.tick = int(sample[0])
		if sim.tick == 25: sim.soldiers[0].hp = 0
		sim._bullet_step(p)
		var actual: Array = [p.pos.x,p.pos.y,p.to.x,p.to.y,p.velocity.x,p.velocity.y]
		for column in 6:
			if absf(float(actual[column]) - float(sample[column + 1])) > 0.02 and first_difference == -1: first_difference = sim.tick
	check(first_difference == -1, "original Lua missile full flight first difference %d" % first_difference)
	check(p.done and p.target == sim.soldiers[1].id, "missile reselects after original target dies and impacts at source frame")
	check(source.missile.hits.size() == 1 and is_equal_approx(1000 - sim.soldiers[1].hp, source.missile.hits[0][2]), "missile source splash falloff damage")
	var corrupted: Dictionary = Levels.load_definition(6)
	corrupted.callbacks.soldier_paladin.insert = "unknown.insert"
	check(Sim.Behaviors.validate(corrupted, Levels.catalog()).contains("soldier_paladin.main_script.insert"), "unimplemented callback fails closed with reference")
	# Source silence removes named buffs and suppresses magic until expiry.
	var shaman: Dictionary = sim._spawn_enemy("enemy_shaman", 0)
	sim.modifiers.apply(sim,"mod_paladin_silence",shaman,1,"test")
	check(shaman.silence_count == 1 and not sim._healer_step(shaman,sim.templates.enemy_shaman), "silence disables shaman cast")
	sim.tick += 120; sim.modifiers.step(sim)
	check(shaman.silence_count == 0, "silence expiry releases magic ban")
func progression() -> void:
	var path = "user://level06_%d.json" % Time.get_ticks_usec()
	var p = Progress.new(); p.initialize(path)
	# The result API accepts only unlocked stages, as a real slot would.
	p.levels[5] = {}
	p.record_result({"generation":1,"level_id":5,"mode":1,"difficulty":2,"result":"victory","stars":3,"lives":20}); p.enter_map()
	check(p.is_playable(6), "fifth victory opens sixth")
	p.record_result({"generation":1,"level_id":6,"mode":1,"difficulty":2,"result":"victory","stars":3,"lives":20,"unlock_towers":["tower_paladin","tower_arcane_wizard"]}); p.enter_map()
	check(p.is_playable(6, 2) and p.is_playable(6, 3) and p.is_playable(7) and not p.is_playable(8), "sixth three stars opens challenges and seventh becomes playable")
	for mode in [2, 3]:
		p.record_result({"generation":1,"level_id":6,"mode":mode,"difficulty":2,"result":"victory","lives":1}); p.enter_map()
		check(p.record(6).get(mode, 0) == 2, "sixth challenge mode stored %d" % mode)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
