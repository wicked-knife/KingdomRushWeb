extends RefCounted
## Dove font aliases, locale adjustments and explicit portable glyph fallbacks.
const BASE := "res://assets/kingdom_rush/all-desktop/fonts/"
const CONFIG := "res://assets/kingdom_rush/data/fonts.json"
const FILES := ["msyh.ttc", "msyhbd.ttc", "JIMOJW.ttf", "Comic Book Italic.ttf", "TOONISH.ttf", "NotoSansCJKkr-Regular.otf"]
var faces := {}
var roles := {}

func initialize(resources: Dictionary) -> void:
	for filename: String in FILES:
		var face: FontFile = resources[BASE + filename].duplicate()
		face.oversampling = 3.0
		face.allow_system_fallback = false
		faces[filename.get_basename()] = face
	faces.msyh.fallbacks = [faces["NotoSansCJKkr-Regular"]]
	for name: String in faces:
		if name not in ["msyh", "NotoSansCJKkr-Regular"]: faces[name].fallbacks = [faces.msyh]
	var config: Dictionary = resources[CONFIG]
	for group in ["global", "default", "zh-Hans"]:
		for entry: Array in config[group]:
			roles[entry[0]] = {"face": entry[1], "adjust": entry[2] if entry.size() > 2 else {}}

func font_for(role: String = "body") -> Font:
	return faces[roles.get(role, {"face": "msyh"}).face]

func size_for(role: String, source_size: float) -> int:
	return maxi(6, roundi(source_size * float(roles.get(role, {}).get("adjust", {}).get("size", 1))))

func offset_for(role: String, source_size: float, vertical: String) -> float:
	var adjust: Dictionary = roles.get(role, {}).get("adjust", {})
	var scale_value := float(adjust.get("size", 1))
	if not adjust.has(vertical): return 0
	if vertical == "top": return (0.5 * (1 - scale_value) + float(adjust.top) * scale_value) * source_size
	if vertical == "bottom":
		var face := font_for(role)
		var actual := size_for(role, source_size)
		return (-face.get_descent(actual) / maxf(1, face.get_height(actual)) * (scale_value - 1) + float(adjust.bottom)) * source_size
	return float(adjust[vertical]) * source_size * scale_value

func ink_bounds(shaped: RID) -> Rect2:
	# Glyph bearings include the font's internal leading. Compact artwork labels
	# must align their visible ink, rather than shrink to fit that invisible space.
	var server := TextServerManager.get_primary_interface()
	var cursor := 0.0
	var bounds := Rect2()
	var found := false
	for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
		for repeat_index in range(int(glyph.repeat)):
			if glyph.font_rid.is_valid():
				var size_key := Vector2i(int(glyph.font_size), 0)
				var dimensions := server.font_get_glyph_size(glyph.font_rid, size_key, int(glyph.index))
				if dimensions.x > 0 and dimensions.y > 0:
					var bearing := server.font_get_glyph_offset(glyph.font_rid, size_key, int(glyph.index))
					var ink := Rect2(Vector2(cursor, 0) + glyph.offset + bearing, dimensions)
					bounds = bounds.merge(ink) if found else ink
					found = true
			cursor += float(glyph.advance)
	# TextLine.draw takes the line's top edge, whereas glyph bearings use its baseline.
	bounds.position.y += server.shaped_text_get_ascent(shaped)
	return bounds
