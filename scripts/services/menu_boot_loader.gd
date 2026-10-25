extends Node
## Frame-budgeted, local bootstrap. Never enumerates or preloads gameplay content.

signal progress_changed(completed: int, total: int, description: String)
signal font_loaded(font: Font)
signal completed
signal failed(message: String)

const Catalog = preload("res://scripts/dove_asset_catalog.gd")
const MANIFEST_PATH := "res://data/menu_manifest.json"
var fonts: RefCounted
var catalog: RefCounted
var manifest: Dictionary = {}
var resources: Dictionary = {}
var locale: Dictionary = {}
var state := "idle"
var error_message := ""


func initialize(manifest_path: String = MANIFEST_PATH) -> void:
	if state == "loading":
		return
	state = "loading"
	error_message = ""
	resources.clear()
	locale.clear()
	catalog = null
	progress_changed.emit(0, 1, "Preparing...")
	await get_tree().process_frame
	manifest = _read_dictionary(manifest_path)
	if manifest.is_empty() or manifest.get("schema_version") != 1:
		_fail("Invalid menu manifest: " + manifest_path)
		return
	var tasks: Array[Dictionary] = [
		{"path": manifest.get("font", ""), "kind": "font", "label": "Loading font..."},
		{"path": manifest.get("catalog", ""), "kind": "json", "label": "校验资源目录"},
		{"path": manifest.get("font_roles", ""), "kind": "json", "label": "加载字体样式"},
		{"path": manifest.get("locale", ""), "kind": "json", "label": "加载中文文案"},
		{"path": manifest.get("sounds", ""), "kind": "json", "label": "加载声音配置"},
		{"path": manifest.get("background", ""), "kind": "texture", "label": "加载主菜单背景"}
	]
	for font_path: String in manifest.get("fonts", []):
		if font_path != manifest.font: tasks.append({"path": font_path, "kind": "font", "label": "加载原版字体"})
	for group: String in manifest.get("atlases", {}):
		tasks.append({"path": manifest.atlases[group], "kind": "json", "label": "加载界面图集"})
	for path: String in manifest.get("textures", []):
		tasks.append({"path": path, "kind": "texture", "label": "加载首页画面"})
	for sound: String in manifest.get("audio", {}):
		tasks.append({"path": manifest.audio[sound], "kind": "audio", "label": "加载音乐与音效"})
	for index in tasks.size():
		var task: Dictionary = tasks[index]
		var path: String = task.path
		progress_changed.emit(index, tasks.size() + 1, task.label)
		await get_tree().process_frame
		var resource: Variant
		if task.kind == "json":
			resource = _read_dictionary(path)
			if resource.is_empty():
				_fail("Invalid or missing data: " + path)
				return
		else:
			if not ResourceLoader.exists(path):
				_fail("Missing resource: " + path)
				return
			resource = load(path)
			var valid: bool = (task.kind == "font" and resource is Font) or (task.kind == "texture" and resource is Texture2D) or (task.kind == "audio" and resource is AudioStream)
			if not valid:
				_fail("Unable to load resource: " + path)
				return
		resources[path] = resource
		if task.kind == "font" and path == manifest.font:
			font_loaded.emit(resource)
		elif path == manifest.locale:
			locale = resource
	# Validate only this screen's dependencies, including aliases and trimmed frame metadata.
	var catalog_data: Dictionary = resources[manifest.catalog]
	if catalog_data.get("schema_version") != 1 or not catalog_data.get("groups") is Dictionary:
		_fail("资源目录版本无效。")
		return
	for group: String in manifest.get("frames", {}):
		if catalog_data.groups.get(group, {}).get("path", "") != manifest.atlases.get(group, ""):
			_fail("图集目录不匹配：" + group)
			return
		var atlas: Dictionary = resources.get(manifest.atlases[group], {})
		for frame_name: String in manifest.frames[group]:
			var canonical: String = atlas.get("lookup", {}).get(frame_name, frame_name)
			var frame: Dictionary = atlas.get("frames", {}).get(canonical, {})
			if not _valid_frame(frame, atlas):
				_fail("界面帧缺失或无效：%s/%s" % [group, frame_name])
				return
	catalog = Catalog.new()
	if not catalog.is_available():
		_fail("资源目录不可用。")
		return
	# Prime the existing catalog with the resources already loaded by this bootstrap.
	for path: String in manifest.textures:
		catalog.get_texture(path)
	progress_changed.emit(tasks.size() + 1, tasks.size() + 1, "加载完成")
	await get_tree().process_frame
	fonts = preload("res://scripts/services/dove_fonts.gd").new()
	fonts.initialize(resources)
	state = "ready"
	completed.emit()


func _valid_frame(frame: Dictionary, atlas: Dictionary) -> bool:
	for field: String in ["region", "logical_size", "original_size", "trim"]:
		if not frame.get(field) is Array or frame[field].size() != (4 if field == "region" else 2):
			return false
	var texture: Texture2D = resources.get(str(atlas.get("texture_directory", "")) + str(frame.get("sheet", "")))
	if texture == null:
		return false
	var region: Array = frame.region
	return float(region[0]) >= 0 and float(region[1]) >= 0 and float(region[2]) > 0 and float(region[3]) > 0 and float(region[0]) + float(region[2]) <= texture.get_width() and float(region[1]) + float(region[3]) <= texture.get_height()


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed := JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(path)) != OK or not parsed.data is Dictionary:
		return {}
	return parsed.data


func _fail(message: String) -> void:
	state = "failed"
	error_message = message
	failed.emit(message)
