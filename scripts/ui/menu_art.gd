extends RefCounted
## Keep padding around trimmed sprites so layout and button hit boxes use Dove units.


static func texture(catalog: RefCounted, frame_name: String, group: String = "screen_slots") -> AtlasTexture:
	var frame: Dictionary = catalog.get_frame(group, frame_name)
	if frame.is_empty():
		return null
	var result: AtlasTexture = frame.texture
	var pixel_scale: Vector2 = frame.region.size / frame.logical_size
	result.margin = Rect2(frame.trim * pixel_scale, (frame.original_size - frame.logical_size) * pixel_scale)
	return result


static func image(catalog: RefCounted, frame_name: String, at: Vector2, group: String = "screen_slots") -> TextureRect:
	var view := TextureRect.new()
	view.texture = texture(catalog, frame_name, group)
	view.position = at
	view.size = catalog.get_frame(group, frame_name).original_size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


static func button(catalog: RefCounted, prefix: String, at: Vector2, group: String = "screen_slots", pressed_frame: int = 3) -> TextureButton:
	var control := TextureButton.new()
	control.texture_normal = texture(catalog, prefix + "_0001", group)
	control.texture_hover = texture(catalog, prefix + "_0002", group)
	control.texture_pressed = texture(catalog, prefix + "_%04d" % pressed_frame, group)
	control.texture_focused = control.texture_hover
	control.ignore_texture_size = true
	control.stretch_mode = TextureButton.STRETCH_SCALE
	control.position = at
	control.size = catalog.get_frame(group, prefix + "_0001").original_size
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return control
