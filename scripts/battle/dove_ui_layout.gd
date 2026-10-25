extends RefCounted
## Source UI coordinates are 768-reference units. Image pixels pass through the
## atlas ref_scale and group scale exactly once. Text and hit regions inherit
## the same parent transform; fixed artwork is never stretched to fit content.
var image_scale := 768.0 / 1080.0
var canvas: Control
var fonts: RefCounted
var transform := Transform2D.IDENTITY
var opacity := 1.0
var stack: Array = []
var measurements := {}
var audit: Array = []

func _init(owner_canvas: Control, font_service: RefCounted, reference_height: float = 768.0) -> void:
	canvas = owner_canvas; fonts = font_service; image_scale = reference_height / 1080.0

func begin() -> void:
	transform = Transform2D.IDENTITY; opacity = 1; stack.clear(); audit.clear()

func push(at: Vector2, factor: float = 1.0, alpha: float = 1.0, rotation: float = 0.0) -> void:
	stack.append([transform, opacity])
	transform = transform * Transform2D(rotation, Vector2.ONE * factor, 0, at)
	opacity *= alpha

func pop() -> void:
	var previous: Array = stack.pop_back()
	transform = previous[0]; opacity = previous[1]
	_apply()

func _apply() -> void:
	canvas.draw_set_transform_matrix(Transform2D(0, Vector2.ONE * canvas.zoom, 0, Vector2.ZERO) * transform)

func image_size(id: String) -> Vector2:
	var frame: Dictionary = canvas._frame(id)
	return frame.original_size * float(frame.ref_scale) * image_scale

func image(id: String, at: Vector2 = Vector2.ZERO, anchor: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE, stretch: Vector2 = Vector2.ONE) -> void:
	var frame: Dictionary = canvas._frame(id)
	if frame.is_empty(): return
	_apply()
	var factor: float = frame.ref_scale * image_scale
	var pos: Vector2 = -image_size(id) * anchor + frame.trim * factor
	tint.a *= opacity
	# Negative draw_texture_rect sizes flip texture sampling without preserving
	# the source anchor. Put scale/flip in the local transform instead.
	canvas.draw_set_transform_matrix(Transform2D(0, Vector2.ONE * canvas.zoom, 0, Vector2.ZERO) * transform * Transform2D(0, stretch, 0, at))
	canvas.draw_texture_rect(frame.texture, Rect2(pos, frame.logical_size * factor), false, tint)
	_apply()

func region(rect: Rect2) -> Rect2:
	return transform * rect

func hit(rect: Rect2, action: String, args: Dictionary = {}, enabled: bool = true) -> void:
	canvas.hits.append({"rect": region(rect), "action": action, "args": args, "enabled": enabled})

func label(value: String, rect: Rect2, font_size: float = 18, color: Color = Color("302923"), align: String = "center", vertical: String = "middle", max_lines: int = 0, outline: int = 0, id: String = "", role: String = "body", shadow: Vector2 = Vector2.ZERO, shadow_color: Color = Color("25241e")) -> void:
	var face: Font = fonts.font_for(role)
	var offset: float = fonts.offset_for(role, font_size, vertical)
	var key := str([value, rect.size, font_size, max_lines, align, vertical, role, face.get_instance_id(), offset])
	if not measurements.has(key):
		var paragraph: TextParagraph
		var actual: int = fonts.size_for(role, font_size)
		while true:
			paragraph = TextParagraph.new()
			paragraph.width = rect.size.x
			paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER if align == "center" else (HORIZONTAL_ALIGNMENT_RIGHT if align == "right" else HORIZONTAL_ALIGNMENT_LEFT)
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.add_string(value, face, actual, "zh_CN")
			if (paragraph.get_size().y + 2 * absf(offset) <= rect.size.y + 0.1 and (max_lines == 0 or paragraph.get_line_count() <= max_lines)) or actual <= 6: break
			actual -= 1
		measurements[key] = {"paragraph": paragraph, "font_size": actual}
	var measured: Dictionary = measurements[key]
	var p: TextParagraph = measured.paragraph
	var maximum_width := 0.0
	for line in range(p.get_line_count()): maximum_width = maxf(maximum_width, p.get_line_size(line).x)
	var point := rect.position
	if vertical == "middle": point.y += (rect.size.y - p.get_size().y) / 2
	elif vertical == "middle-caps": point.y += (rect.size.y - p.get_size().y + face.get_descent(measured.font_size)) / 2
	elif vertical == "bottom": point.y += rect.size.y - p.get_size().y
	point.y += offset
	_apply()
	color.a *= opacity
	if shadow != Vector2.ZERO:
		shadow_color.a *= opacity
		p.draw(canvas.get_canvas_item(), point + shadow, shadow_color)
	if outline > 0: p.draw_outline(canvas.get_canvas_item(), point, outline, Color(0.08, 0.07, 0.04, opacity))
	p.draw(canvas.get_canvas_item(), point, color)
	# Store measured geometry, including the glyph area, for native gallery checks.
	audit.append({"id": id if id != "" else value, "text": value, "font_size": measured.font_size, "font_role": role, "font_family": face.get_font_name(),
		"box": region(rect), "extent": Vector2(maximum_width, p.get_size().y), "fits": p.get_size().y + 2 * absf(offset) <= rect.size.y + 0.1 and maximum_width <= rect.size.x + 0.1 and (max_lines == 0 or p.get_line_count() <= max_lines),
		"lines": p.get_line_count()})

func source_label(definition: Dictionary, strings: Dictionary) -> void:
	var colors := {"black": Color.BLACK, "white": Color.WHITE, "gray": Color("302923"), "red": Color("d83712"), "dark_red": Color("b73f0d"), "blue": Color("007cb2")}
	var pos := Vector2(definition.pos.x, definition.pos.y)
	var anchor: Dictionary = definition.get("anchor", {})
	pos -= Vector2(anchor.get("x", 0), anchor.get("y", 0))
	# Dove KView applies G.rotate(-r), while Transform2D takes a native angle.
	push(pos, 1, 1, -float(definition.get("r", 0)))
	label(strings.get(definition.text, definition.text), Rect2(Vector2.ZERO, Vector2(definition.size.x, definition.size.y)),
		int(definition.get("font_size", 18)), colors.get(definition.get("color", ""), Color("11140c")),
		definition.get("text_align", "left"), definition.get("vertical_align", "top"), int(definition.get("fit_lines", 0)), 0, definition.text, definition.get("font_name", "body"))
	pop()

func display_label(value: String, rect: Rect2, font_size: float, color: Color, role: String, id: String, outline: int = 0, outline_color: Color = Color("272519")) -> void:
	# Source buttons and tabs use short line boxes, not paragraph-height fitting.
	# Measure the actual shaped glyphs (including explicit fallback faces) so the
	# visible caption stays centered and full-sized inside its painted content area.
	var face: Font = fonts.font_for(role)
	var key := str(["display", value, rect.size, font_size, role, face.get_instance_id(), outline])
	if not measurements.has(key):
		var actual: int = fonts.size_for(role, font_size)
		while true:
			var line := TextLine.new()
			line.add_string(value, face, actual, "zh_CN")
			var ink: Rect2 = fonts.ink_bounds(line.get_rid())
			var extent := ink.size + Vector2.ONE * outline * 2
			if (extent.x <= rect.size.x and extent.y <= rect.size.y) or actual <= 6:
				measurements[key] = {"line": line, "ink": ink, "font_size": actual, "extent": extent}
				break
			actual -= 1
	var measured: Dictionary = measurements[key]
	var point: Vector2 = rect.position + (rect.size - measured.ink.size) / 2 - measured.ink.position
	_apply()
	color.a *= opacity; outline_color.a *= opacity
	# Bitmap outline sizes address the oversampled font cache. Convert the
	# design-unit thickness too, otherwise a 3 px stroke becomes a broken 1 px edge.
	if outline > 0:
		var raster_outline := roundi(outline * maxf(1, face.oversampling))
		measured.line.draw_outline(canvas.get_canvas_item(), point, raster_outline, outline_color)
	measured.line.draw(canvas.get_canvas_item(), point, color)
	audit.append({"id": id, "text": value, "font_size": measured.font_size, "font_role": role, "font_family": face.get_font_name(),
		"box": region(rect), "extent": measured.extent, "fits": measured.extent.x <= rect.size.x + 0.1 and measured.extent.y <= rect.size.y + 0.1, "lines": 1})

func button(id: String, at: Vector2, caption: String, action: String, args: Dictionary = {}, enabled: bool = true, style: String = "options", role: String = "button") -> Rect2:
	var dimensions := image_size(id)
	var rect := Rect2(at, dimensions)
	var over: bool = canvas.hovered == action + str(args)
	var image_id := id.replace("_0001", "_0002") if over and enabled else id
	image(image_id, at, Vector2.ZERO, Color.WHITE if enabled else Color(0.5, 0.5, 0.5))
	var content := rect.grow_individual(-12, -6, -12, -8)
	var fs := 19
	if style == "notice": content = Rect2(at + Vector2(20, 14), Vector2(dimensions.x - 40, 34)); fs = 20
	if style == "gotcha": content = Rect2(at + Vector2(20, 0), Vector2(dimensions.x - 40, 26)); fs = 20
	label(caption, content, fs, Color("fffec8"), "center", "middle", 1, 1, "button:" + action, role)
	hit(rect, action, args, enabled)
	return rect
