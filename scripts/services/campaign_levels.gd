extends RefCounted
## Availability and resource identity are independent of saved campaign unlocks.
const IDS := [1, 2, 3, 4, 5]
static var last_error := ""

static func supports(id: int, mode: int = 1, difficulty: int = 2) -> bool:
	return id in IDS and mode in [1, 2, 3] and difficulty == 2

static func folder(id: int) -> String:
	return "res://data/level%02d/" % id

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed := JSON.new()
	return parsed.data if parsed.parse(FileAccess.get_file_as_string(path)) == OK and parsed.data is Dictionary else {}

static func load_definition(id: int, mode: int = 1, difficulty: int = 2) -> Dictionary:
	last_error = ""
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
	return definition

static func _fail(reason: String) -> Dictionary:
	last_error = reason
	return {}
