extends Control
## Map camera and input. UI and map use the same inverse transforms for drawing and hits.
signal battle_requested(level_id: int, mode: int, difficulty: int)
signal returned_to_menu
const Layout = preload("res://scripts/battle/dove_ui_layout.gd")
const Animations = preload("res://scripts/map/map_animations.gd")
const Interface = preload("res://scripts/map/map_interface.gd")
const HeroRoom = preload("res://scripts/map/hero_room.gd")
const FlagAnimation = preload("res://scripts/map/dove_map_flag.gd")
var hero_room: Control
var upgrades_room: Control
var catalog: RefCounted
var progress: RefCounted
var definition: Dictionary
var animation_player: RefCounted
var interface: RefCounted
var paint: RefCounted
var fonts: RefCounted
var font: Font
var audio: Node
var settings: Node
var zoom := 1.0
var view_size := Vector2(1920, 1080)
var magnification := 1.0
var camera_scale := 1.0
var camera_offset := Vector2.ZERO
var pointer := Vector2(-1000, -1000)
var hits: Array = []
var hovered := ""
var frames := {}
var overlay := ""
var selected_level := 1
var mode := 1
var message := ""
var message_until := 0.0
var touches := {}
var touch_start := Vector2.ZERO
var touch_moved := false
var suppress_mouse_until := 0
var volume_drag := {}
var changes := {}
var change_times := {}
var fx: Array[AudioStreamPlayer] = []
var sounds := {}
var announced := {}
var flag_states := {}

func initialize(loader: Node, boot: Node, sound: Node, preferences: Node, campaign: RefCounted, camera: Dictionary = {}) -> void:
	name = "CampaignMapKR1"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	catalog = loader.catalog; definition = loader.definition.duplicate(true)
	fonts = boot.fonts
	font = fonts.font_for("body")
	audio = sound; settings = preferences; progress = campaign
	paint = Layout.new(self, fonts, 1080)
	interface = Interface.new(self)
	animation_player = Animations.new(definition.animations)
	changes = progress.enter_map()
	for id in changes.get("unlocked", []):
		var duration := 0.0
		for deco: Dictionary in definition.decos:
			if int(deco.get("trigger_level", 0)) == int(id): duration = (int(deco.animations.to) - int(deco.animations.from) + 1) / 30.0
		change_times[int(id)] = {"road": 1.2, "flag": 1.2 + duration}
	for i in range(4):
		var player := AudioStreamPlayer.new(); player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = "SFX"; add_child(player); fx.append(player)
	_refresh_size()
	magnification = clampf(float(camera.get("magnification", 1)), 1, 3)
	camera_scale = maxf(view_size.x / 1920.0, 1.0) * magnification
	# Dove starts at the left edge. Centering the whole map clips the first flag's
	# start balloon in 4:3 windows, even though the flag itself remains visible.
	var center: Vector2 = camera.get("center", Vector2(view_size.x / (2 * camera_scale), 540))
	if not changes.get("unlocked", []).is_empty():
		var id := int(changes.unlocked[0])
		for stage: Dictionary in definition.levels:
			if int(stage.id) == id: center = Animations.vec(stage.flag.pos)
	camera_offset = view_size / 2 - center * camera_scale; _clamp_camera()
	if camera.is_empty() and changes.get("unlocked", []).is_empty():
		var latest := 1
		for id in progress.unlocked:
			if int(id) < 1000: latest = maxi(latest, int(id))
		for stage: Dictionary in definition.levels:
			if int(stage.id) == latest:
				var point := world_to_screen(Animations.vec(stage.flag.pos))
				if point.x < 100 or point.x > view_size.x - 100:
					camera_offset.x = view_size.x / 2 - float(stage.flag.pos.x) * camera_scale
				_clamp_camera()
	var music: Dictionary = catalog.get_sound("MusicMap1")
	audio.play_music(load(music.paths[0]), float(music.get("gain", 1)))
	queue_redraw()

func _refresh_size() -> void:
	if size.y <= 0: return
	var center := screen_to_world(view_size / 2)
	zoom = size.y / 1080.0; view_size = size / zoom
	camera_scale = maxf(view_size.x / 1920.0, 1.0) * magnification
	camera_offset = view_size / 2 - center * camera_scale
	_clamp_camera()

func snapshot() -> Dictionary: return {"center": screen_to_world(view_size / 2), "magnification": magnification}
func screen_to_world(point: Vector2) -> Vector2: return (point - camera_offset) / camera_scale
func world_to_screen(point: Vector2) -> Vector2: return point * camera_scale + camera_offset
func _clamp_camera() -> void:
	var limit := view_size - Vector2(1920, 1080) * camera_scale
	camera_offset.x = clampf(camera_offset.x, minf(limit.x, 0), 0)
	camera_offset.y = clampf(camera_offset.y, minf(limit.y, 0), 0)

func set_map_zoom(value: float, anchor: Vector2) -> void:
	if overlay != "": return
	var before := screen_to_world(anchor)
	magnification = clampf(value, 1, 3)
	camera_scale = maxf(view_size.x / 1920.0, 1.0) * magnification
	camera_offset = anchor - before * camera_scale; _clamp_camera(); queue_redraw()
	hits.clear()

func pan(delta: Vector2) -> void:
	if overlay != "": return
	var previous := camera_offset
	camera_offset += delta; _clamp_camera(); queue_redraw()
	if camera_offset != previous: hits.clear()

func _process(delta: float) -> void:
	if animation_player == null: return
	if not is_equal_approx(size.y / zoom, 1080) or not is_equal_approx(size.x / zoom, view_size.x): _refresh_size()
	animation_player.advance(delta)
	for state: RefCounted in flag_states.values(): state.advance(delta)
	if overlay == "" and touches.is_empty() and volume_drag.is_empty():
		var direction := Vector2.ZERO
		if Rect2(Vector2.ZERO, view_size).has_point(pointer):
			if pointer.x < 100: direction.x = 1
			elif pointer.x > view_size.x - 100: direction.x = -1
			if pointer.y < 100: direction.y = 1
			elif pointer.y > view_size.y - 100: direction.y = -1
		pan(direction * 350 * delta)
	for id in change_times:
		if animation_player.time >= change_times[id].road and not announced.has("road" + str(id)):
			announced["road" + str(id)] = true; _sound("GuimapNewRoad")
		if animation_player.time >= change_times[id].flag and not announced.has("flag" + str(id)):
			announced["flag" + str(id)] = true; _sound("GUIMapNewFlah")
	for id in changes.get("stars", {}):
		var delta_stars: int = int(changes.stars[id].after) - int(changes.stars[id].before)
		for star in delta_stars:
			var key := "star%s:%d" % [id, star]
			if animation_player.time >= 0.3 + star * 0.25 and not announced.has(key): announced[key] = true; _sound("GUIWinStars")
	for kind: String in ["heroic", "iron"]:
		for id in changes.get(kind, []):
			var key := kind + str(id)
			if animation_player.time >= 0.5 and not announced.has(key): announced[key] = true; _sound("GUIWinStars")
	queue_redraw()

func _frame(id: String) -> Dictionary:
	if not frames.has(id): frames[id] = catalog.get_frame("map_kr1", id)
	return frames[id]

func _draw() -> void:
	if paint == null: return
	hits.clear(); paint.begin()
	paint.push(camera_offset, camera_scale)
	paint.image("map_background_kr1")
	for layer in range(1, 4):
		for item: Dictionary in animation_player.items(layer):
			var dimensions: Vector2 = paint.image_size(item.image)
			var anchor: Vector2 = Animations.vec(item.anchor) / dimensions if not item.anchor.is_empty() else Vector2(0.5, 0.5)
			paint.image(item.image, item.pos, anchor, Color(1, 1, 1, item.alpha), item.scale)
		for deco: Dictionary in definition.decos:
			if int(deco.layer) != layer: continue
			var image: String = deco.image
			if deco.has("trigger_level"):
				var id := int(deco.trigger_level)
				if not progress.is_unlocked(id): continue
				if change_times.has(id):
					var elapsed: float = animation_player.time - float(change_times[id].road)
					if elapsed < 0: continue
					image = "%s_%04d" % [deco.animations.prefix, mini(int(deco.animations.to), int(deco.animations.from) + int(elapsed * 30))]
			paint.image(image, Animations.vec(deco.pos), Vector2(0.5, 0.5))
		if layer == 2:
			for stage: Dictionary in definition.levels:
				if progress.is_unlocked(int(stage.id)): _flag(stage)
	if not progress.record(1).has(1):
		paint.push(Vector2(292, 775), 0.98 + sin(animation_player.time * 5) * 0.02)
		paint.image("mapBalloon_starthere_notxt", Vector2.ZERO, Vector2(0.5, 1))
		paint.label("从这里开始！", Rect2(-82, -60, 164, 32), 18, Color("2e2927"), "center", "middle", 1)
		paint.pop()
	paint.pop()
	paint.image("map_vignette_small", Vector2(-2, -2), Vector2.ZERO, Color.WHITE, view_size * 1.02 / Vector2(400, 225))
	if overlay != "": hits.clear()
	interface.draw()
	_refresh_hover()
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _flag(stage: Dictionary) -> void:
	var id := int(stage.id)
	var born: float = float(change_times.get(id, {}).get("flag", -10))
	var elapsed: float = animation_player.time - born
	if elapsed < 0: return
	var stars: int = int(progress.record(id).get("stars", 0))
	if not flag_states.has(id): flag_states[id] = FlagAnimation.new(stars > 0)
	var state: RefCounted = flag_states[id]
	state.completed = stars > 0
	state.iron = progress.record(id).has(3)
	state.set_hovered(hovered == "level" + str({"id": id}))
	var frame: String = state.frame()
	if born >= 0 and elapsed < 0.8: frame = "map_flag_%04d" % (1 + mini(23, int(elapsed * 30)))
	if changes.get("stars", {}).has(str(id)) and animation_player.time >= 0.3 and animation_player.time < 0.3 + 25.0 / 30.0:
		frame = "map_flag_%04d" % (65 + mini(24, int((animation_player.time - 0.3) * 30)))
	var at := Animations.vec(stage.flag.pos)
	paint.push(at - Vector2(44, 60))
	if progress.record(id).has(2) and (not id in changes.get("heroic", []) or animation_player.time >= 0.5):
		var wing_frame := clampi(1 + int((animation_player.time - 0.5) * 30), 1, 15) if id in changes.get("heroic", []) else 15
		var wing := "map_flag_heroic_%04d" % wing_frame
		paint.image(wing, Vector2(41, 60), Vector2(0.5, 0.5))
	if id in changes.get("iron", []) and animation_player.time < 4.5:
		frame = "map_flag_%04d" % (clampi(135 + int((animation_player.time - 0.5) * 30), 135, 150) if animation_player.time >= 0.5 else 134)
	if state.hovered: frame = state.frame()
	paint.image(frame)
	var visible_stars := stars
	if changes.get("stars", {}).has(str(id)):
		var change: Dictionary = changes.stars[str(id)]
		visible_stars = mini(stars, int(change.before) + maxi(0, int((animation_player.time - 0.3) / 0.25) + 1)) if animation_player.time >= 0.3 else int(change.before)
	for star in visible_stars:
		var star_frame := 17
		if changes.get("stars", {}).has(str(id)):
			var change: Dictionary = changes.stars[str(id)]
			if star >= int(change.before): star_frame = clampi(1 + int((animation_player.time - 0.3 - (star - int(change.before)) * 0.25) * 30), 1, 17)
		paint.image("mapFlag_star_%04d" % star_frame, Vector2(12 + star * 16, 12))
	if overlay == "" and (born < 0 or elapsed >= 0.8): paint.hit(Rect2(20, 34, 44, 74), "level", {"id": id})
	paint.pop()

func _set_hovered(value: String) -> void:
	if hovered == value: return
	hovered = value
	for id in flag_states: flag_states[id].set_hovered(value == "level" + str({"id": id}))
	if hovered.begins_with("level"): _sound("GUIQuickMenuOver")
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" else CURSOR_ARROW
	queue_redraw()

func _refresh_hover() -> void:
	var value := ""
	for hit: Dictionary in hits:
		if hit.rect.has_point(pointer): value = hit.action + str(hit.args)
	_set_hovered(value)

func _gui_input(event: InputEvent) -> void:
	if paint == null: return
	if event is InputEventMouseMotion:
		pointer = event.position / zoom
		if not volume_drag.is_empty(): _volume(pointer.x)
		_refresh_hover()
	elif event is InputEventMouseButton:
		if Time.get_ticks_msec() < suppress_mouse_until: accept_event(); return
		pointer = event.position / zoom
		if not event.pressed: volume_drag.clear(); return
		accept_event()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if overlay != "": close_overlay()
		elif event.button_index == MOUSE_BUTTON_LEFT: _click(pointer)
		elif overlay == "":
			var amount := Vector2.ZERO
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: amount.y = 90
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: amount.y = -90
			elif event.button_index == MOUSE_BUTTON_WHEEL_LEFT: amount.x = 90
			elif event.button_index == MOUSE_BUTTON_WHEEL_RIGHT: amount.x = -90
			if event.shift_pressed: amount = Vector2(-amount.y, 0)
			pan(amount)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch(event); accept_event()
	elif event is InputEventMagnifyGesture:
		set_map_zoom(magnification * event.factor, event.position / zoom); accept_event()
	elif event is InputEventPanGesture:
		pan(-event.delta * 45); accept_event()
	queue_redraw()

func _touch(event: InputEvent) -> void:
	suppress_mouse_until = Time.get_ticks_msec() + 500
	var point: Vector2 = event.position / zoom
	if event is InputEventScreenTouch:
		if event.pressed:
			if touches.is_empty(): touch_start = point; touch_moved = false
			touches[event.index] = point
		else:
			if touches.size() == 1 and not touch_moved: _click(point)
			touches.erase(event.index)
			if touches.size() == 1: touch_start = touches.values()[0]
		return
	if not touches.has(event.index): return
	if touches.size() >= 2:
		var old: Array = touches.values(); var distance: float = (old[0] as Vector2).distance_to(old[1])
		touches[event.index] = point
		var current: Array = touches.values()
		if distance > 0: set_map_zoom(magnification * (current[0] as Vector2).distance_to(current[1]) / distance, (current[0] + current[1]) / 2)
		touch_moved = true
	else:
		if point.distance_to(touch_start) > 15: touch_moved = true
		if touch_moved: pan(point - touches[event.index])
		touches[event.index] = point

func _click(point: Vector2) -> void:
	for index in range(hits.size() - 1, -1, -1):
		var hit: Dictionary = hits[index]
		if not hit.rect.has_point(point): continue
		if hit.action == "volume": volume_drag = hit.args; _volume(point.x)
		elif hit.enabled: _action(hit.action, hit.args)
		else: show_message(str(hit.args.get("reason", "暂未开放")))
		return

func _action(action: String, args: Dictionary = {}) -> void:
	hits.clear(); volume_drag.clear()
	_set_hovered("")
	if action != "upgrades" and upgrades_room != null: upgrades_room.hide()
	match action:
		"upgrades":
			overlay = "upgrades"; touches.clear()
			if hero_room != null: hero_room.hide()
			if upgrades_room == null:
				upgrades_room = preload("res://scripts/map/upgrades_room.gd").new(); add_child(upgrades_room); upgrades_room.initialize(self)
			upgrades_room.open()
		"heroes":
			overlay = "heroes"; touches.clear()
			if hero_room == null:
				hero_room = HeroRoom.new(); add_child(hero_room); hero_room.initialize(self)
			hero_room.open()
		"level":
			if not progress.is_unlocked(int(args.id)): return
			selected_level = int(args.id); mode = 1; overlay = "level"
		"mode": mode = int(args.mode)
		"close": close_overlay()
		"options":
			if hero_room != null: hero_room.hide()
			overlay = "options"; touches.clear()
		"menu": returned_to_menu.emit(); return
		"battle":
			if progress.is_playable(selected_level, mode, 2): battle_requested.emit(selected_level, mode, 2); return
		_ : show_message("暂未开放")
	_sound("GUIButtonCommon"); queue_redraw()

func close_overlay() -> void:
	if hero_room != null: hero_room.hide()
	if upgrades_room != null: upgrades_room.hide()
	overlay = ""; pointer = Vector2(-1000, -1000); _set_hovered(""); hits.clear(); touches.clear(); volume_drag.clear(); queue_redraw()
func show_message(value: String) -> void:
	message = value; message_until = animation_player.time + 3; queue_redraw()
func _volume(x: float) -> void:
	var value := clampf((x - volume_drag.track.position.x) / volume_drag.track.size.x, 0, 1)
	settings.set_volumes(value if volume_drag.bus == "music" else settings.music_volume, value if volume_drag.bus == "sfx" else settings.sfx_volume)

func _input(event: InputEvent) -> void:
	if overlay == "heroes" and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		hero_room.tab_focus(); get_viewport().set_input_as_handled(); return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if overlay != "": close_overlay()
		else: _action("options")
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT: pointer = Vector2(-1000, -1000); _set_hovered("")
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: touches.clear(); pointer = Vector2(-1000, -1000); volume_drag.clear(); _set_hovered("")

func _sound(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if not sounds.has(id):
		var sound: Dictionary = catalog.get_sound(id)
		sounds[id] = {"stream": load(sound.paths[0]), "gain": float(sound.get("gain", 1))}
	for player: AudioStreamPlayer in fx:
		if not player.playing:
			player.stream = sounds[id].stream; player.volume_db = linear_to_db(sounds[id].gain); player.play(); return

func _exit_tree() -> void:
	for player: AudioStreamPlayer in fx: player.stop(); player.stream = null
	frames.clear(); sounds.clear(); hits.clear(); touches.clear()
	if catalog != null: catalog.clear_cache()
