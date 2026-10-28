extends RefCounted
## Availability and resource identity are independent of saved campaign unlocks.
const CONTENT_PATH := "res://data/campaign_content.json"
const Controller = preload("res://scripts/battle/dove_level_controller.gd")
const Behaviors = preload("res://scripts/battle/dove_behaviors.gd")
static var last_error := ""
static var _content: Dictionary = {}

static func catalog() -> Dictionary:
	# Availability is queried by the map every frame. Keep the immutable catalog
	# in memory; level definitions still load fresh to isolate each battle/mode.
	if _content.is_empty(): _content = read_json(CONTENT_PATH)
	return _content

static func ids() -> Array[int]:
	var result: Array[int] = []
	for key: String in catalog().get("levels", {}): result.append(int(key))
	result.sort()
	return result

static func supports(id: int, mode: int = 1, difficulty: int = 2) -> bool:
	var content := catalog()
	var entry: Dictionary = content.get("levels", {}).get(str(id), {})
	return content.get("schema_version", 0) == 1 and float(mode) in entry.get("modes", []) and float(difficulty) in entry.get("difficulties", [])

static func folder(id: int) -> String:
	var entry: Dictionary = catalog().get("levels", {}).get(str(id), {})
	return "res://data/%s/" % entry.folder if entry.has("folder") else ""

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed := JSON.new()
	return parsed.data if parsed.parse(FileAccess.get_file_as_string(path)) == OK and parsed.data is Dictionary else {}

static func load_definition(id: int, mode: int = 1, difficulty: int = 2) -> Dictionary:
	last_error = ""
	var definition := _load_definition(id, mode, difficulty)
	if definition.is_empty(): last_error = "%d/%d/%d: %s" % [id, mode, difficulty, last_error]
	return definition

static func _load_definition(id: int, mode: int, difficulty: int) -> Dictionary:
	if not supports(id, mode, difficulty): return _fail("该关卡、模式或难度尚未开放。")
	var base := folder(id)
	var manifest := read_json(base + "manifest.json")
	var definition := read_json(base + "definition.json")
	if manifest.get("schema_version", 0) != 1 or not manifest.get("data") is Array or not manifest.get("resources") is Array: return _fail("资源清单缺失或格式不兼容。")
	var identity: Variant = definition.get("level", {})
	if not identity is Dictionary or identity.get("id", 0) != id: return _fail("关卡定义缺失或与所选关卡不匹配。")
	if mode != 1:
		var variant: Dictionary = definition.get("modes", {}).get(str(mode), {})
		if not variant.get("waves") is Dictionary or not variant.get("layout") is Dictionary: return _fail("挑战模式数据缺失。")
		definition.waves = variant.waves.duplicate(true)
		definition.layout = variant.layout.duplicate(true)
		identity.mode = mode
	for path: String in manifest.get("data", []):
		if read_json(path).is_empty(): return _fail("无法读取关卡数据：" + path.get_file())
	for path: String in manifest.get("resources", []):
		if not ResourceLoader.exists(path): return _fail("缺少关卡资源：" + path.get_file())
		if load(path) == null: return _fail("无法加载关卡资源：" + path.get_file())
	if definition.get("templates", {}).is_empty() or definition.get("waves", {}).get("groups", []).is_empty(): return _fail("关卡模板或波次数据不完整。")
	if identity.get("root", "") != base or identity.get("mode", 0) != mode or identity.get("difficulty", 0) != difficulty: return _fail("关卡资源版本或战役身份不匹配。")
	var content := catalog()
	if definition.get("source", {}).get("commit", "") != content.source.commit or manifest.get("source", {}).get("commit", "") != content.source.commit: return _fail("%s: source differs from current Dove catalog" % base)
	var registered: Dictionary = content.levels[str(id)]
	if identity.get("controller", "") != registered.controller: return _fail("%s: controller differs from content registration" % base)
	if Controller.create(identity.controller, content) == null: return _fail("%s: missing or invalid controller '%s'" % [base, identity.controller])
	var error := Behaviors.validate(definition, content)
	if not error.is_empty(): return _fail(error)
	return definition

static func _fail(reason: String) -> Dictionary:
	last_error = reason
	return {}
