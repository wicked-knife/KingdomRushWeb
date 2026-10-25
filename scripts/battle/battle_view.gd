extends Control
## Native canvas view. Simulation owns all rules; this class submits player commands.
signal returned_to_menu
const Simulation = preload("res://scripts/battle/level01_sim.gd")
const Interface = preload("res://scripts/battle/battle_ui.gd")
const SpriteAnimation = preload("res://scripts/battle/dove_animation.gd")
const UnitInfo = preload("res://scripts/battle/dove_unit_info.gd")
const Catalog = preload("res://scripts/dove_asset_catalog.gd")
const ART_SCALE := 768.0 / 1080.0
const INK := Color("ffe9b0")
var sim: RefCounted
var catalog: RefCounted
var font: Font
var interface: RefCounted
var audio: Node
var selected := ""
var selected_unit := 0
var targeting := ""
var hovered := ""
var hits: Array = []
var frames_cache := {}
var animations := {}
var draw_list: Array = []
var view_width := 1365.33
var zoom := 1.0
var margin := 170.66
var message := ""
var message_time := 0.0
var tip := ""
var fx_players: Array = []
var sound_cache := {}
var sound_last := {}
var volume_drag := {}

func initialize(boot: Node, sound: Node) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "Level01"
	mouse_filter = MOUSE_FILTER_STOP
	font = boot.resources[boot.manifest.font].duplicate()
	# Custom canvas transforms are not included in automatic font oversampling.
	# Give the battle its own cache so scaled Chinese glyphs remain crisp.
	if font is FontFile: (font as FontFile).oversampling = 3.0
	audio = sound
	catalog = Catalog.new("res://data/level01/catalog.json")
	animations = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/animations.json")).animations
	sim = Simulation.new()
	sim.event.connect(_on_event)
	interface = Interface.new(self)
	for i in range(12):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"; add_child(player); fx_players.append(player)
	_music("Level01PrepMusic")
	queue_redraw()

func _process(delta: float) -> void:
	if sim == null: return
	sim.advance(delta)
	if selected_unit != 0 and unit_info().is_empty(): selected_unit = 0
	message_time = maxf(0, message_time - delta)
	queue_redraw()

func _on_event(kind: String, payload: Dictionary) -> void:
	match kind:
		"sound": _sound(str(payload.id))
		"wave":
			selected = ""; targeting = ""
			if int(payload.number) == 1: _music("Level01Music")
		"reward": _message("提前开波 +%d 金币，技能冷却缩短" % payload.gold)
		"tip": tip = str(payload.id)
		"notice_confirmed": interface.confirmed(payload.notice)
		"finished": selected = ""; selected_unit = 0; targeting = ""

func _music(id: String) -> void:
	var definition: Dictionary = catalog.get_sound(id)
	if definition.is_empty(): return
	audio.music_player.stop()
	audio.music_player.stream = load(definition.paths[0])
	if audio.music_player.stream is AudioStreamOggVorbis: audio.music_player.stream.loop = true
	audio.music_player.volume_db = linear_to_db(float(definition.get("gain", 1.0)))
	audio.unlock()

func _sound(id: String) -> void:
	if not is_inside_tree(): return
	if DisplayServer.get_name() == "headless": return
	if not catalog.get_static("sounds").has(id): return
	var now := Time.get_ticks_msec()
	if now - int(sound_last.get(id, -1000)) < 90: return
	sound_last[id] = now
	if not sound_cache.has(id):
		var definition: Dictionary = catalog.get_sound(id)
		sound_cache[id] = {"streams": [], "gain": definition.get("gain", 1.0)}
		for path: String in definition.paths: sound_cache[id].streams.append(load(path))
	var sound: Dictionary = sound_cache[id]
	if sound.streams.is_empty(): return
	for player: AudioStreamPlayer in fx_players:
		if not player.playing:
			player.stream = sound.streams[(sim.tick + id.length()) % sound.streams.size()]
			player.volume_db = linear_to_db(float(sound.gain)); player.play(); return

func _exit_tree() -> void:
	for player: AudioStreamPlayer in fx_players: player.stop(); player.stream = null
	sound_cache.clear(); frames_cache.clear()
	if catalog != null: catalog.clear_cache()
	if sim != null and sim.event.is_connected(_on_event): sim.event.disconnect(_on_event)

func _frame(name_value: String) -> Dictionary:
	if not frames_cache.has(name_value): frames_cache[name_value] = catalog.get_frame("level01", name_value)
	return frames_cache[name_value]

func _art(frame_name: String, at: Vector2, anchor: Vector2 = Vector2(0.5, 0.5), factor: float = 1.0, tint: Color = Color.WHITE, flip: bool = false, rotation_value: float = 0.0, sprite_scale: Vector2 = Vector2.ONE) -> void:
	var f := _frame(frame_name)
	if f.is_empty(): return
	var origin := Vector2(anchor.x * f.original_size.x - f.trim.x, (1.0 - anchor.y) * f.original_size.y - f.trim.y)
	var scale_value := float(f.ref_scale) * ART_SCALE * factor
	var rect := Rect2(-origin * scale_value, f.logical_size * scale_value)
	draw_set_transform(at * zoom, rotation_value, Vector2(-zoom if flip else zoom, zoom) * sprite_scale)
	draw_texture_rect(f.texture, rect, false, tint)
	draw_set_transform(Vector2.ZERO, 0, Vector2(zoom, zoom))

func _text(value: String, at: Vector2, size_value: int = 20, color: Color = INK, centered: bool = false) -> void:
	if centered: at.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x / 2
	draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, 3, Color("252519"))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

func world(point: Vector2) -> Vector2:
	return Vector2(point.x + margin, 768 - point.y)

func _draw() -> void:
	if sim == null: return
	zoom = size.y / 768.0; view_width = size.x / zoom; margin = (view_width - 1024) / 2
	draw_set_transform(Vector2.ZERO, 0, Vector2(zoom, zoom))
	hits.clear(); draw_list.clear(); interface.begin()
	_art("stage_1", Vector2(view_width / 2, 384))
	for i in range(sim.data.layout.entities_list.size()):
		var e: Dictionary = sim.data.layout.entities_list[i]
		if not sim.templates.has(e.template): continue
		if str(e.template).begins_with("tower_holder"): continue
		if sim.templates[e.template].has("delayed_play"): continue
		_queue_template(e.template, Simulation.vec(e.pos))
	for decal: Dictionary in sim.decals:
		if not decal.removed: _queue_template(decal.template, decal.pos, decal.state, decal.state_at, decal.flip, false, 1, false, "", decal)
	for tower: Dictionary in sim.towers:
		var template_name: String = "tower_holder_grass" if tower.type == "" else "tower_" + tower.type + "_1"
		if tower.ready > sim.tick:
			template_name = "tower_build_" + tower.type
		var preview := ""
		if tower.id == selected and tower.type == "":
			for type: String in Simulation.TYPES:
				if hovered == "build" + str({"id": selected, "type": type}): preview = "tower_preview_" + ("artillery" if type == "engineer" else type)
		_queue_template(template_name, tower.pos, "", int(tower.get("built_at", 0)) if tower.ready > sim.tick else 0, false, false, 1, false, preview, {} if tower.ready > sim.tick else tower)
	for unit: Dictionary in sim.enemies + sim.soldiers:
		_queue_template(unit.template, unit.pos, unit.state, unit.state_at, unit.flip, false, int(unit.get("variant", 1)), unit.hp <= 0, "", unit)
	for p: Dictionary in sim.projectiles:
		_queue_template(p.template, p.pos, "", p.at, false, false, 1, false, "", p)
	for effect: Dictionary in sim.effects: _queue_template(effect.template, effect.pos, "", effect.at, false, false, 1, false, "", effect)
	draw_list.sort_custom(func(a, b):
		if a.z != b.z: return a.z < b.z
		if a.sort_y != b.sort_y: return a.sort_y > b.sort_y
		return a.order < b.order)
	for item: Dictionary in draw_list: _art(item.frame, world(item.pos), item.anchor, 1.0, item.tint, item.flip, -item.rotation, item.scale)
	for unit: Dictionary in sim.enemies + sim.soldiers:
		if unit.hp <= 0 or unit.hp >= unit.max_hp: continue
		var p := world(unit.pos + Simulation.vec(sim.templates[unit.template].health_bar.offset))
		draw_rect(Rect2(p + Vector2(-13, -2), Vector2(26, 4)), Color("362519"))
		draw_rect(Rect2(p + Vector2(-12, -1), Vector2(24 * unit.hp / unit.max_hp, 2)), Color("67ce26"))
	if selected_unit != 0:
		var unit: Dictionary = sim.unit_by_id(selected_unit)
		if not unit.is_empty() and unit.hp > 0:
			var ring := PackedVector2Array()
			for i in range(33): ring.append(world(unit.pos) + Vector2(cos(i * TAU / 32) * 14, sin(i * TAU / 32) * 7))
			draw_polyline(ring, Color("ffe477"), 1.5, true)
	_draw_selection()
	_draw_hud()
	if message_time > 0: _text(message, Vector2(view_width / 2, 95), 20, INK, true)
	if targeting != "":
		var point := get_local_mouse_position() / zoom
		var valid: bool = sim.valid_ground(Vector2(point.x - margin, 768 - point.y))
		_art("pointer_set_rally_0001" if targeting == "rally" else "pointer_power_" + ("reinforcements" if targeting == "reinforcements" else "rain_of_fire"), point, Vector2(0.5, 0.5), 1, Color.WHITE if valid else Color(1, 0.3, 0.3))
	if not sim.notices.is_empty(): _draw_notice(str(sim.notices[0]))
	elif sim.result != "": _draw_result()
	elif sim.paused: _draw_pause()
	draw_set_transform(Vector2.ZERO)

func _queue_template(template_name: String, point: Vector2, state: String = "", at: int = 0, flip: bool = false, up: bool = false, variant: int = 1, dead: bool = false, preview: String = "", runtime: Dictionary = {}) -> void:
	if runtime.get("hidden", false): return
	var template: Dictionary = sim.templates[template_name]
	var order := 0
	for sprite: Dictionary in template.get("render", {}).get("sprites", []):
		order += 1
		if sprite.get("hidden", false) and sprite.get("name", "") != preview: continue
		var playback := {"state": state, "elapsed": maxi(0, sim.tick - at)}
		var layer: Dictionary = runtime.get("layers", {}).get(order, {})
		if not layer.is_empty():
			playback.state = layer.state; playback.elapsed = maxi(0, sim.tick - int(layer.at)); playback.loop = layer.loop
			var length := SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, layer.state))
			if layer.has("idle") and int(playback.elapsed) >= length:
				playback.state = layer.idle; playback.elapsed -= length; playback.loop = true
		elif state != "":
			playback.loop = state not in ["attack", "death", "play", "shoot"]
			if sprite.has("angles") and state == "shoot": playback.state = "shootingUp" if up else "shootingDown"
			if state == "attack" and int(playback.elapsed) >= SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, state)):
				playback.state = "idle"; playback.loop = true
		if template_name == "re_farmer": playback.prefix = "re_farmer_%d" % variant
		var frame_name := SpriteAnimation.frame(sprite, animations, playback)
		var offset := Simulation.vec(sprite.get("offset", {"x": 0, "y": 0}))
		var alpha := float(sprite.get("alpha", 255)) / 255.0
		if dead: alpha *= clampf(1 - float(sim.tick - at - 24) / 36, 0, 1)
		var sprite_scale := Simulation.vec(sprite.get("scale", {"x": 1, "y": 1}))
		var tween: Dictionary = template.get("tween", {})
		var clicked: bool = runtime.has("clicked_at") and sim.tick - int(runtime.clicked_at) <= 6
		if not tween.get("disabled", false) or clicked:
			var seconds: float = (sim.tick - int(runtime.clicked_at) if clicked else sim.tick - int(runtime.get("born_at", at))) / 30.0
			for property: Dictionary in tween.get("props", []):
				if int(property.get("sprite_id", 1)) != order: continue
				if property.name == "scale": sprite_scale *= SpriteAnimation.vector_track(property.keys, seconds)
				elif property.name == "alpha": alpha *= SpriteAnimation.scalar_track(property.keys, seconds) / 255.0
		draw_list.append({"scale": sprite_scale, "frame": frame_name, "pos": point + offset, "sort_y": point.y + float(sprite.get("sort_y_offset", 0)), "anchor": Simulation.vec(sprite.get("anchor", {"x": 0.5, "y": 0.5})), "z": int(sprite.get("z", 3000)), "order": draw_list.size(), "flip": layer.get("flip", flip), "rotation": float(runtime.get("rotation", sprite.get("r", 0))), "tint": Color(1, 1, 1, alpha)})

func unit_info() -> Dictionary:
	return UnitInfo.snapshot(sim.unit_by_id(selected_unit), sim.templates, sim.data.ui.strings) if selected_unit != 0 else {}

func _draw_selection() -> void:
	interface.selection()

func _draw_hud() -> void:
	interface.hud()

func _dim() -> void:
	hits.clear()
	draw_rect(Rect2(0, 0, view_width, 768), Color(0.015, 0.035, 0.025, 0.73))

func _draw_notice(id: String) -> void:
	interface.notice(id)

func _draw_pause() -> void:
	interface.pause()

func _draw_result() -> void:
	interface.result()

func _gui_input(input: InputEvent) -> void:
	queue_redraw()
	if input is InputEventMouseMotion:
		var point: Vector2 = input.position / zoom
		if not volume_drag.is_empty(): _set_volume(volume_drag, point.x)
		var previous := hovered
		hovered = ""
		for hit: Dictionary in hits:
			if hit.rect.has_point(point): hovered = hit.action + str(hit.args)
		if previous != hovered and hovered.begins_with("build"): _sound("GUIQuickMenuOver")
		return
	if input is InputEventMouseButton and not input.pressed:
		volume_drag.clear(); return
	if not input is InputEventMouseButton or not input.pressed: return
	accept_event()
	if input.button_index == MOUSE_BUTTON_RIGHT:
		targeting = ""; selected = ""; selected_unit = 0; hits.clear(); return
	if input.button_index != MOUSE_BUTTON_LEFT: return
	var point: Vector2 = input.position / zoom
	for i in range(hits.size() - 1, -1, -1):
		var hit: Dictionary = hits[i]
		if hit.rect.has_point(point):
			if hit.action == "volume":
				volume_drag = hit.args
				_set_volume(hit.args, point.x)
			elif hit.enabled: _action(hit.action, hit.args)
			else: _message("金币不足、技能尚未解锁或冷却未结束")
			return
	if not sim.notices.is_empty() or sim.paused or sim.result != "": return
	var world_point := Vector2(point.x - margin, 768 - point.y)
	if targeting != "":
		var success: bool = sim.command("rally", {"id": selected, "pos": world_point}) if targeting == "rally" else sim.command("cast", {"power": targeting, "pos": world_point})
		if success: targeting = ""; selected = ""
		else: _message("无效落点：请选择范围内道路")
		return
	selected_unit = UnitInfo.pick(sim.soldiers + sim.enemies, sim.templates, world_point)
	if selected_unit != 0:
		selected = ""; return
	for tower: Dictionary in sim.towers:
		var rect := Rect2(tower.pos + Vector2(-40, -12), Vector2(80, 70 if tower.type != "" else 46))
		if rect.has_point(world_point) and tower.ready <= sim.tick: selected = tower.id; _sound("GUIQuickMenuOpen"); return
	selected = ""
	for decal: Dictionary in sim.decals:
		if decal.removed: continue
		var area: Dictionary = sim.templates[decal.template].ui.click_rect
		if Rect2(decal.pos + Simulation.vec(area.pos), Simulation.vec(area.size)).has_point(world_point):
			sim.command("decal_click", {"id": decal.id}); return

func _input(input: InputEvent) -> void:
	if sim == null or not visible: return
	if input is InputEventKey and input.pressed and not input.echo:
		if input.keycode == KEY_ESCAPE:
			if not sim.notices.is_empty(): _action("confirm")
			elif targeting != "" or selected != "" or selected_unit != 0: targeting = ""; selected = ""; selected_unit = 0
			elif sim.result == "": _action("pause")
			get_viewport().set_input_as_handled()
		elif sim.notices.is_empty() and not sim.paused and sim.result == "":
			if input.keycode == KEY_1: _action("target", {"power": "fire"})
			elif input.keycode == KEY_2: _action("target", {"power": "reinforcements"})
			elif input.keycode == KEY_SPACE: _action("wave")
			elif input.keycode == KEY_P: _action("pause")

func _action(action: String, args: Dictionary = {}) -> void:
	# A command can replace the entire composition before the next rendered frame.
	# Never dispatch a subsequent click through hit regions from the old mode.
	hits.clear()
	match action:
		"skip_tutorial":
			while not sim.notices.is_empty() and str(sim.notices[0]).begins_with("TUTORIAL_"): sim.command("confirm")
		"locked", "unit_info": return
		"target":
			var power: String = args.power
			selected_unit = 0
			if power == "rally" or (sim.unlocked.get(power, false) and sim.cooldowns.get(power, 0) == 0): targeting = power
			interface.power_hint_hidden = true
		"restart":
			sim.reset(); interface.reset(); selected = ""; selected_unit = 0; targeting = ""; tip = ""
			_music("Level01PrepMusic")
			for player: AudioStreamPlayer in fx_players: player.stop()
		"menu": returned_to_menu.emit(); return
		"tip": sim.notices.append(tip); tip = ""
		_:
			if not sim.command(action, args): _message("当前操作不可用")
			elif action == "build" or action == "sell": selected = ""
	_sound("GUIButtonCommon")
	queue_redraw()

func _message(value: String) -> void:
	message = value; message_time = 3.0

func _set_volume(args: Dictionary, x: float) -> void:
	var value := clampf((x - args.track.position.x) / args.track.size.x, 0, 1)
	var settings: Node = get_parent().settings
	settings.set_volumes(value if args.bus == "music" else settings.music_volume, value if args.bus == "sfx" else settings.sfx_volume)
	queue_redraw()
