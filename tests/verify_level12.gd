extends "res://tests/verify_level08.gd"
## Stage-twelve source configuration, wave timelines and Veznan/portal/tower-lock/souls verification.

func fresh(mode: int = 1):
	var data := Levels.load_definition(12, mode)
	check(not data.is_empty(), "twelfth loads %d: %s" % [mode, Levels.last_error])
	if data.is_empty(): return null
	var sim = Sim.new(data, 42)
	sim.notices.clear()
	return sim

func hashes12() -> Dictionary:
	var result: Dictionary = {}
	for path: String in [
		"tests/verify_level12.gd", "tests/fixtures/level12_source.json",
		"scripts/battle/dove_veznan.gd", "scripts/battle/controllers/level12.gd",
		"scripts/battle/dove_behaviors.gd", "scripts/battle/dove_unit_info.gd",
		"scripts/battle/level01_sim.gd", "data/campaign_content.json",
		"data/level12/definition.json",
	]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func run() -> void:
	source = Levels.read_json("res://tests/fixtures/level12_source.json")
	check(not source.is_empty(), "twelfth independent source exists")
	check(Levels.supports(12, 1) and Levels.supports(12, 2) and Levels.supports(12, 3) and not Levels.supports(13) and not Levels.supports(12, 1, 3), "twelve levels and normal difficulty")
	for mode: int in [1, 2, 3]:
		var sim = fresh(mode)
		if sim == null: quit(1); return
		check(sim.gold == [1300, 1600, 2800][mode - 1] and sim.lives == [20, 1, 1][mode - 1], "source economy %d" % mode)
		check(sim.towers.size() == 13 and sim.data.waves.groups.size() == [15, 6, 1][mode - 1], "source tower sites and waves %d" % mode)
		check(sim.data.waves == source.modes[str(mode)], "complete raw source waves %d" % mode)
		check(not sim.data.layout.locked_hero and sim.data.layout.level_mode_overrides[mode - 1].max_upgrade_level == 6, "hero allowed and technology cap six %d" % mode)
		check(sim.data.locations.entrances.size() == 2 and sim.veznan.portals.size() == 3, "two entrances and three portals %d" % mode)
		for kind: String in Sim.TYPES:
			check(sim.tower_locked("tower_build_" + kind) == (mode == 3 and kind == "engineer"), "source build restriction %d/%s" % [mode, kind])
		var has_boss: bool = sim.enemies.any(func(e): return e.template == "eb_veznan")
		check(has_boss == (mode == 1), "campaign spawns castle Veznan only %d" % mode)
		var has_forsale: bool = sim.data.layout.entities_list.any(func(e): return str(e.get("render.sprites[1].name", "")) == "stage12_forsale")
		check(has_forsale == (mode != 1), "forsale sign only in challenges %d" % mode)
		timeline12(mode)
	power_points12()
	tower_lock12()
	portals12()
	souls_aura12()
	veznan_lifecycle12()
	demon_fire_melee12()
	progress12()
	negative12()
	write8("level12_comparisons", comparisons)
	write8("level12_timelines", timeline_report)
	write8("level12_logic", {
		"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"independent_modes": 3, "timeline_waves": 22, "births": births,
		"source_scenarios": 10, "full_replays": false, "source_hashes": hashes12(),
	})
	print("LEVEL12: ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "births": births, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func timeline12(mode: int) -> void:
	var sim = fresh(mode)
	sim.towers.clear(); sim.soldiers.clear(); sim.enemies.clear(); sim.controller.boss_id = 0
	var report: Array = []
	for group: int in source.timelines[str(mode)].size():
		var start: int = sim.tick
		var offset: int = sim.spawn_log.size()
		check(sim.command("wave"), "timeline starts %d/%d" % [mode, group + 1])
		while not sim.spawn_queue.is_empty():
			sim.enemies.clear(); sim.pending_entities.clear(); ticks(sim, 1)
		var actual: Array = []
		var expected: Array = source.timelines[str(mode)][group]
		for entry: Dictionary in sim.spawn_log.slice(offset):
			if entry.origin == "wave": actual.append([entry.tick - start, entry.type, entry.path, entry.subpath])
		var normalized: Array = actual.duplicate(true)
		for i: int in mini(expected.size(), normalized.size()):
			if int(expected[i][3]) == -1:
				check(int(normalized[i][3]) in [0, 1, 2], "random subpath legal %d/%d/%d" % [mode, group + 1, i])
				normalized[i][3] = -1
		compare8("source timeline %d/%d" % [mode, group + 1], expected, normalized, 0)
		report.append({"wave": group + 1, "expected": expected, "actual": actual, "first_difference": comparisons["source timeline %d/%d" % [mode, group + 1]].first_difference})
		births += actual.size(); sim.enemies.clear(); sim.pending_entities.clear()
	timeline_report[str(mode)] = report

func power_points12() -> void:
	var sim = fresh(1)
	for row: Dictionary in source.power_points:
		var pt := Vector2(float(row.x), float(row.y))
		var expected_extra: bool = bool(row.allowed)
		check(sim.controller.extra_fire_point(pt) == expected_extra, "fn_can_power rect (%d,%d)" % [int(row.x), int(row.y)])
		if expected_extra:
			check(sim.valid_power_point("fire", pt) and sim.valid_power_point("reinforcements", pt), "powers allowed in graveyard rect (%d,%d)" % [int(row.x), int(row.y)])

func tower_lock12() -> void:
	for mode: String in ["clicked_release", "timeout_trap"]:
		var sim = fresh(1)
		var tw: Dictionary = sim.tower_by_id("1")
		tw.template = "tower_archer_1"; tw.type = "archer"; tw.ready = 0; tw.inserted = true
		sim.enemies.clear(); sim.controller.boss_id = 0
		sim.tick = 0
		var sounds: Array = []
		sim.event.connect(func(kind, payload):
			if kind == "sound": sounds.append([sim.tick, payload.id])
		)
		sim.veznan.lock_tower(sim, tw, 1)
		var done_tick := -1
		var block_start := -1
		var block_end := -1
		for n: int in 420:
			sim.tick = n
			if mode == "clicked_release" and n in [40, 55, 70]:
				check(sim.command("tower_click", {"id": "1"}), "veznan tower click accepted %d" % n)
			var was_blocked: bool = bool(tw.get("blocked", false))
			sim.veznan.step_tower_locks(sim)
			var now_blocked: bool = bool(tw.get("blocked", false))
			if not was_blocked and now_blocked: block_start = n
			if was_blocked and not now_blocked: block_end = n
			if sim.veznan.tower_locks.is_empty(): done_tick = n; break
		var exp: Dictionary = source.tower_locks[mode]
		check(done_tick == int(exp.done_tick), "mod_veznan_tower done_tick %s (%d vs %d)" % [mode, done_tick, int(exp.done_tick)])
		check(block_start == 32 and block_end == int(exp.done_tick), "mod_veznan_tower block window %s (%d..%d)" % [mode, block_start, block_end])
		var exp_sounds: Array = []
		for ev: Array in exp.events:
			if ev[0] == "sound": exp_sounds.append([int(ev[1]), str(ev[2])])
		compare8("mod_veznan_tower sounds " + mode, exp_sounds, sounds, 0)

func portals12() -> void:
	var sim = fresh(1)
	sim.enemies.clear(); sim.controller.boss_id = 0
	for p: Dictionary in sim.veznan.portals:
		p.spawn_signal = true
	var births_by_portal := {}
	for n: int in 350:
		sim.tick = n
		var before: int = sim.enemies.size()
		sim.veznan.step_portals(sim)
		for e: Dictionary in sim.enemies.slice(before):
			births_by_portal[e.node] = int(births_by_portal.get(e.node, 0)) + 1
			check(e.template in ["enemy_demon", "enemy_demon_wolf", "enemy_demon_mage"], "portal spawns valid demon")
	check(births_by_portal.has(100) and births_by_portal.has(145) and births_by_portal.has(220), "all 3 portals spawn on source out_nodes 101/146/221")
	check(sim.veznan.portals.all(func(p): return p.phase == "idle" and not p.spawn_signal), "all portals return to idle")

func souls_aura12() -> void:
	var sim = fresh(1)
	sim.enemies.clear(); sim.controller.boss_id = 0
	var aura_t: Dictionary = sim.templates.veznan_souls_aura.souls
	var aura := {"pos": Vector2(500, 314), "entity": str(aura_t.entity), "angles": aura_t.angles, "count": int(aura_t.count), "delay_frames": int(aura_t.delay_frames), "emitted": 0, "next_at": 0, "interrupt": false}
	sim.veznan.souls_auras.append(aura)
	var ticks_emitted: Array = []
	for n: int in 121:
		sim.tick = n
		if n == 90: aura.interrupt = true
		var before: int = sim.veznan.souls.size()
		sim.veznan.step_souls(sim)
		if sim.veznan.souls.size() > before: ticks_emitted.append(n)
	var exp_ticks: Array = []
	for row: Array in source.souls_aura.spawns: exp_ticks.append([int(row[0])])
	var act_ticks: Array = []
	for t_val: Variant in ticks_emitted: act_ticks.append([int(t_val)])
	compare8("veznan_souls_aura emission ticks", exp_ticks, act_ticks, 0)
	check(not sim.veznan.soul_particles.is_empty(), "veznan_soul emits ps_veznan_soul particles")

func veznan_lifecycle12() -> void:
	var sim = fresh(1)
	var boss: Dictionary = sim.controller._boss(sim)
	check(is_equal_approx(boss.max_hp, float(source.veznan_stats.hp_difficulty_2)), "Veznan difficulty 2 HP is 7999 without 1.65x")
	check(boss.pos == Vector2(518, 677) and boss.ignore_damage and boss.health_bar_hidden, "Veznan spawns in castle untargetable")
	var taunts: Array = []
	var sounds: Array = []
	var hide_gui_events: Array = []
	sim.event.connect(func(kind, payload):
		if kind == "veznan_taunt": taunts.append(payload)
		elif kind == "sound": sounds.append(payload.id)
		elif kind == "hide_gui": hide_gui_events.append(sim.tick)
	)
	# Advance to welcome and start wave 1
	ticks(sim, 35)
	check(boss.veznan.phase == "welcome", "enters welcome after 1s")
	sim.command("wave")
	sim.spawn_queue.clear()
	ticks(sim, 5)
	check(boss.veznan.phase == "castle" and taunts.any(func(x): return x.key == "VEZNAN_TAUNT_0005"), "wave 1 triggers taunt #5 and enters castle")
	# Simulate waves complete to trigger descend
	sim.wave = 15
	sim.spawn_queue.clear()
	sim.enemies = [boss]
	for p: Dictionary in sim.veznan.portals: p.phase = "idle"; p.spawn_signal = false
	for _i in 360:
		ticks(sim, 1)
		if boss.veznan.phase == "battle": break
	check(boss.veznan.phase == "battle", "descends into battle phase")
	check(not boss.ignore_damage and not boss.health_bar_hidden and int(boss.vis.bans) == 0, "battle phase targetable with visible bar")
	# Test soul_drain in battle (militia killed & heals Veznan; elemental immune)
	boss.veznan.action = {}; boss.veznan.melee_job = {}
	boss.veznan.ba.disabled = true; boss.veznan.pa.disabled = true
	boss.veznan.sda.ts = sim.tick - 300
	boss.hp = boss.max_hp - 1000.0
	var hp_before: float = boss.hp
	var militia: Dictionary = sim._soldier("soldier_militia", "", 0, boss.pos + Vector2(60, 0), boss.pos + Vector2(60, 0))
	militia.rallying = false; militia.hp = 100.0; militia.max_hp = 100.0
	var elem: Dictionary = sim._soldier("soldier_elemental", "", 0, boss.pos + Vector2(70, 0), boss.pos + Vector2(70, 0))
	elem.rallying = false; elem.hp = 500.0; elem.max_hp = 500.0
	for _i in 45:
		ticks(sim, 1)
	check(militia.hp <= 0 and elem.hp == 500.0, "soul_drain instakills militia and skips elemental")
	check(is_equal_approx(boss.hp - hp_before, boss.max_hp * 0.035), "soul_drain heals 3.5% max HP")
	check("VeznanSoulDrain" in sounds, "soul_drain plays audio")
	# Lethal hit triggers demon transform
	var dealt: float = sim.damage(boss, 99999.0, 1)
	check(dealt == 0.0 and boss.veznan.phase_signal == "lethal", "battle lethal damage intercepted by on_damage")
	for _i in 60:
		ticks(sim, 1)
		if boss.veznan.phase == "demon": break
	check(boss.veznan.phase == "demon", "transforms into demon phase")
	check(is_equal_approx(boss.max_hp, float(source.veznan_stats.demon_hp_difficulty_2)) and is_equal_approx(boss.hp, boss.max_hp), "demon HP is initial_hp * 1.5 (11998.5)")
	check(boss.get("prefix", "") == "eb_veznan_demon" and boss.get("portrait", "") == "info_portraits_enemies_0072", "demon switches prefix and portrait")
	check(is_equal_approx(float(boss.get("speed_override", 0)), float(source.veznan_stats.speed_demon)), "demon speed is 18")
	check("VeznanToDemon" in sounds, "demon transform plays audio")
	# Build a tower to verify death blocks all towers
	var tw: Dictionary = sim.tower_by_id("1")
	tw.template = "tower_archer_1"; tw.type = "archer"; tw.ready = 0; tw.inserted = true
	# Lethal hit in demon triggers death -> souls -> white circle -> victory
	var dealt2: float = sim.damage(boss, 99999.0, 1)
	check(dealt2 == 0.0 and boss.veznan.phase_signal == "lethal", "demon lethal damage intercepted by on_damage")
	ticks(sim, 2)
	check(boss.veznan.phase == "death" and hide_gui_events.size() == 1 and tw.get("blocked", false), "death hides GUI and blocks all towers")
	check("VeznanDeath" in sounds, "death plays VeznanDeath")
	var saw_souls := false
	var saw_circle := false
	for _i in 450:
		ticks(sim, 1)
		if not sim.veznan.souls.is_empty(): saw_souls = true
		if not sim.veznan.white_circles.is_empty(): saw_circle = true
		if sim.result == "victory": break
	check(saw_souls and saw_circle, "death plays souls aura and white circle expansion")
	check(sim.result == "victory" and sim.custom_game_outcome.get("next_item_name", "") == "kr1_end", "death-end finishes campaign with kr1_end outcome hook")

func demon_fire_melee12() -> void:
	var sim = fresh(1)
	var boss: Dictionary = sim.controller._boss(sim)
	boss.veznan.phase = "demon"; boss.veznan.demon_mode = true
	boss.prefix = "eb_veznan_demon"; boss.ignore_damage = false; boss.vis.bans = 0
	boss.pos = Vector2(520, 320); boss.melee_slot_override = Vector2(50, 0); boss.veznan.melee_ts = [-100, -100]
	var guard: Dictionary = sim._soldier("soldier_militia", "", 0, boss.pos + Vector2(50, 0), boss.pos + Vector2(50, 0))
	guard.rallying = false; guard.hp = 50000.0; guard.max_hp = 50000.0
	boss.blocker = guard.id; boss.blockers = [guard.id]; guard.target = boss.id
	guard.pos = sim.melee_slot(guard, boss)
	var hit_ticks: Array = []
	var saw_fire_fx := false
	var start_tick: int = sim.tick
	for _i in 52:
		var prev_hp: float = guard.hp
		sim.step()
		if guard.hp < prev_hp: hit_ticks.append(sim.tick - start_tick - 1)
		if sim.effects.any(func(fx): return fx.template == "fx_veznan_demon_fire"): saw_fire_fx = true
	var expected_hits: Array = []
	for h: Variant in source.veznan_stats.demon_hit_times_ticks: expected_hits.append([int(h)])
	var actual_hits: Array = []
	for h: Variant in hit_ticks: actual_hits.append([int(h)])
	compare8("demon fire multi-hit ticks", expected_hits, actual_hits, 0)
	check(saw_fire_fx and not sim.effects.any(func(fx): return fx.template == "fx_veznan_demon_fire"), "demon fire spawns fx_veznan_demon_fire and cleans up after 26 frames")

func progress12() -> void:
	var p = Progress.new()
	var file: String = "res://output/level12_logic_slot_%d.json" % Time.get_ticks_usec()
	p.initialize(file)
	for id: int in range(1, 12):
		preload("res://tests/slot_fixture.gd").complete(p, {"generation": 1, "level_id": id, "mode": 1, "difficulty": 2, "result": "victory", "lives": 20})
	check(p.is_playable(12) and not p.is_playable(12, 2), "eleventh settlement opens twelfth campaign")
	for mode: int in [1, 2, 3]:
		preload("res://tests/slot_fixture.gd").complete(p, {"generation": 1, "level_id": 12, "mode": mode, "difficulty": 2, "result": "victory", "lives": 20 if mode == 1 else 1})
	check(p.is_playable(12, 2) and p.is_playable(12, 3) and not p.is_playable(13), "twelfth challenges save and thirteenth remains preview")
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(file + suffix): DirAccess.remove_absolute(file + suffix)

func negative12() -> void:
	var data := Levels.load_definition(12)
	for name: String in ["eb_veznan", "mod_veznan_tower", "veznan_portal", "veznan_souls_aura", "veznan_soul", "ps_veznan_soul", "decal_s12_shoutbox", "decal_eb_veznan_white_circle"]:
		var broken: Dictionary = data.duplicate(true)
		broken.templates.erase(name)
		check(not Sim.Behaviors.validate(broken, Levels.catalog()).is_empty(), "runtime refuses missing twelfth dependency " + name)
