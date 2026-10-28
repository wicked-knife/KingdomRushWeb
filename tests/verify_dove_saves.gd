extends SceneTree
const Progress = preload("res://scripts/services/campaign_progress.gd")
const Slots = preload("res://scripts/services/save_slots.gd")
const Settings = preload("res://scripts/services/menu_settings.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
var checks := 0
var failures: Array[String] = []
var temporary := "user://dove_saves_%d" % Time.get_ticks_usec()
func _init() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(value)); file.close()
func win(id: int, lives: int = 20, generation: int = 1) -> Dictionary:
	return {"generation": generation, "level_id": id, "mode": 1, "difficulty": 2, "lives": lives, "result": "victory", "unlock_towers": []}
func complete(p: RefCounted, outcome: Dictionary) -> Dictionary:
	check(p.record_result(outcome), "accept campaign victory %d" % int(outcome.level_id))
	return p.enter_map()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(temporary)
	var settings := Settings.new(); settings.initialize(temporary + "/settings.json")
	settings.set_volumes(0.4, 0.7); settings.data.custom_setting = {"keep": true}
	var slots := Slots.new(); slots.initialize(temporary + "/saves", settings)
	check(slots.status(1) == "empty" and slots.status(2) == "empty" and slots.status(3) == "empty", "new storage starts with three empty slots")
	var p := slots.select_slot(1); var second := slots.select_slot(2)
	check(p.data.levels.keys().all(func(k): return k is int), "all in-memory level keys are integers")
	check(p.unlocked == [1] and p.total_stars() == 0 and p.data.levels.has(201), "shared source template preserves other generation entry points")
	check(p.data.upgrades.archers == 0 and p.data.bag.is_empty() and p.data.gems == 0 and p.data.locked_towers.size() == 75, "full source defaults exported")
	check(p.max_stars == 645 and slots.summaries()[0].max_stars == 645, "shared star denominator comes from all source generations")
	p.data.bag.example = 2; p.data.upgrades.archers = 1
	check(second.data.bag.is_empty() and second.data.upgrades.archers == 0, "new slots deep-copy every nested field")
	p.data.upgrades.archers = 0
	check(slots.slot_path(1) == temporary + "/saves/slot_1.json", "generation-independent slot path")
	check(p.record_result(win(1, 5)) and p.record(1).is_empty() and not p.is_unlocked(2), "victory is persisted without immediate settlement")
	check(p.total_stars() == 0 and p.summary().stars == 1 and slots.summaries()[0].stars == 1, "slot summary projects pending victory")
	check(not p.record_result(win(1, 5)), "identical pending result is idempotent")
	var reloaded := Slots.new(); reloaded.initialize(slots.directory, settings)
	p = reloaded.select_slot(1)
	check(p.data.has("last_victory") and p.total_stars() == 0, "pending victory survives process reload")
	var changes: Dictionary = p.enter_map()
	check(p.record(1) == {"stars": 1, 1: 2} and p.record(2).is_empty() and p.is_unlocked(2), "map commits mode record and empty next level")
	check(changes.stars["1"] == {"before": 0, "after": 1} and changes.unlocked == [2] and not p.data.has("last_victory"), "map returns changes and clears pending data")
	check(p.enter_map() == {"stars": {}, "unlocked": [], "heroic": [], "iron": []}, "re-entering map never repeats settlement")
	var disk := Progress.read_json(p.path)
	check(disk.levels["1"]["1"] == 2 and disk.levels["2"] is Dictionary and disk.levels["2"].is_empty(), "JSON serializes numeric mode keys and empty objects")
	for id in range(2, 5): complete(p, win(id))
	check(p.is_playable(5) and p.record(5).is_empty(), "settled fourth victory opens fifth generically")
	var fifth := win(5); fifth.unlock_towers = ["tower_ranger", "tower_elf"]
	check(p.record_result(fifth) and "tower_ranger" in p.data.locked_towers, "tower unlock waits for map")
	var before: int = p.total_stars()
	check(p.record_result({"result": "defeat"}) and not p.data.has("last_victory") and p.total_stars() == before, "defeat clears pending victory without changing committed best")
	check(not p.is_unlocked(6) and "tower_ranger" in p.data.locked_towers, "discarded fifth victory grants no unlock")
	complete(p, fifth)
	check(p.is_unlocked(6) and p.is_playable(6) and p.record(5)[1] == 2, "fifth settlement opens sixth campaign")
	check(not "tower_ranger" in p.data.locked_towers and not "tower_elf" in p.data.locked_towers, "settlement removes source unlocked towers")
	complete(p, win(5, 1)); check(p.record(5).stars == 3, "lower victory preserves best stars")
	var harder := win(5, 6); harder.difficulty = 4; complete(p, harder)
	check(p.record(5).stars == 3 and p.record(5)[1] == 4, "difficulty and stars improve independently")
	var challenge := win(5); challenge.mode = 2
	check(p.record_result(challenge) and Levels.supports(5, 2), "challenge victory uses unified pending result")
	# The shared slot can already retain and settle the source's mode records.
	p.data.last_victory = {"level_idx": 5, "level_mode": 2, "level_difficulty": 3, "stars": 1, "unlock_towers": []}
	check(p.summary().heroic == 1 and p.summary().stars == p.total_stars() + 1, "pending heroic summary counts one extra star")
	p.enter_map(); check(p.record(5)[2] == 3, "numeric heroic record retained")
	p.levels[5][3] = 2
	p.data.future_field = {"items": [1, "two", {"ok": true}]}; p.levels[9999] = {"custom": {"value": 7}}
	p.levels[27] = {1: 2, "stars": 2}; p.levels[5].custom_level_field = "retained"
	p.data.heroes.future_hero_field = {"xp": 123}; p.data.achievements = {"example":1}
	check(p.data.upgrade_list_id is String and p.data.upgrade_list_id == "1", "current source tech ID is a string")
	p.flush_seen({"enemy_wolf": true, "enemy_spider_big": true, "enemy_spider_small": true, "enemy_marauder": true, "FUTURE_NOTICE": true})
	p.save(); var restored := Progress.new(); restored.initialize(p.path)
	check(restored.data.future_field.items[0] == 1 and restored.data.future_field.items[1] == "two" and restored.data.future_field.items[2].ok and restored.record(9999).custom.value == 7 and restored.record(27)[1] == 2, "unknown fields and non-playable generation records round-trip")
	check(restored.record(5)[2] == 3 and restored.record(5)[3] == 2 and restored.record(5).custom_level_field == "retained", "all mode keys and custom level data round-trip")
	check(restored.data.heroes.future_hero_field.xp == 123 and restored.data.achievements.example == 1, "unimplemented feature data survives saves")
	check(restored.data.seen.FUTURE_NOTICE and restored.data.seen.enemy_marauder, "seen has no content whitelist")
	var stage := Levels.load_definition(5); stage.seen = restored.data.seen
	stage.slot_locked_towers = Progress.decode(Progress.read_json(Progress.SLOT_DEFINITION).template).locked_towers
	var sim := Sim.new(stage)
	check(not sim.tower_locked("tower_ranger") and not sim.tower_locked("tower_elf") and sim.tower_locked("tower_musketeer"), "current level unlock overrides global locks only for its own towers")
	for enemy in ["enemy_wolf", "enemy_spider_big", "enemy_spider_small", "enemy_marauder"]: sim._spawn_enemy(enemy)
	check(sim.alerts.is_empty(), "fifth enemies use persistent seen table")
	var first_stage := Levels.load_definition(1); first_stage.slot_locked_towers = stage.slot_locked_towers
	check(Sim.new(first_stage).tower_locked("tower_archer_2"), "early campaign tier cap remains enforced")
	# Every source range runs through the same algorithm, without scene support.
	for generation: String in p.rules:
		var branch := Progress.new(); branch.initialize(temporary + "/generation_" + generation + ".json"); branch.data.last_generation = int(generation)
		var groups: Array = branch.rules[generation].level_ranges
		var start: int = groups[0][0]
		branch.enter_map(); complete(branch, win(start, 20, int(generation)))
		check(branch.is_unlocked(start + 1), "range continuation generation " + generation)
		var last: int = branch.rules[generation].main_campaign_last
		branch.levels[last] = {"stars": 3, 1: 2}; branch.enter_map()
		for group: Array in groups.slice(1): check(branch.is_unlocked(int(group[0])), "main campaign opens branch %s/%d" % [generation, int(group[0])])
		for group: Array in groups:
			if group.size() < 2 or int(group[0]) == start: continue
			var head: int = group[0]; complete(branch, win(head, 20, int(generation)))
			check(branch.is_unlocked(head + 1), "branch continuation %s/%d" % [generation, head])
	# Backups contain the entire slot, not just campaign flags.
	write(p.path, "corrupt"); restored.initialize(p.path)
	check(restored.data.future_field.items[0] == 1 and restored.data.future_field.items[2].ok and not restored.notice.is_empty(), "corrupt primary recovers complete healthy backup")
	DirAccess.remove_absolute(p.path); restored.initialize(p.path)
	check(restored.record(27).stars == 2, "missing primary recovers backup")
	write(p.path, "bad"); write(p.path + ".bak", "bad")
	var broken := Slots.new(); broken.initialize(slots.directory)
	check(broken.status(1) == "corrupt" and broken.select_slot(1) == null, "unrecoverable slot is not silently replaced")
	write(p.path, {"schema_version": 99}); broken.initialize(slots.directory)
	check(broken.status(1) == "future" and broken.select_slot(1) == null, "future format cannot be overwritten")
	check(broken.delete_slot(1) and broken.status(1) == "empty", "delete retires primary and backup together")
	broken.initialize(slots.directory); check(broken.select_slot(1).total_stars() == 0, "deleted slot never resurrects")
	var deleted := broken.select_slot(1); complete(deleted, win(1)); deleted.save()
	if OS.get_name() == "Windows":
		var held := FileAccess.open(deleted.path + ".bak", FileAccess.READ)
		check(not broken.delete_slot(1) and FileAccess.file_exists(deleted.path), "failed backup retirement rolls primary back")
		held.close()
	var blocked_path := temporary + "/blocked"; write(blocked_path, "file")
	var blocked := Slots.new(); blocked.initialize(blocked_path + "/saves")
	var memory := blocked.select_slot(1); complete(memory, win(1))
	check(memory.total_stars() == 3 and not memory.notice.is_empty() and blocked.select_slot(1) == memory, "write failure retains session data and reports failure")
	slots.select_slot(3); var settings_again := Settings.new(); settings_again.initialize(settings.settings_path)
	check(settings_again.last_slot_idx == 3 and is_equal_approx(settings_again.music_volume, 0.4) and settings_again.data.custom_setting.keep, "last slot saves with global preferences without losing unknown settings")
	check(not FileAccess.file_exists(slots.directory + "/index.json"), "no slot index is created")
	settings.free(); settings_again.free()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "generations": [1, 2, 3, 5, 6], "browser_tested": false}
	write("res://reports/dove_saves_logic.json", report)
	print("DOVE_SAVES: ", JSON.stringify(report)); remove_tree(temporary); quit(0 if failures.is_empty() else 1)
func remove_tree(folder: String) -> void:
	for child in DirAccess.get_directories_at(folder): remove_tree(folder + "/" + child)
	for child in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + child)
	DirAccess.remove_absolute(folder)
