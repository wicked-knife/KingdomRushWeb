extends RefCounted
## Three shared Dove slots; application settings remain separate.
signal changed
signal notice_changed(message: String)
const Progress = preload("res://scripts/services/campaign_progress.gd")
const DEFAULT_ROOT := "user://saves"
var directory := DEFAULT_ROOT
var active_slot := 0
var preferences: Node
var last_slot: int:
	get: return preferences.last_slot_idx if preferences != null else 1
var notice := ""
var sessions := {}
var max_stars := 0

func initialize(root_path: String = DEFAULT_ROOT, settings: Node = null) -> void:
	directory = root_path; preferences = settings; sessions.clear(); active_slot = 0; _notice("")
	max_stars = int(Progress.read_json(Progress.SLOT_DEFINITION).max_stars)
	_ensure_directory(directory)

func slot_path(id: int) -> String: return directory + "/slot_%d.json" % id

func status(id: int) -> String:
	if id < 1 or id > 3: return "invalid"
	if sessions.has(id): return "used"
	var path := slot_path(id); var primary := Progress.read_json(path)
	if int(primary.get("schema_version", 0)) > 1: return "future"
	if Progress.valid(primary) or Progress.valid(Progress.read_json(path + ".bak")): return "used"
	return "corrupt" if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") else "empty"

func _load(id: int) -> RefCounted:
	if sessions.has(id): return sessions[id]
	var p := Progress.new(); p.initialize(slot_path(id))
	p.changed.connect(_on_progress_changed); p.notice_changed.connect(_notice)
	sessions[id] = p; return p

func summaries() -> Array:
	var rows := []
	for id in range(1, 4):
		var state := status(id)
		var row := {"id": id, "state": state, "stars": 0, "max_stars": max_stars, "heroic": 0, "iron": 0, "notice": ""}
		if state == "used":
			var p := _load(id); row.merge(p.summary(), true); row.notice = p.notice
		rows.append(row)
	return rows

func select_slot(id: int) -> RefCounted:
	var state := status(id)
	if state not in ["empty", "used"]:
		_notice("存档来自较新版本，无法继续。" if state == "future" else "存档无法读取，请确认后删除该槽位。"); return null
	_notice("")
	var p := _load(id)
	if state == "empty": p.save()
	active_slot = id
	if preferences != null: preferences.select_slot(id)
	changed.emit(); return p

func delete_slot(id: int) -> bool:
	if id < 1 or id > 3: return false
	var trash := directory + "/deleted_%d_%d" % [id, Time.get_ticks_usec()]
	if not _ensure_directory(trash): _notice("删除失败，存档已保留。"); return false
	var moved := []
	for suffix in ["", ".bak", ".tmp"]:
		var source: String = slot_path(id) + suffix
		if not FileAccess.file_exists(source): continue
		var destination: String = trash + "/" + source.get_file()
		if DirAccess.rename_absolute(source, destination) != OK:
			for pair: Array in moved: DirAccess.rename_absolute(pair[1], pair[0])
			DirAccess.remove_absolute(trash); _notice("删除失败，存档已保留。"); return false
		moved.append([source, destination])
	# All recoverable files are retired before the session becomes empty.
	sessions.erase(id)
	if active_slot == id: active_slot = 0
	for pair: Array in moved: DirAccess.remove_absolute(pair[1])
	DirAccess.remove_absolute(trash)
	_notice(""); changed.emit(); return true

func _notice(value: String) -> void:
	notice = value; notice_changed.emit(value)

func _on_progress_changed() -> void: changed.emit()

func _ensure_directory(path: String) -> bool:
	var cursor := path
	while not DirAccess.dir_exists_absolute(cursor):
		if FileAccess.file_exists(cursor) or cursor == cursor.get_base_dir(): return false
		cursor = cursor.get_base_dir()
	return DirAccess.make_dir_recursive_absolute(path) == OK
