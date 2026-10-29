extends RefCounted
## Frozen arithmetic descriptors; no Expression/eval or executable source text.
const OLD := Color8(255, 100, 100)
const NEW := Color8(100, 255, 100)
const ARROW := Color8(200, 200, 150)
const INK := Color8(240, 230, 185)

static func validate(data: Dictionary) -> String:
	for notice: Dictionary in data.ui.notifications.values():
		var prefixes: Array = [notice.prefix] if notice.get("layout", "") == "N_TOWER" else notice.get("prefixes", []) if notice.get("layout", "") == "N_TOWER_2" else []
		for prefix: String in prefixes:
			for suffix in ["_NAME", "_EXTRA"]:
				var key: String = prefix+suffix
				if data.ui.strings.get(key, "") == "" or data.ui.strings.get(key,key) == key: return "missing tower notification text "+key
		var subtitles: Array=[notice.sub] if notice.has("sub") else notice.get("subs",[])
		for key: String in subtitles:
			if data.ui.strings.get(key,"")=="" or data.ui.strings.get(key,key)==key:return "missing tower notification subtitle "+key
	for items: Array in data.ui.tower_menus.values():
		for item: Dictionary in items:
			if item.has("tt_list") and data.ui.get("power_previews",{}).get(item.action_arg,[]).size() != item.tt_list.size(): return "missing power preview "+str(item.action_arg)
	for power: String in data.ui.get("power_previews",{}):
		var rows: Array=data.ui.power_previews[power]
		for level in rows.size():
			var row: Dictionary=rows[level]
			if row.get("title","")=="" or not row.get("tokens") is Array:return "invalid power preview "+power
			for token in row.tokens:
				if token is String:
					if token.contains("%$"):return "unexpanded power preview "+power
					continue
				if not token is Dictionary or not token.get("percent") is bool:return "invalid power token "+power
				var result:=checked(token.get("expression"),data.templates,{"level":level+1,"tdmg":1.0,"tcd":1.0})
				if not result.has("value") or not (result.value is float or result.value is int) or not is_finite(float(result.value)):return "invalid power preview dependency "+power
	return ""

static func checked(node: Variant, templates: Dictionary, context: Dictionary, depth: int=0) -> Dictionary:
	if depth>32 or not node is Array or node.is_empty():return {}
	var op: String=str(node[0])
	if node.size()==2:
		if op=="value" and (node[1] is String or node[1] is float or node[1] is int):return {"value":node[1]}
		if op=="context" and context.has(node[1]):return {"value":context[node[1]]}
		if op=="template" and templates.has(node[1]):return {"value":templates[node[1]]}
	if not op in ["field","index","negate","+","-","*","/"] or node.size()!=(2 if op=="negate" else 3):return {}
	var left:=checked(node[1],templates,context,depth+1)
	if not left.has("value"):return {}
	var a: Variant=left.value
	if op=="field":
		return {"value":a[node[2]]} if a is Dictionary and node[2] is String and not node[2].begins_with("_") and a.has(node[2]) else {}
	if op=="negate":return {"value":-float(a)} if a is float or a is int else {}
	var right:=checked(node[2],templates,context,depth+1)
	if not right.has("value"):return {}
	var b: Variant=right.value
	if op=="index":return {"value":a[int(b)-1]} if a is Array and (b is int or b is float) and float(b)==int(b) and int(b)>0 and int(b)<=a.size() else {}
	if not (a is float or a is int) or not (b is float or b is int):return {}
	match op:
		"+":return {"value":float(a)+float(b)}
		"-":return {"value":float(a)-float(b)}
		"*":return {"value":float(a)*float(b)}
		"/":return {"value":float(a)/float(b)} if float(b)!=0 else {}
	return {}

static func evaluate(node: Array, templates: Dictionary, context: Dictionary) -> Variant:
	match str(node[0]):
		"value": return node[1]
		"context": return context[node[1]]
		"template": return templates[node[1]]
		"field": return evaluate(node[1], templates, context)[node[2]]
		"index": return evaluate(node[1], templates, context)[int(evaluate(node[2], templates, context)) - 1]
		"negate": return -float(evaluate(node[1], templates, context))
		"+": return float(evaluate(node[1], templates, context)) + float(evaluate(node[2], templates, context))
		"-": return float(evaluate(node[1], templates, context)) - float(evaluate(node[2], templates, context))
		"*": return float(evaluate(node[1], templates, context)) * float(evaluate(node[2], templates, context))
		"/": return float(evaluate(node[1], templates, context)) / float(evaluate(node[2], templates, context))
	assert(false, "Unsupported frozen tooltip node")
	return 0.0

static func number(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func description(sim, tower: Dictionary, power: String, level: int) -> String:
	var rows: Array = sim.data.ui.get("power_previews", {}).get(power, [])
	if rows.is_empty(): return sim.data.ui.power_descriptions[power][level - 1]
	var context := {"level":level, "tdmg":sim.attack_factor(tower), "tcd":float(tower.get("cooldown_factor", sim.tower_template(tower).tower.cooldown_factor))}
	var result := ""
	for token in rows[level - 1].tokens:
		if token is String: result += token
		else:
			var value := float(evaluate(token.expression, sim.templates, context))
			result += number(value * (100 if token.percent else 1)) + ("%" if token.percent else "")
	return result

static func preview(sim, tower: Dictionary, power: String) -> Dictionary:
	if not tower.get("powers", {}).has(power): return {}
	var current := int(tower.powers[power])
	var maximum := int(sim.tower_template(tower).powers[power].max_level)
	var next := mini(current + 1, maximum)
	var rows: Array = sim.data.ui.get("power_previews", {}).get(power, [])
	var title: String = rows[next - 1].title if not rows.is_empty() else power
	var text := description(sim, tower, power, next)
	var old := description(sim, tower, power, current) if current > 0 and current < maximum else ""
	return {"title":title,"level":current,"next_level":next,"maxed":current >= maximum,"text":text,"current_text":old,"runs":diff(old, text)}

static func diff(old: String, next: String) -> Array:
	var pattern := RegEx.create_from_string("[0-9]+(?:\\.[0-9]+)?")
	var before := pattern.search_all(old)
	var after := pattern.search_all(next)
	var runs: Array = []; var cursor := 0
	for i in after.size():
		var item: RegExMatch = after[i]
		if item.get_start() > cursor: runs.append({"text":next.substr(cursor,item.get_start()-cursor),"color":INK})
		if i < before.size() and before[i].get_string() != item.get_string():
			runs.append({"text":before[i].get_string(),"color":OLD}); runs.append({"text":"→","color":ARROW})
		runs.append({"text":item.get_string(),"color":NEW}); cursor=item.get_end()
	if cursor < next.length(): runs.append({"text":next.substr(cursor),"color":INK})
	return runs
