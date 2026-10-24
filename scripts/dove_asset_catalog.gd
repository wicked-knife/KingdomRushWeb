class_name DoveAssetCatalog
extends RefCounted
## Lazy access to the installed Dove asset snapshot. No gameplay code is executed.
## Texture regions use physical pixels; logical_size/trim/original_size use Dove units.

const ROOT := "res://assets/kingdom_rush/"
const CATALOG_PATH := ROOT + "catalog.json"

var _catalog: Dictionary = {}
var _groups: Dictionary = {}
var _textures: Dictionary = {}
var _animations: Dictionary = {}
var _exoskeletons: Dictionary = {}
var _static: Dictionary = {}


func _init() -> void:
	_catalog = _read_json(CATALOG_PATH)
	if not _catalog.is_empty() and int(_catalog.get("schema_version", 0)) != 1:
		push_error("Unsupported Dove asset catalog schema")
		_catalog = {}


func is_available() -> bool:
	return not _catalog.is_empty()


func list_groups() -> Array:
	var names: Array = _catalog.get("groups", {}).keys()
	names.sort()
	return names


func load_group(group: String) -> Dictionary:
	if not _groups.has(group):
		var definition: Dictionary = _catalog.get("groups", {}).get(group, {})
		if definition.is_empty():
			push_error("Unknown Dove atlas group: " + group)
			return {}
		_groups[group] = _read_json(str(definition["path"]))
	return _groups[group]


func get_frame(group: String, frame_name: String) -> Dictionary:
	var data: Dictionary = load_group(group)
	if data.is_empty():
		return {}
	var canonical: String = str(data.get("lookup", {}).get(frame_name, frame_name))
	var definition: Dictionary = data.get("frames", {}).get(canonical, {})
	if definition.is_empty():
		push_error("Unknown Dove frame: %s/%s" % [group, frame_name])
		return {}
	var image: Texture2D = get_texture(str(data["texture_directory"]) + str(definition["sheet"]))
	if image == null:
		return {}
	var texture := AtlasTexture.new()
	texture.atlas = image
	texture.region = _rect(definition["region"])
	texture.filter_clip = true
	return {"texture": texture, "name": canonical, "group": group,
		"region": texture.region, "source_region": _rect(definition["source_region"]),
		"logical_size": _vector(definition["logical_size"]),
		"original_size": _vector(definition["original_size"]), "trim": _vector(definition["trim"]),
		"ref_scale": float(definition["ref_scale"])}


func get_texture(path: String) -> Texture2D:
	if not path.begins_with(ROOT):
		push_error("Texture path is outside the Dove asset directory: " + path)
		return null
	if not _textures.has(path):
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			push_error("Failed to load Dove texture: " + path)
			return null
		_textures[path] = texture
	return _textures[path] as Texture2D


func get_animation(animation_name: String) -> Dictionary:
	if _animations.is_empty():
		_animations = _read_json(str(_catalog.get("animations", "")))
	var definition: Dictionary = _animations.get("animations", {}).get(animation_name, {})
	if definition.is_empty():
		push_error("Unknown Dove regular animation: " + animation_name)
		return {}
	var frames: PackedStringArray = []
	for number in definition["frames"]:
		frames.append("%s_%04d" % [definition["prefix"], int(number)])
	return {"fps": float(_animations.get("fps", 30)), "frames": frames}


func get_exoskeleton(exo_name: String) -> Dictionary:
	if not _exoskeletons.has(exo_name):
		var path: String = str(_catalog.get("exoskeletons", {}).get(exo_name, ""))
		if path.is_empty():
			push_error("Unknown Dove composition: " + exo_name)
			return {}
		_exoskeletons[exo_name] = _read_json(path)
	return _exoskeletons[exo_name]


func get_sound(sound_id: String) -> Dictionary:
	var definition: Dictionary = get_static("sounds").get(sound_id, {}).duplicate(true)
	if definition.is_empty():
		push_error("Unknown Dove sound: " + sound_id)
		return {}
	var paths: PackedStringArray = []
	for filename in definition.get("files", []):
		paths.append(str(_catalog["audio_directory"]) + str(filename))
	definition["paths"] = paths
	return definition


func get_static(name: String) -> Dictionary:
	if not _static.has(name):
		var path: String = str(_catalog.get("static", {}).get(name, ""))
		if path.is_empty():
			push_error("Unknown Dove static catalog: " + name)
			return {}
		_static[name] = _read_json(path)
	return _static[name]


func clear_cache() -> void:
	# Existing returned textures remain valid while their callers hold references.
	_groups.clear()
	_textures.clear()
	_animations.clear()
	_exoskeletons.clear()
	_static.clear()


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Missing Dove data file: " + path)
		return {}
	var json := JSON.new()
	var error: Error = json.parse(FileAccess.get_file_as_string(path))
	if error != OK or not json.data is Dictionary:
		push_error("Invalid Dove JSON: %s (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data
