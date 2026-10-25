extends RefCounted
## Three independent campaigns. Audio preferences remain application-wide.
signal changed
signal notice_changed(message: String)
const Progress = preload("res://scripts/services/campaign_progress.gd")
const DEFAULT_ROOT := "user://saves/kr1"
var directory := DEFAULT_ROOT
var legacy := Progress.DEFAULT_PATH
var active_slot := 0
var last_slot := 1
var notice := ""
var sessions := {}
var migration_done := false

func initialize(root_path: String = DEFAULT_ROOT, legacy_path: String = Progress.DEFAULT_PATH) -> void:
	directory = root_path; legacy = legacy_path; sessions.clear(); active_slot = 0; _notice("")
	_ensure_directory(directory)
	var index := _read(directory + "/index.json")
	if index.get("schema_version", 0) != 1: index = _read(directory + "/index.json.bak")
	migration_done = bool(index.get("legacy_migrated", false))
	last_slot = clampi(int(index.get("last_slot", 1)), 1, 3)
	if not migration_done: _migrate()

func slot_path(id: int) -> String:
	return directory + "/slot_%d/campaign.json" % id

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary else {}

func _valid(value: Dictionary) -> bool:
	return value.get("schema_version", 0) == 1 and value.get("generation", 0) == 1 and value.get("levels") is Dictionary

func status(id: int) -> String:
	if id < 1 or id > 3: return "invalid"
	if sessions.has(id): return "used"
	var path := slot_path(id)
	var primary := _read(path)
	if int(primary.get("schema_version", 0)) > 1: return "future"
	if _valid(primary) or _valid(_read(path + ".bak")): return "used"
	return "corrupt" if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") else "empty"

func _load(id: int) -> RefCounted:
	if sessions.has(id): return sessions[id]
	var path := slot_path(id)
	var p := Progress.new()
	if not FileAccess.file_exists(path) and _valid(_read(path + ".bak")):
		p.initialize(path + ".bak"); p.path = path
		p._notice("进度文件缺失，已恢复备份。")
	else: p.initialize(path)
	p.changed.connect(_on_progress_changed)
	p.notice_changed.connect(_notice)
	sessions[id] = p
	return p

func summaries() -> Array:
	var rows := []
	for id in range(1, 4):
		var state := status(id)
		var row := {"id": id, "state": state, "stars": 0, "heroic": 0, "iron": 0, "notice": ""}
		if state == "used":
			var p := _load(id)
			row.stars = p.total_stars(); row.notice = p.notice
			for record: Dictionary in p.levels.values():
				row.heroic += int(int(record.get("heroic", 0)) > 0)
				row.iron += int(int(record.get("iron", 0)) > 0)
		rows.append(row)
	return rows

func select_slot(id: int) -> RefCounted:
	var state := status(id)
	if state not in ["empty", "used"]:
		_notice("存档来自较新版本，无法继续。" if state == "future" else "存档无法读取，请确认后删除该槽位。")
		return null
	_notice("")
	var p := _load(id)
	if state == "empty":
		_ensure_directory(slot_path(id).get_base_dir())
		p.save()
	active_slot = id; last_slot = id; _save_index()
	changed.emit()
	return p

func delete_slot(id: int) -> bool:
	if id < 1 or id > 3: return false
	var folder := slot_path(id).get_base_dir()
	# Rename the complete slot directory atomically so a partial removal cannot
	# leave a backup that resurrects a deleted campaign.
	if DirAccess.dir_exists_absolute(folder):
		var trash := directory + "/deleted_%d_%d" % [id, Time.get_ticks_usec()]
		if DirAccess.rename_absolute(folder, trash) != OK:
			_notice("删除失败，存档已保留。"); return false
		for filename in ["campaign.json", "campaign.json.bak", "campaign.json.tmp"]:
			if FileAccess.file_exists(trash + "/" + filename): DirAccess.remove_absolute(trash + "/" + filename)
		DirAccess.remove_absolute(trash)
	sessions.erase(id)
	if active_slot == id: active_slot = 0
	_notice(""); changed.emit(); return true

func _on_progress_changed() -> void: changed.emit()

func _save_index() -> bool:
	var path := directory + "/index.json"
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null: _notice("存档索引无法保存，本次游戏仍可继续。"); return false
	f.store_string(JSON.stringify({"schema_version": 1, "legacy_migrated": migration_done, "last_slot": last_slot}))
	f.flush(); var error := f.get_error(); f.close()
	if error != OK: _notice("存档索引写入失败，本次游戏仍可继续。"); return false
	if _read(path).get("schema_version", 0) == 1 and DirAccess.copy_absolute(path, path + ".bak") != OK:
		_notice("存档索引备份失败，本次游戏仍可继续。"); return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		_notice("存档索引无法保存，本次游戏仍可继续。"); return false
	return true

func _migrate() -> void:
	var has_legacy := FileAccess.file_exists(legacy) or FileAccess.file_exists(legacy + ".bak")
	if has_legacy and status(1) == "empty":
		var old := _read(legacy)
		if int(old.get("schema_version", 0)) > 1:
			_notice("旧存档来自较新版本，已保留原文件。"); return
		if not _valid(old): old = _read(legacy + ".bak")
		if not _valid(old): _notice("旧存档无法读取，已保留原文件。"); return
		var p := Progress.new()
		p.initialize(legacy if _valid(_read(legacy)) else legacy + ".bak")
		p.path = slot_path(1)
		_ensure_directory(p.path.get_base_dir())
		if not p.save(): _notice("旧进度迁移未能保存，原文件已保留。"); return
	migration_done = true
	if not _save_index(): migration_done = false; return
	# The source remains recoverable, but its old lookup name is retired.
	if has_legacy:
		for suffix in ["", ".bak"]:
			if FileAccess.file_exists(legacy + suffix) and not FileAccess.file_exists(legacy + suffix + ".migrated"):
				DirAccess.rename_absolute(legacy + suffix, legacy + suffix + ".migrated")

func _notice(value: String) -> void:
	notice = value; notice_changed.emit(value)

func _ensure_directory(path: String) -> bool:
	var cursor := path
	while not DirAccess.dir_exists_absolute(cursor):
		if FileAccess.file_exists(cursor) or cursor == cursor.get_base_dir(): return false
		cursor = cursor.get_base_dir()
	return DirAccess.make_dir_recursive_absolute(path) == OK
