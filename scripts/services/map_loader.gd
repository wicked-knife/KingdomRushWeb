extends Node
## Map-only dependencies are loaded in frame-sized batches, outside menu bootstrap.
signal progress_changed(completed: int, total: int, description: String)
const Catalog = preload("res://scripts/dove_asset_catalog.gd")
const MANIFEST := "res://data/map_kr1/manifest.json"
var catalog: RefCounted
var definition := {}
var error_message := ""
var loaded := false

func initialize(manifest_path: String = MANIFEST) -> bool:
	loaded = false; error_message = ""
	var manifest := _read(manifest_path)
	if manifest.get("schema_version", 0) != 1 or not manifest.get("resources") is Array: return _fail("地图资源清单无效")
	catalog = Catalog.new("res://data/map_kr1/catalog.json")
	definition = _read("res://data/map_kr1/definition.json")
	if definition.get("levels", []).size() != 27 or definition.get("animations", []).size() != 124: return _fail("一代地图数据无效")
	if not catalog.is_available() or catalog.load_group("map_kr1").get("frames", {}).is_empty(): return _fail("地图图集目录无效")
	var paths: Array = manifest.resources
	for i in paths.size():
		var path: String = paths[i]
		progress_changed.emit(i, paths.size(), "加载一代大地图")
		await get_tree().process_frame
		if not ResourceLoader.exists(path): return _fail("地图资源缺失：" + path)
		if path.ends_with(".png") and catalog.get_texture(path) == null: return _fail("地图图片无法读取：" + path)
		if not path.ends_with(".png") and load(path) == null: return _fail("地图资源无法读取：" + path)
	progress_changed.emit(paths.size(), paths.size(), "加载完成")
	loaded = true; return true

func _fail(message: String) -> bool:
	error_message = message; return false

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed := JSON.new()
	return parsed.data if parsed.parse(FileAccess.get_file_as_string(path)) == OK and parsed.data is Dictionary else {}

func _exit_tree() -> void:
	if catalog != null: catalog.clear_cache()
	catalog = null; definition.clear()
