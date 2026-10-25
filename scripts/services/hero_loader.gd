extends Node
## Hero-room textures and selection voices are separate from map bootstrap.
const Catalog = preload("res://scripts/dove_asset_catalog.gd")
const MANIFEST := "res://data/heroes/manifest.json"
signal progress_changed(done: int, total: int)
var catalog: RefCounted
var loaded := false
var loading := false
var error_message := ""

func initialize(manifest_path: String = MANIFEST) -> bool:
	if loading: return false
	loading = true; loaded = false; error_message = ""
	if catalog != null: catalog.clear_cache()
	catalog = Catalog.new("res://data/heroes/catalog.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	if not manifest is Dictionary or manifest.get("schema_version", 0) != 1 or not manifest.get("resources") is Array:
		return _fail("英雄资源清单无效")
	var definition_path := "res://data/heroes/definition.json"
	if not FileAccess.file_exists(definition_path): return _fail("英雄目录缺失")
	var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(definition_path))
	if not definition is Dictionary or definition.get("schema_version", 0) != 1 or not definition.get("heroes") is Array or definition.heroes.size() != 79:
		return _fail("英雄目录无效")
	if not catalog.is_available() or catalog.load_group("heroes").get("frames", {}).is_empty(): return _fail("英雄图集目录无效")
	var paths: Array = manifest.resources
	for i in paths.size():
		progress_changed.emit(i, paths.size())
		await get_tree().process_frame
		if not is_inside_tree(): return false
		var path: String = paths[i]
		if not ResourceLoader.exists(path): return _fail("英雄资源缺失：" + path)
		if path.ends_with(".png"):
			if catalog.get_texture(path) == null: return _fail("英雄图片无法读取：" + path)
		elif load(path) == null: return _fail("英雄资源无法读取：" + path)
	loading = false; loaded = true; progress_changed.emit(paths.size(), paths.size()); return true

func _fail(message: String) -> bool:
	error_message = message; loading = false; return false

func _exit_tree() -> void:
	if catalog != null: catalog.clear_cache()
	catalog = null
