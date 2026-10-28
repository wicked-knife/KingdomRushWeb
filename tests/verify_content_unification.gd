extends SceneTree
## Short deterministic combat samples; no victory search or complete campaign replay.
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
var failures: Array[String] = []
var checks := 0
var timelines := {}
var timeline_entries := 0
var timeline_waves := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func dismiss(sim) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")

func run() -> void:
	var samples := {}
	var baseline: Dictionary = Levels.read_json("res://tests/fixtures/content_combat_baseline.json")
	var record_current := OS.get_cmdline_user_args().has("--record-current")
	check(not baseline.is_empty(), "current combat snapshot exists")
	if not record_current: check(baseline.get("source",{}).get("commit","") == Levels.catalog().source.commit, "combat snapshot uses current source")
	var expected_timelines: Dictionary = Levels.read_json("res://tests/fixtures/content_timelines.json")
	check(expected_timelines.size() == 15, "all pre-migration mode timelines exist")
	check(not Levels.supports(7) and not Levels.supports(1, 1, 3), "preview and unsupported difficulty remain unavailable")
	var catalog := Levels.catalog()
	check(Sim.Controller.create("unknown", catalog) == null, "unknown controller rejected")
	var invalid := Levels.load_definition(5)
	invalid.behaviors.enemy_goblin = "unknown.enemy.update"
	check(Sim.Behaviors.validate(invalid, catalog).contains("enemy_goblin"), "unknown source behavior reports owner")
	invalid = Levels.load_definition(5); invalid.templates.erase("arrow_elf")
	check(Sim.Behaviors.validate(invalid, catalog).contains("arrow_elf"), "missing child template rejected")
	check(Sim.Behaviors.canonical("game_scripts.arrow_missile.update", catalog) == "scripts.arrow_missile.update", "verified source alias resolves")
	check(Sim.Behaviors.canonical("unknown.arrow_missile.update", catalog) == "unknown.arrow_missile.update", "unverified suffix never aliases")
	shaman_binding()
	for id in range(1, 6):
		for mode in [1, 2, 3]:
			var data := Levels.load_definition(id, mode)
			check(not data.is_empty(), "registered content loads %d/%d: %s" % [id, mode, Levels.last_error])
			if data.is_empty(): continue
			var sim = Sim.new(data, 42)
			check(sim.gold == {1:[270,230,360],2:[240,310,275],3:[330,400,660],4:[520,750,1500],5:[700,1000,1500]}[id][mode-1], "source economy %d/%d" % [id, mode])
			check(sim.lives == (20 if mode == 1 else 1), "source lives %d/%d" % [id, mode])
			check(sim.notices.has("TUTORIAL_1") == (id == 1 and mode == 1), "tutorial policy %d/%d" % [id, mode])
			dismiss(sim)
			check(sim.command("wave"), "first wave %d/%d" % [id, mode])
			check(sim.unlocked.fire == (id != 1 or mode != 1), "first-wave power policy %d/%d" % [id, mode])
			timeline(data, "%d/%d" % [id, mode], expected_timelines.get("%d/%d" % [id, mode], []))
	# Compare before/after hashes for actual attacks, modifiers, recruitment and hatching.
	for id in [1, 3, 5]:
		var definition := Levels.load_definition(id)
		if definition.is_empty(): continue
		var sim = Sim.new(definition, 42)
		dismiss(sim); sim.gold = 10000
		var empty: Array = sim.towers.filter(func(t): return t.type == "")
		for index in Sim.TYPES.size():
			check(sim.command("build", {"id":empty[index].id,"type":Sim.TYPES[index]}), "representative build %d/%d" % [id,index])
		for tick in range(25): sim.step()
		if id == 5:
			check(sim.command("upgrade", {"id":"4","upgrade_to":"tower_ranger"}), "ranger binding")
			check(sim.command("upgrade_power", {"id":"4","power":"poison"}), "ranger skill binding")
			check(sim.command("upgrade", {"id":"5","upgrade_to":"tower_elf"}), "camp binding")
			check(sim.command("buy_soldier", {"id":"5","type":"soldier_elf"}), "recruit binding")
			check(sim.command("upgrade_power", {"id":"5","power":"bleed"}), "camp skill binding")
			var mother: Dictionary = sim._spawn_enemy("enemy_spider_big", 0, 0)
			mother.egg_at = sim.tick - 1
		check(sim.command("wave"), "representative combat starts %d" % id)
		var hashes: Array = []
		for index in range(1200):
			dismiss(sim); sim.step()
			if index % 100 == 99:
				var state := [sim.tick,sim.gold,sim.lives,sim.kills,sim.leaks,sim.rng.state,sim.towers,sim.enemies,sim.soldiers,sim.projectiles,sim.modifiers.active,sim.eggs,sim.spawn_log]
				hashes.append(var_to_str(state).sha256_text())
		samples[str(id)] = hashes
		if not record_current: check(hashes == baseline.get("samples", {}).get(str(id), []), "combat state matches current snapshot %d; first differing sample %d" % [id, first_difference(hashes, baseline.get("samples", {}).get(str(id), []))])
	if record_current and failures.is_empty():
		var snapshot := FileAccess.open("res://tests/fixtures/content_combat_baseline.json",FileAccess.WRITE)
		snapshot.store_string(JSON.stringify({"source":Levels.catalog().source,"samples":samples},"\t")); snapshot.close()
	var timeline_file := FileAccess.open("res://reports/content_timelines.json", FileAccess.WRITE)
	timeline_file.store_string(JSON.stringify(timelines)); timeline_file.close()
	var report := {"passed":failures.is_empty(),"checks":checks,"combinations":15,"timeline_waves":timeline_waves,"timeline_entries":timeline_entries,"timeline_report":"reports/content_timelines.json","combat_scenarios":3,"combat_ticks":3600,"samples":samples,"failures":failures}
	var suffix := "_before" if OS.get_cmdline_user_args().has("--before") else ""
	var file := FileAccess.open("res://reports/content_unification" + suffix + ".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CONTENT_UNIFICATION: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " checks=", checks, " waves=", timeline_waves, " births=", timeline_entries, " combat_ticks=3600")
	quit(0 if failures.is_empty() else 1)

func first_difference(actual: Array, expected: Array) -> int:
	for index in mini(actual.size(), expected.size()):
		if actual[index] is Array and expected[index] is Array:
			if first_difference(actual[index], expected[index]) != -1: return index
		elif actual[index] != expected[index]: return index
	return -1 if actual.size() == expected.size() else mini(actual.size(), expected.size())

func timeline(data: Dictionary, key: String, expected: Array) -> void:
	var sim = Sim.new(data, 42)
	var groups: Array = []
	for index in expected.size():
		dismiss(sim)
		var started: int = sim.tick
		check(sim.command("wave"), "timeline wave starts %s/%d" % [key, index + 1])
		var offset: int = sim.spawn_log.size()
		while not sim.spawn_queue.is_empty():
			dismiss(sim); sim.enemies.clear(); sim.eggs.clear(); sim.step()
		var actual: Array = []
		var normalized: Array = []
		for entry: Dictionary in sim.spawn_log.slice(offset):
			actual.append([entry.tick - started, entry.type, entry.path, entry.subpath])
			var position: int = normalized.size()
			var random_subpath: bool = position < expected[index].size() and int(expected[index][position][3]) == -1
			normalized.append([entry.tick - started, entry.type, entry.path, -1 if random_subpath and entry.subpath >= 0 and entry.subpath < 3 else entry.subpath])
		var difference := first_difference(normalized, expected[index])
		check(difference == -1, "complete timeline %s wave %d; first difference %d" % [key, index + 1, difference])
		groups.append({"wave":index + 1,"expected":expected[index],"actual":actual,"first_difference":difference})
		timeline_waves += 1; timeline_entries += actual.size()
		sim.enemies.clear(); sim.eggs.clear()
	timelines[key] = groups

func shaman_binding() -> void:
	var sim = Sim.new(Levels.load_definition(3), 42)
	var shaman: Dictionary = sim._spawn_enemy("enemy_shaman", 0)
	var ally: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	ally.pos = shaman.pos + Vector2(10, 0); ally.hp -= 60
	var injured: float = ally.hp
	sim.tick = 240
	check(not sim.behaviors.enemy_step(sim, shaman, sim.templates.enemy_shaman), "registered healer preserves strict eight-second cooldown")
	sim.tick = 241; sim._enemy_step(shaman)
	check(shaman.state == "heal" and not shaman.casting.is_empty(), "normal enemy loop dispatches source shaman behavior")
	sim.tick += 13; sim._enemy_step(shaman)
	check(ally.hp == injured, "registered healer waits fourteen frames")
	sim.tick += 1; sim._enemy_step(shaman)
	check(ally.hp == injured + 50, "registered healer applies source heal amount")
	sim.damage(shaman, 9999, 1); var before: float = ally.hp
	sim.tick += 241; sim._enemy_step(shaman)
	check(ally.hp == before, "dead registered healer cannot heal")
