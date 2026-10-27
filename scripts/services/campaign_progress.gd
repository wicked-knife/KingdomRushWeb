extends RefCounted
## A Dove slot session. Only JSON boundaries translate numeric table keys.
signal changed
signal notice_changed(message: String)
const DEFAULT_PATH := "user://saves/slot_1.json"
const DEFINITION := "res://data/map_kr1/definition.json"
const SLOT_DEFINITION := "res://data/save/definition.json"
const HERO_DEFINITION := "res://data/heroes/definition.json"
const CampaignLevels = preload("res://scripts/services/campaign_levels.gd")
var data := {}
var rules := {}
var definition: Dictionary
var hero_definition: Dictionary
var hero_rows := {}
var notice := ""
var path := DEFAULT_PATH
var save_allowed := true
var max_stars := 0
# Views into the same slot; no secondary progression representation.
var levels: Dictionary:
	get: return data.levels
	set(value): data.levels = value
var heroes: Dictionary:
	get: return data.heroes
var unlocked: Array[int]:
	get:
		var ids: Array[int] = []
		for id: int in levels:
			if _in_generation(id, int(data.last_generation)): ids.append(id)
		ids.sort()
		return ids

static func stars_for(lives: int) -> int:
	return 3 if lives >= 18 else (2 if lives >= 6 else (1 if lives > 0 else 0))

static func read_json(filename: String) -> Dictionary:
	if not FileAccess.file_exists(filename): return {}
	var parsed := JSON.new()
	return parsed.data if parsed.parse(FileAccess.get_file_as_string(filename)) == OK and parsed.data is Dictionary else {}

static func valid(value: Dictionary) -> bool:
	if value.get("schema_version", 0) != 1: return false
	for key in ["levels", "upgrades", "heroes", "seen", "achievements", "bag"]:
		if not value.get(key) is Dictionary: return false
	if not value.heroes.get("selected") is Array or not value.get("locked_towers") is Array: return false
	if value.has("last_victory") and not value.last_victory is Dictionary: return false
	if not value.get("last_generation") is float and not value.get("last_generation") is int: return false
	for id: Variant in value.levels:
		if not str(id).is_valid_int() or int(id) <= 0 or not value.levels[id] is Dictionary: return false
		var row: Dictionary = value.levels[id]
		for key: Variant in row:
			if str(key) not in ["stars", "1", "2", "3"]: continue
			var v: Variant = row[key]
			if not (v is int or v is float) or not is_finite(float(v)) or float(v) != int(v): return false
			if int(v) < (0 if str(key) == "stars" else 1) or int(v) > (3 if str(key) == "stars" else 4): return false
	for tower: Variant in value.locked_towers:
		if not tower is String: return false
	return true

static func decode(value: Dictionary) -> Dictionary:
	var out := value.duplicate(true)
	var decoded := {}
	for id: Variant in out.levels:
		var row := {}
		for key: Variant in out.levels[id]:
			row[int(key) if str(key).is_valid_int() else key] = out.levels[id][key]
		decoded[int(id)] = row
	out.levels = decoded
	return out

func initialize(save_path: String = DEFAULT_PATH) -> void:
	path = save_path; save_allowed = true; _notice("")
	var exported := read_json(SLOT_DEFINITION)
	rules = exported.generations
	max_stars = int(exported.max_stars)
	data = decode(exported.template)
	definition = read_json(DEFINITION)
	hero_definition = read_json(HERO_DEFINITION); hero_rows.clear()
	for row: Dictionary in hero_definition.heroes: hero_rows[row.name] = row
	var loaded := read_json(path)
	if int(loaded.get("schema_version", 0)) > 1:
		save_allowed = false; _notice("存档来自较新版本，本次进度暂不写入该文件。"); return
	if not valid(loaded) and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")):
		loaded = read_json(path + ".bak")
		_notice("进度文件无法读取，已恢复备份。" if valid(loaded) else "存档无法读取，原文件已保留。")
		if not valid(loaded): save_allowed = false; return
	if valid(loaded): data = decode(loaded)
	var selected: Array = []
	for id: Variant in heroes.selected:
		if id is String and is_hero_unlocked(id) and not id in selected and selected.size() < 2: selected.append(id)
	heroes.selected = selected

func _in_generation(id: int, generation: int) -> bool:
	for group: Array in rules.get(str(generation), {}).get("level_ranges", []):
		if id >= int(group[0]) and id <= int(group[-1]): return true
	return false

func hero(id: String) -> Dictionary: return hero_rows.get(id, {})
func selected_hero_ids() -> Array[String]:
	var ids: Array[String] = []; ids.assign(heroes.selected); return ids
func is_hero_unlocked(id: String) -> bool:
	var row := hero(id)
	return not row.is_empty() and int(record(int(row.available_level)).get("stars", 0)) > 0
func select_hero(id: String) -> bool:
	if not is_hero_unlocked(id) or id in heroes.selected: return false
	if heroes.selected.size() == 2: heroes.selected[1] = id
	else: heroes.selected.append(id)
	save(); changed.emit(); return true
func deselect_hero(id: String) -> bool:
	if not id in heroes.selected: return false
	heroes.selected.erase(id); save(); changed.emit(); return true
func is_unlocked(id: int) -> bool: return levels.has(id)
func is_playable(id: int, mode: int = 1, difficulty: int = 2) -> bool:
	return is_unlocked(id) and CampaignLevels.supports(id, mode, difficulty) and (mode == 1 or int(record(id).get("stars", 0)) >= 3)
func record(id: int) -> Dictionary: return levels.get(id, {})
func mark_seen(id: String) -> bool:
	if id.is_empty() or data.seen.get(id, false): return false
	data.seen[id] = true; return true
func flush_seen(seen: Dictionary) -> void:
	var dirty := false
	for id: String in seen:
		if seen[id]: dirty = mark_seen(id) or dirty
	if dirty: save()
func total_stars() -> int:
	var total := 0
	for row: Dictionary in levels.values(): total += int(row.get("stars", 0)) + int(row.has(2)) + int(row.has(3))
	return total
func summary() -> Dictionary:
	var row := {"stars": total_stars(), "heroic": 0, "iron": 0}
	for level: Dictionary in levels.values():
		row.heroic += int(level.has(2)); row.iron += int(level.has(3))
	var victory: Dictionary = data.get("last_victory", {})
	if not _valid_victory(victory): return row
	var level := record(int(victory.level_idx)); var mode := int(victory.level_mode)
	if mode == 1: row.stars += maxi(0, int(victory.stars) - int(level.get("stars", 0)))
	elif not level.has(mode):
		row.stars += 1; row["heroic" if mode == 2 else "iron"] += 1
	return row

func _valid_victory(victory: Dictionary) -> bool:
	for key in ["level_idx", "level_mode", "level_difficulty", "stars"]:
		var value: Variant = victory.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value): return false
	return is_unlocked(int(victory.level_idx)) and int(victory.level_mode) in [1, 2, 3] and int(victory.level_difficulty) in [1, 2, 3, 4] and int(victory.stars) in [1, 2, 3] and victory.get("unlock_towers") is Array and victory.unlock_towers.all(func(tower): return tower is String)

func record_result(outcome: Dictionary) -> bool:
	if outcome.get("result", "") == "defeat":
		var had := data.has("last_victory")
		data.erase("last_victory"); save(); changed.emit(); return had
	var id := int(outcome.get("level_id", 0))
	var mode := int(outcome.get("mode", 0))
	if outcome.get("result", "") != "victory" or mode not in [1, 2, 3] or not is_unlocked(id) or not _in_generation(id, int(outcome.get("generation", 1))): return false
	var stars := stars_for(int(outcome.get("lives", 0))) if mode == 1 else (1 if int(outcome.get("lives", 0)) > 0 else 0)
	if stars == 0: return false
	var victory := {"level_idx": id, "level_mode": int(outcome.mode), "level_difficulty": clampi(int(outcome.get("difficulty", 2)), 1, 4), "stars": stars, "unlock_towers": outcome.get("unlock_towers", []).duplicate()}
	if data.get("last_victory", {}) == victory: return false
	data.last_victory = victory; save(); changed.emit(); return true

func enter_map() -> Dictionary:
	var changes := {"stars": {}, "unlocked": [], "heroic": [], "iron": []}
	var dirty := data.has("last_victory")
	var victory: Dictionary = data.get("last_victory", {})
	if _valid_victory(victory):
		var id := int(victory.level_idx); var mode := int(victory.level_mode)
		var row := record(id); var before := int(row.get("stars", 0))
		if mode == 1 and int(victory.stars) > before:
			row.stars = int(victory.stars)
			changes.stars[str(id)] = {"before": before, "after": int(victory.stars)}
		if mode != 1 and not row.has(mode): changes["heroic" if mode == 2 else "iron"].append(id)
		row[mode] = maxi(int(row.get(mode, 0)), int(victory.level_difficulty))
		for tower: String in victory.unlock_towers: data.locked_towers.erase(tower)
	data.erase("last_victory")
	# Same range-based progression as U.unlock_next_levels_in_ranges. Unlocks
	# persist as empty records, independently of available scenes/resources.
	var config: Dictionary = rules.get(str(int(data.last_generation)), {})
	var groups: Array = config.get("level_ranges", [])
	if not groups.is_empty():
		if not is_unlocked(int(groups[0][0])): _unlock(int(groups[0][0]), changes)
		if record(int(config.main_campaign_last)).has(1):
			for group: Array in groups.slice(1):
				if not is_unlocked(int(group[0])): _unlock(int(group[0]), changes)
		for group: Array in groups:
			if group.size() < 2: continue
			for id in range(int(group[0]), int(group[1])):
				if record(id).has(1) and not is_unlocked(id + 1):
					_unlock(id + 1, changes); break
	if dirty or not changes.unlocked.is_empty(): save(); changed.emit()
	return changes

func _unlock(id: int, changes: Dictionary) -> void:
	levels[id] = {}; changes.unlocked.append(id)

func save() -> bool:
	if not save_allowed: return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: _notice("进度已在本次游戏中生效，但无法保存到本地。"); return false
	file.store_string(JSON.stringify(data)); file.flush()
	var error := file.get_error(); file.close()
	if error != OK: _notice("进度写入失败，本次游戏仍可继续。"); return false
	if valid(read_json(path)) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		_notice("进度备份失败，本次游戏仍可继续。"); return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		_notice("进度保存失败，本次游戏仍可继续。"); return false
	_notice("浏览器未开启本地存储，本次进度可能无法保留。" if OS.has_feature("web") and not OS.is_userfs_persistent() else "")
	return true

func _notice(value: String) -> void:
	notice = value; notice_changed.emit(value)
