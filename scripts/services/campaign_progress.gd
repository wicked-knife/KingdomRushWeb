extends RefCounted
## Single-generation progression. Scene availability is deliberately separate from unlocks.
signal changed
signal notice_changed(message: String)
const DEFAULT_PATH := "user://campaign_kr1.json"
const DEFINITION := "res://data/map_kr1/definition.json"
const HERO_DEFINITION := "res://data/heroes/definition.json"
const CampaignLevels = preload("res://scripts/services/campaign_levels.gd")
var definition: Dictionary
var hero_definition: Dictionary
var hero_rows := {}
var heroes := {"selected": []}
var seen_notifications: Array[String] = []
var levels := {}
var unlocked: Array[int] = [1]
var notice := ""
var path := DEFAULT_PATH
var save_allowed := true
var pending := {"stars": {}, "unlocked": []}

static func stars_for(lives: int) -> int:
	return 3 if lives >= 18 else (2 if lives >= 6 else (1 if lives > 0 else 0))

func initialize(save_path: String = DEFAULT_PATH) -> void:
	path = save_path; levels.clear(); unlocked = [1]; save_allowed = true
	heroes = {"selected": []}; hero_rows.clear()
	seen_notifications.clear()
	hero_definition = _read(HERO_DEFINITION)
	for row: Dictionary in hero_definition.get("heroes", []): hero_rows[row.name] = row
	pending = {"stars": {}, "unlocked": []}; _notice("")
	definition = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION))
	var loaded := {}
	if FileAccess.file_exists(path):
		loaded = _read(path)
		if not _valid(loaded):
			if int(loaded.get("schema_version", 0)) > 1:
				save_allowed = false; _notice("进度来自较新版本，本次进度暂不写入该文件。")
				return
			loaded = _read(path + ".bak")
			_notice("进度文件无法读取，已恢复备份。" if _valid(loaded) else "进度文件无法读取，本次从第一关开始。")
		if loaded.get("schema_version", 0) == 1 and loaded.get("generation", 0) == 1 and loaded.get("levels") is Dictionary:
			for stage: Dictionary in definition.levels:
				var record: Variant = loaded.levels.get(str(int(stage.id)), {})
				if not record is Dictionary: continue
				var normalized := {}
				for key in ["stars", "campaign", "heroic", "iron"]:
					var value: Variant = record.get(key, 0)
					if (value is int or value is float) and is_finite(float(value)):
						normalized[key] = clampi(int(value), 0, 3 if key == "stars" else 4)
				if int(normalized.get("campaign", 0)) > 0 and int(normalized.get("stars", 0)) > 0:
					levels[str(int(stage.id))] = normalized
	_recompute()
	var seen: Variant = loaded.get("seen_notifications", [])
	if seen is Array:
		for id: Variant in seen:
			if id is String and id in ["enemy_wolf_small", "enemy_shaman", "enemy_ogre"] and not id in seen_notifications: seen_notifications.append(id)
	var hero_data: Variant = loaded.get("heroes", {})
	var selected: Variant = hero_data.get("selected", []) if hero_data is Dictionary else []
	if selected is Array:
		for id: Variant in selected:
			if id is String and is_hero_unlocked(id) and not id in heroes.selected and heroes.selected.size() < 2:
				heroes.selected.append(id)

func hero(id: String) -> Dictionary: return hero_rows.get(id, {})
func selected_hero_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(heroes.selected)
	return ids
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
	heroes.selected.erase(id)
	save(); changed.emit(); return true

func _read(filename: String) -> Dictionary:
	if not FileAccess.file_exists(filename): return {}
	var parsed := JSON.new()
	return parsed.data if parsed.parse(FileAccess.get_file_as_string(filename)) == OK and parsed.data is Dictionary else {}

func _valid(value: Dictionary) -> bool:
	return value.get("schema_version", 0) == 1 and value.get("generation", 0) == 1 and value.get("levels") is Dictionary

func _recompute() -> void:
	unlocked = [1]
	if int(levels.get(str(int(definition.main_campaign_last)), {}).get("campaign", 0)) > 0:
		for group: Array in definition.level_ranges:
			if not int(group[0]) in unlocked: unlocked.append(int(group[0]))
	for group: Array in definition.level_ranges:
		if group.size() < 2: continue
		for id in range(int(group[0]), int(group[1])):
			if int(levels.get(str(id), {}).get("campaign", 0)) > 0 and not id + 1 in unlocked: unlocked.append(id + 1)
	# Completed flags also remain available when opening a sanitized save.
	for id: String in levels:
		if not int(id) in unlocked: unlocked.append(int(id))
	unlocked.sort()

func is_unlocked(id: int) -> bool: return id in unlocked
func is_playable(id: int, mode: int = 1, difficulty: int = 2) -> bool:
	return is_unlocked(id) and CampaignLevels.supports(id, mode, difficulty)
func record(id: int) -> Dictionary: return levels.get(str(id), {})
func mark_notification_seen(id: String) -> void:
	if id in seen_notifications or not id in ["enemy_wolf_small", "enemy_shaman", "enemy_ogre"]: return
	seen_notifications.append(id); save()
func total_stars() -> int:
	var total := 0
	for value: Dictionary in levels.values():
		total += int(value.get("stars", 0)) + int(int(value.get("heroic", 0)) > 0) + int(int(value.get("iron", 0)) > 0)
	return total

func record_result(outcome: Dictionary) -> bool:
	if outcome.get("result", "") != "victory" or outcome.get("generation", 1) != 1 or outcome.get("mode", 0) != 1: return false
	var id := int(outcome.get("level_id", 0))
	if not is_unlocked(id) or not definition.levels.any(func(stage): return int(stage.id) == id): return false
	var stars := stars_for(int(outcome.get("lives", 0)))
	if stars == 0: return false
	var previous: Dictionary = record(id)
	var before := int(previous.get("stars", 0))
	var difficulty := clampi(int(outcome.get("difficulty", 2)), 1, 4)
	if stars <= before and difficulty <= int(previous.get("campaign", 0)): return false
	var old_unlocks := unlocked.duplicate()
	var next := previous.duplicate()
	next.stars = maxi(before, stars); next.campaign = maxi(difficulty, int(previous.get("campaign", 0)))
	levels[str(id)] = next
	_recompute()
	if stars > before:
		var initial: int = pending.stars.get(str(id), {}).get("before", before)
		pending.stars[str(id)] = {"before": initial, "after": stars}
	for stage in unlocked:
		if not stage in old_unlocks and not stage in pending.unlocked: pending.unlocked.append(stage)
	save(); changed.emit(); return true

func consume_changes() -> Dictionary:
	var changes := pending.duplicate(true)
	pending = {"stars": {}, "unlocked": []}
	return changes

func save() -> bool:
	if not save_allowed: return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: _notice("进度已在本次游戏中生效，但无法保存到本地。"); return false
	file.store_string(JSON.stringify({"schema_version": 1, "generation": 1, "content_version": definition.source.commit, "levels": levels, "heroes": heroes, "seen_notifications": seen_notifications}))
	file.flush(); var error := file.get_error(); file.close()
	if error != OK: _notice("进度写入失败，本次游戏仍可继续。"); return false
	# Preserve only a validated previous save; never replace a healthy backup with corruption.
	if _valid(_read(path)):
		if DirAccess.copy_absolute(path, path + ".bak") != OK: _notice("进度备份失败，本次游戏仍可继续。"); return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: _notice("进度保存失败，本次游戏仍可继续。"); return false
	_notice("浏览器未开启本地存储，本次进度可能无法保留。" if OS.has_feature("web") and not OS.is_userfs_persistent() else "")
	return true

func _notice(value: String) -> void:
	notice = value; notice_changed.emit(value)
