extends RefCounted
## Load only selected, implemented heroes; level data and saves stay independent.
static var last_error := ""

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func validate(bundle: Dictionary) -> String:
	for key: String in ["templates","behaviors","dependencies","callbacks","rules","strings"]:
		if not bundle.get(key) is Dictionary:return "缺少英雄字段："+key
	if not bundle.templates.has(bundle.get("id","")):return "缺少英雄模板"
	for owner: String in bundle.dependencies:
		if not bundle.templates.has(owner):return "缺少英雄依赖主体："+owner
		for child: String in bundle.dependencies[owner]:
			if not bundle.templates.has(child):return "缺少英雄依赖："+owner+" -> "+child
	return ""

static func attach(definition: Dictionary, slot: Dictionary) -> bool:
	last_error = ""
	definition.battle_heroes = []
	definition.combat_bundles = []
	var mode: int = int(definition.level.get("mode",1))
	var overrides: Dictionary = definition.layout.get("level_mode_overrides",[{}])[mode-1]
	if overrides.get("locked_hero",definition.layout.get("locked_hero",false)): return true
	var catalog := read_json("res://data/campaign_content.json")
	for id: String in slot.get("heroes",{}).get("selected",[]):
		if id in definition.battle_heroes or not catalog.get("combat_heroes",{}).has(id): continue
		var base: String = "res://data/"+str(catalog.combat_heroes[id].folder)+"/"
		var manifest := read_json(base+"manifest.json")
		var bundle := read_json(base+"definition.json")
		if bundle.get("id","")!=id or manifest.get("schema_version",0)!=1 or bundle.get("source",{}).get("commit","")!=catalog.source.commit:
			last_error="英雄战斗资源无效："+id; return false
		last_error=validate(bundle)
		if not last_error.is_empty():return false
		for path: String in manifest.get("data",[]):
			if read_json(path).is_empty(): last_error="缺少英雄数据："+path; return false
		for path: String in manifest.get("resources",[]):
			if not ResourceLoader.exists(path): last_error="缺少英雄资源："+path; return false
		for key: String in ["templates","behaviors","dependencies","callbacks"]:
			definition[key].merge(bundle[key],false)
		definition.ui.strings.merge(bundle.strings,false)
		definition.hero_rules=bundle.rules.duplicate(true)
		definition.battle_heroes.append(id)
		definition.combat_bundles.append(base)
	return true
