extends Node
## Only application preferences; game progress and save slots are intentionally separate.

signal changed(music_volume: float, sfx_volume: float)
signal notice_changed(message: String)

const DEFAULT_PATH := "user://settings.json"
var music_volume := 1.0
var sfx_volume := 1.0
var last_slot_idx := 1
var data := {}
var notice := ""
var settings_path := DEFAULT_PATH


func initialize(path: String = DEFAULT_PATH) -> void:
	settings_path = path
	music_volume = 1.0
	sfx_volume = 1.0
	last_slot_idx = 1; data = {}
	_set_notice("")
	if FileAccess.file_exists(path):
		var parsed := JSON.new()
		var error := parsed.parse(FileAccess.get_file_as_string(path))
		if error == OK and parsed.data is Dictionary and parsed.data.get("schema_version") == 1:
			data = parsed.data
			music_volume = _volume(parsed.data.get("music_volume"))
			sfx_volume = _volume(parsed.data.get("sfx_volume"))
			var slot: Variant = data.get("last_slot_idx", 1)
			if slot is int or slot is float: last_slot_idx = clampi(int(slot), 1, 3)
		else:
			_set_notice("设置文件无法读取，已恢复默认音量。")
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		_set_notice("浏览器未开启本地存储，本次音量设置可能无法保留。")
	changed.emit(music_volume, sfx_volume)


func set_volumes(music: float, sfx: float) -> void:
	music_volume = _volume(music)
	sfx_volume = _volume(sfx)
	changed.emit(music_volume, sfx_volume)
	save()


func select_slot(id: int) -> void:
	last_slot_idx = clampi(id, 1, 3); save()

func save() -> bool:
	var temporary := settings_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_set_notice("音量已生效，但设置无法保存。请检查本地存储是否可用。")
		return false
	data.merge({"schema_version": 1, "music_volume": music_volume, "sfx_volume": sfx_volume, "last_slot_idx": last_slot_idx}, true)
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, settings_path) != OK:
		_set_notice("音量已生效，但设置无法保存。请检查本地存储是否可用。")
		return false
	if not OS.has_feature("web") or OS.is_userfs_persistent():
		_set_notice("")
	return true


func _volume(value: Variant) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return 1.0


func _set_notice(message: String) -> void:
	if notice != message:
		notice = message
		notice_changed.emit(notice)
