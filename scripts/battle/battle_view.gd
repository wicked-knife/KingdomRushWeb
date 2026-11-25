extends Control
## Native canvas view. Simulation owns all rules; this class submits player commands.
signal returned_to_map
signal finished(outcome: Dictionary)
signal routed(route: String)
signal seen_flushed(seen: Dictionary)
const CampaignProgress = preload("res://scripts/services/campaign_progress.gd")
const Simulation = preload("res://scripts/battle/level01_sim.gd")
const Interface = preload("res://scripts/battle/battle_ui.gd")
const SpriteAnimation = preload("res://scripts/battle/dove_animation.gd")
const UnitInfo = preload("res://scripts/battle/dove_unit_info.gd")
const Catalog = preload("res://scripts/dove_asset_catalog.gd")
const Feedback = preload("res://scripts/battle/battle_feedback.gd")
const ART_SCALE := 768.0 / 1080.0
const INK := Color("ffe9b0")
const VICTORY_STAR_DELAY := 0.65
const VICTORY_STAR_INTERVAL := 0.7
const INVALID_POINT_DURATION := 14.0 / 30.0
var sim: RefCounted
var catalog: RefCounted
var combat_catalogs: Array = []
var fonts: RefCounted
var font: Font
var interface: RefCounted
var developer: RefCounted
var audio: Node
var selected := ""
var selected_unit := 0
var targeting := ""
var invalid_point_time := 0.0
var hovered := ""
var tower_hover_id := ""
var pointer := Vector2(-1000, -1000)
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
var outcome := {}
var return_label := "返回地图"
var victory_elapsed := -1.0
var victory_star_sounds := 0
var feedback: RefCounted

func initialize(boot: Node, sound: Node, definition: Dictionary = {}, simulation_override: RefCounted = null) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "Battle"
	mouse_filter = MOUSE_FILTER_STOP
	fonts = boot.fonts
	font = fonts.font_for("body")
	audio = sound
	sim = simulation_override if simulation_override != null else Simulation.new(definition, 1, OS.is_debug_build())
	var base: String = sim.data.get("level", {}).get("root", "res://data/level01/")
	catalog = Catalog.new(base + "catalog.json")
	for extra: String in sim.data.get("combat_bundles",[]):
		combat_catalogs.append({"catalog":Catalog.new(extra+"catalog.json"),"group":extra.trim_suffix("/").get_file()})
	animations = sim.animations
	sim.event.connect(_on_event)
	interface = Interface.new(self)
	developer = preload("res://scripts/battle/battle_developer.gd").new(self)
	feedback = Feedback.new(self)
	for i in range(12):
		var player := AudioStreamPlayer.new()
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = "SFX"; add_child(player); fx_players.append(player)
	for hero: Dictionary in sim.soldiers:
		if hero.has("hero"):sim.Heroes.voice(sim,sim.templates[hero.template],"insert")
	_music(sim.data.get("level", {}).get("prep_music", "Level01PrepMusic"))
	queue_redraw()

func _process(delta: float) -> void:
	if sim == null: return
	sim.advance(delta)
	interface.wave_flags.sync()
	interface.wave_flags.advance(delta)
	interface.advance_rewards(delta)
	_advance_victory_audio(delta)
	if selected_unit != 0 and unit_info().is_empty():
		selected_unit=0
		if targeting=="hero":targeting="";feedback.sync_cursor()
	message_time = maxf(0, message_time - delta)
	advance_target_feedback(delta)
	queue_redraw()

func advance_target_feedback(delta: float) -> void:
	invalid_point_time = maxf(0, invalid_point_time - delta) if targeting != "" else 0.0
	feedback.advance(delta)
	interface.advance_feedback(delta)

func target_pointer_frame() -> String:
	if invalid_point_time > 0:
		return "error_feedback_%04d" % clampi(1 + floori((INVALID_POINT_DURATION - invalid_point_time) * 30), 1, 14)
	return feedback.pointer_frame()

func _on_event(kind: String, payload: Dictionary) -> void:
	match kind:
		"music": _music(str(payload.id))
		"sound": _sound(str(payload.id))
		"stop_audio":
			audio.stop_music()
			for player:AudioStreamPlayer in fx_players:player.stop()
		"wave":
			selected = ""; targeting = ""
			feedback.sync_cursor()
			if int(payload.number) == 1: _music(sim.data.get("level", {}).get("music", "Level01Music"))
		"reward": interface.show_wave_reward(payload)
		"tip": tip = str(payload.id)
		"notice_confirmed": interface.confirmed(payload.notice)
		"finished":
			selected = ""; selected_unit = 0; targeting = ""
			feedback.sync_cursor()
			if outcome.is_empty():
				var identity: Dictionary = sim.data.get("level", {})
				var stars := CampaignProgress.stars_for(sim.lives) if int(identity.get("mode", 1)) == 1 else (1 if sim.lives > 0 else 0)
				outcome = {"generation": identity.get("generation", 1), "level_id": identity.get("id", 1), "mode": identity.get("mode", 1), "difficulty": identity.get("difficulty", 2), "result": sim.result, "lives": sim.lives, "stars": stars if sim.result == "victory" else 0, "developer_used": sim.developer_used}
				outcome.unlock_towers = sim.data.layout.get("unlock_towers", []).duplicate()
				if sim.result=="victory" and sim.controller.has_method("victory_route"):
					var route:String=sim.controller.victory_route(sim)
					if route!="":outcome.next_item_name=route
				if sim.result == "victory": _begin_victory_audio()
				finished.emit(outcome.duplicate())

func _begin_victory_audio() -> void:
	# Dove VictoryView:show stops battle audio before the completion fanfare.
	audio.stop_music(); audio.click_player.stop()
	for player: AudioStreamPlayer in fx_players: player.stop()
	victory_elapsed = 0; victory_star_sounds = 0
	interface.victory.start()
	_sound("GUIQuestCompleted", false)

func _advance_victory_audio(delta: float) -> void:
	if sim.result != "victory" or victory_elapsed < 0: return
	victory_elapsed += delta
	while victory_star_sounds < int(outcome.get("stars", 0)) and victory_elapsed >= VICTORY_STAR_DELAY + victory_star_sounds * VICTORY_STAR_INTERVAL:
		_sound("GUIWinStars", false)
		victory_star_sounds += 1

func _music(id: String) -> void:
	var definition: Dictionary = catalog.get_sound(id)
	if definition.is_empty(): return
	audio.play_music(load(definition.paths[0]), float(definition.get("gain", 1.0)))

func _sound(id: String, limit_repeats: bool = true) -> void:
	if not is_inside_tree(): return
	if DisplayServer.get_name() == "headless": return
	var sound_catalog: RefCounted = catalog
	if not sound_catalog.get_static("sounds").has(id):
		for extra: Dictionary in combat_catalogs:
			if extra.catalog.get_static("sounds").has(id):sound_catalog=extra.catalog;break
		if not sound_catalog.get_static("sounds").has(id):return
	var now := Time.get_ticks_msec()
	if limit_repeats and now - int(sound_last.get(id, -1000)) < 90: return
	sound_last[id] = now
	if not sound_cache.has(id):
		var definition: Dictionary = sound_catalog.get_sound(id)
		sound_cache[id] = {"streams": [], "gain": definition.get("gain", 1.0)}
		for path: String in definition.paths: sound_cache[id].streams.append(load(path))
	var sound: Dictionary = sound_cache[id]
	if sound.streams.is_empty(): return
	for player: AudioStreamPlayer in fx_players:
		if not player.playing:
			player.stream = sound.streams[(sim.tick + id.length()) % sound.streams.size()]
			player.volume_db = linear_to_db(float(sound.gain)); player.play(); return

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	flush_seen()
	for player: AudioStreamPlayer in fx_players: player.stop(); player.stream = null
	if is_instance_valid(audio) and is_instance_valid(audio.music_player):
		audio.stop_music()
	sound_cache.clear(); frames_cache.clear()
	if catalog != null: catalog.clear_cache()
	for extra: Dictionary in combat_catalogs:extra.catalog.clear_cache()
	combat_catalogs.clear()
	if sim != null and sim.event.is_connected(_on_event): sim.event.disconnect(_on_event)

func _frame(name_value: String) -> Dictionary:
	if not frames_cache.has(name_value):
		var group: String=sim.data.get("level",{}).get("group","level01")
		if not catalog.load_group(group).get("lookup",{}).has(name_value):
			for extra: Dictionary in combat_catalogs:
				if extra.catalog.load_group(extra.group).get("lookup",{}).has(name_value):
					frames_cache[name_value]=extra.catalog.get_frame(extra.group,name_value);return frames_cache[name_value]
		frames_cache[name_value]=catalog.get_frame(group,name_value)
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
	tower_hover_id = hovered_tower()
	_art(sim.data.get("level", {}).get("background", "stage_1"), Vector2(view_width / 2, 384))
	for i in range(sim.data.layout.entities_list.size()):
		var e: Dictionary = sim.data.layout.entities_list[i]
		if not sim.templates.has(e.template): continue
		if e.has("tower.holder_id"): continue
		# Layout entries seed live units. Drawing them here leaves immortal,
		# motionless copies behind after the actual guards move or die.
		if sim.templates[e.template].has("soldier") or sim.templates[e.template].has("enemy"): continue
		if e.get("render.sprites[1].name","") == sim.data.level.background: continue
		if sim.templates[e.template].has("delayed_play") or sim.templates[e.template].template_name == "decal_fish": continue
		if sim.templates[e.template].has("particle_system") or sim.templates[e.template].has("tunnel") or sim.templates[e.template].template_name == "decal_tunnel_light": continue
		if sim.templates[e.template].template_name=="veznan_portal":continue
		_queue_template(e.template, Simulation.vec(e.pos))
	sim.snow.queue(self)
	sim.wasteland.queue(self)
	sim.jt.queue(self)
	sim.veznan.queue(self)
	for decal: Dictionary in sim.decals:
		if not decal.removed: _queue_template(decal.template, decal.pos, decal.state, decal.state_at, decal.flip, false, 1, false, "", decal)
	for egg: Dictionary in sim.eggs:
		_queue_egg(egg)
	for spawner: Dictionary in sim.spawners:
		_queue_template(spawner.template, spawner.pos, spawner.state, spawner.at, false, false, 1, false, "", {"alpha": clampf(1 - float(sim.tick - int(spawner.get("fade_at", sim.tick))) / 120.0, 0, 1), "playback_loop": false})
	for aura: Dictionary in sim.auras:
		_queue_template(aura.template, aura.pos, "", aura.at, false, false, 1, false, "", {"playback_loop": false})
	for tower: Dictionary in sim.towers:
		var template_name: String = tower.template
		if tower.ready > sim.tick:
			template_name = "tower_build_" + tower.type
		var preview := ""
		if tower.id == selected and tower.type == "":
			for type: String in Simulation.TYPES:
				if hovered == "build" + str({"id": selected, "type": type}): preview = "tower_preview_" + ("artillery" if type == "engineer" else type)
		_queue_template(template_name, tower.pos, "", int(tower.get("built_at", 0)) if tower.ready > sim.tick else 0, false, false, 1, false, preview, {} if tower.ready > sim.tick else tower)
		if tower.has("arcane") and tower.powers.disintegrate > 0:
			var cooldown: float = sim.tower_template(tower).powers.disintegrate.cooldown_base + sim.tower_template(tower).powers.disintegrate.cooldown_inc * tower.powers.disintegrate - sim.tower_template(tower).attacks.min_cooldown
			if tower.arcane.timestamps[1] <= tower.arcane.last - sim.frames(cooldown) or sim.tick - tower.arcane.timestamps[1] >= sim.frames(cooldown):
				_queue_template("decalmod_arcane_wizard_disintegrate_ready", tower.pos)
	for unit: Dictionary in sim.enemies + sim.soldiers:
		_queue_template(unit.template, unit.pos, unit.state, unit.state_at, unit.flip, false, int(unit.get("variant", 1)), unit.hp <= 0, "", unit)
	for p: Dictionary in sim.projectiles:
		_queue_template(p.template, p.pos, p.get("playback_state","flying" if sim.templates[p.template].get("behavior", "") == "scripts.bolt.update" else ""), p.at, false, false, 1, false, "", p)
	for aura: Dictionary in sim.upgrades.auras: _queue_template(aura.template, aura.pos, "", aura.at, false, false, 1, false, "", aura)
	for effect: Dictionary in sim.effects:
		if effect.has("owner") and sim.tick-int(effect.at)>=int(effect.duration): continue
		if effect.has("raw_frame"):
			draw_list.append({"scale":Vector2.ONE,"frame":effect.raw_frame,"pos":effect.pos,"sort_y":effect.pos.y,"anchor":effect.anchor,"z":1000,"order":draw_list.size(),"flip":false,"rotation":effect.rotation,"tint":Color(1,1,1,1.0-float(sim.tick-effect.at)/effect.duration)})
			continue
		if effect.has("target"):
			var target: Dictionary = sim.unit_by_id(effect.target)
			if target.is_empty() or target.hp <= 0: continue
			effect.pos = target.pos + Simulation.vec(sim.unit_template(target).unit.mod_offset)
		_queue_template(effect.template, effect.pos, effect.get("state", ""), effect.at, effect.get("flip",false), false, 1, false, "", effect)
	for modifier: Dictionary in sim.modifiers.active:
		var target: Dictionary = sim.unit_by_id(modifier.target)
		if target.is_empty() or target.hp <= 0 or target.get("hidden", false): continue
		# The original lifecycle hides older duplicate poison sprites.
		if not modifier.get("visible",true) or not sim.templates[modifier.template].has("render"): continue
		_queue_template(modifier.template, target.pos, modifier.state, modifier.at, target.flip, false, 1, false, "", {"sprite_z": int(sim.templates[target.template].render.sprites[0].z) if modifier.template=="mod_ray_tesla" else int(sim.templates[modifier.template].render.sprites[0].get("z",3000)), "sprite_offset": Vector2.ZERO if modifier.template == "mod_thorn" or not sim.templates[modifier.template].modifier.get("use_mod_offset",true) else Simulation.vec(sim.unit_template(target).unit.mod_offset), "prefix":modifier.prefix,"sprite_scale":modifier.scale,"playback_loop":modifier.phase == "loop" and sim.templates[modifier.template].render.sprites[0].get("loop",true)})
	feedback.queue_markers()
	draw_list.sort_custom(func(a, b):
		if a.z != b.z: return a.z < b.z
		if a.sort_y != b.sort_y: return a.sort_y > b.sort_y
		if int(a.get("draw_order",1)) != int(b.get("draw_order",1)): return int(a.get("draw_order",1)) < int(b.get("draw_order",1))
		return a.order < b.order)
	for item: Dictionary in draw_list: _art(item.frame, world(item.pos), item.anchor, 1.0, item.tint, item.flip, -item.rotation, item.scale)
	for unit: Dictionary in sim.enemies + sim.soldiers:
		if unit.get("health_bar_hidden",false) or unit.hp <= 0 or unit.hp == unit.max_hp or unit.get("hidden", false) or unit.get("health_bar_hidden",false) or unit.has("boss"): continue
		var p := world(unit.pos + Simulation.vec(sim.templates[unit.template].health_bar.offset))
		var width := 36.0 if sim.templates[unit.template].health_bar.type == "medium" or unit.has("hero") and sim.templates[unit.template].health_bar.type=="med" else 24.0
		draw_rect(Rect2(p + Vector2(-width / 2 - 1, -2), Vector2(width + 2, 4)), Color("362519"))
		# Dove uses a full-width cyan bar (fg2) for HP above the normal maximum.
		var color := Color.CYAN if unit.hp > unit.max_hp else Color("67ce26")
		draw_rect(Rect2(p + Vector2(-width / 2, -1), Vector2(width * clampf(unit.hp / unit.max_hp, 0, 1), 2)), color)
	_draw_selection()
	feedback.draw_rally_feedback()
	interface.wave_flags.draw_path()
	if not sim.veznan.hud_hidden:_draw_hud()
	_draw_boss_bar()
	if not sim.veznan.taunt.is_empty():
		var taunt:Dictionary=sim.veznan.taunt
		_art("boss_veznan_taunts_love_0001",world(taunt.pos))
		var label:=str(taunt.text)
		for line_index in range(ceili(label.length()/12.0)):_text(label.substr(line_index*12,12),world(taunt.pos)+Vector2(0,-13+line_index*19),18,Color("e9bdff"),true)
	developer.hud()
	if message_time > 0: _text(message, Vector2(view_width / 2, 95), 20, INK, true)
	feedback.draw_pointer()
	if developer.opened: developer.draw()
	elif not sim.notices.is_empty(): _draw_notice(str(sim.notices[0]))
	elif sim.result != "": _draw_result()
	elif sim.paused: _draw_pause()
	_refresh_hover()
	draw_set_transform(Vector2.ZERO)

func _queue_egg(egg: Dictionary) -> void:
	# Dove plays start once, holds its last frame, then fades the idle shell.
	_queue_template(egg.template,egg.pos,egg.state,egg.at,false,false,1,false,"",{"alpha":clampf(1 - float(sim.tick - int(egg.get("fade_at",sim.tick))) / 120.0,0,1),"playback_loop":false})

func _queue_template(template_name: String, point: Vector2, state: String = "", at: int = 0, flip: bool = false, up: bool = false, variant: int = 1, dead: bool = false, preview: String = "", runtime: Dictionary = {}) -> void:
	if runtime.get("hidden", false): return
	if dead and runtime.get("source_corpse",false):
		var u:Dictionary=sim.templates[template_name].get("unit",{})
		if u.get("hide_during_death",false):return
		var death_length:int=SpriteAnimation.duration(animations,SpriteAnimation.key(sim.templates[template_name].render.sprites[0],state))
		if u.get("hide_after_death",false) and sim.tick-at>=death_length:return
	var template: Dictionary = runtime.get("combat_template",sim.templates[template_name])
	if dead and template.get("unit", {}).get("hide_after_death", false):
		var sprite: Dictionary = template.render.sprites[0]
		if sim.tick - at >= SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, state)): return
	if template.has("particle_system"):
		var ps: Dictionary = template.particle_system
		var alpha: float = lerpf(float(ps.alphas[0]),float(ps.alphas[1]),clampf(float(sim.tick - at) / int(runtime.duration),0,1)) / 255.0
		draw_list.append({"scale":Vector2.ONE,"frame":ps.name,"pos":point,"sort_y":point.y,"anchor":Vector2(0.5,0.5),"z":int(ps.z),"order":draw_list.size(),"flip":false,"rotation":runtime.rotation,"tint":Color(1,1,1,alpha)})
		return
	var order := 0
	for sprite: Dictionary in template.get("render", {}).get("sprites", []):
		order += 1
		var tower_over: bool = template.has("tower") and order == 1 and str(runtime.get("id", "")) == tower_hover_id and tower_hover_id != ""
		if sprite.get("hidden", false) and sprite.get("name", "") != preview and not runtime.get("fish", false) and not runtime.get("layers",{}).get(order,{}).get("visible",false) and not (tower_over and sprite.get("hover_off_hidden",false)): continue
		var playback := {"state": state, "elapsed": maxi(0, sim.tick - at)}
		if runtime.get("prefix", "") != "": playback.prefix = runtime.prefix
		var layer: Dictionary = runtime.get("layers", {}).get(order, {})
		if layer.has("visible") and not layer.visible:continue
		if not layer.is_empty():
			playback.state = layer.get("state",state); playback.elapsed = maxi(0, sim.tick - int(layer.get("at",at))); playback.loop = layer.get("loop",true)
			var length := SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, layer.get("state",state)))
			if layer.has("idle") and int(playback.elapsed) >= length:
				playback.state = layer.idle; playback.elapsed -= length; playback.loop = true
		elif state != "":
			playback.loop = state not in ["attack", "attack2", "holystrike", "healing", "death", "play", "shoot", "ranged_attack", "heal", "jump", "small", "medium", "large"]
			var shoot_angles: Array = sprite.get("angles", {}).get("shoot", [])
			if state == "shoot" and not shoot_angles.is_empty(): playback.state = shoot_angles[0 if up else mini(1, shoot_angles.size() - 1)]
			if state in ["attack", "attack2", "holystrike", "healing"] and int(playback.elapsed) >= SpriteAnimation.duration(animations, SpriteAnimation.key(sprite, state)):
				playback.state = "idle"; playback.loop = true
		if runtime.has("playback_loop") and not layer.has("loop"): playback.loop = runtime.playback_loop
		if sprite.has("hide_after_runs") and int(playback.elapsed)>=SpriteAnimation.duration(animations,SpriteAnimation.key(sprite,playback.state))*int(sprite.hide_after_runs):continue
		if template.has("reinforcement") and template.get("info", {}).has("portrait_idxs"): playback.prefix = "%s_%d" % [template_name, variant]
		var frame_name := SpriteAnimation.frame(sprite, animations, playback)
		if order == 1 and runtime.get("terrain_base",true) and runtime.has("holder") and sim.templates.has(runtime.holder) and not sprite.get("animated",false): frame_name = sim.templates[runtime.holder].render.sprites[0].name
		if tower_over: frame_name += "_over"
		var offset := Simulation.vec(sprite.get("offset", {"x": 0, "y": 0}))
		offset += runtime.get("sprite_offset", Vector2.ZERO)
		var alpha := float(sprite.get("alpha", 255)) / 255.0
		alpha *= float(runtime.get("alpha",1.0))
		if layer.has("alpha"):alpha=float(layer.alpha)
		# Multi-attack soldiers use the source corpse lifetime (guards/paladins).
		# Existing units retain their established presentation.
		if dead and not runtime.get("source_corpse",false) and not template.get("unit", {}).get("hide_after_death", false) and not (template.has("soldier") and template.melee.attacks.size() > 1): alpha *= clampf(1 - float(sim.tick - at - 24) / 36, 0, 1)
		var sprite_scale: Vector2 = runtime.get("sprite_scale", Simulation.vec(sprite.get("scale", {"x": 1, "y": 1})))
		var tween: Dictionary = template.get("tween", {})
		var clicked: bool = runtime.has("clicked_at") and sim.tick - int(runtime.clicked_at) <= 6
		if not tween.get("disabled", false) or clicked:
			var seconds: float = (sim.tick - int(runtime.clicked_at) if clicked else sim.tick - int(runtime.get("born_at", at))) / 30.0
			for property: Dictionary in tween.get("props", []):
				if property.get("disabled",false):continue
				if int(property.get("sprite_id", 1)) != order: continue
				if property.name == "scale": sprite_scale *= SpriteAnimation.vector_track(property.keys, seconds)
				elif property.name == "alpha":
					var keys: Array = property.keys
					if keys.any(func(k): return k[0] is String):
						keys = keys.duplicate(true)
						for k: Array in keys:
							if k[0] is String: k[0] = float(runtime.get("duration", 0)) - (0.5 if k[0].ends_with("-0.5") else 0)
					alpha *= SpriteAnimation.scalar_track(keys, fmod(seconds, float(keys[-1][0])) if property.get("loop", false) and float(keys[-1][0]) > 0 else seconds) / 255.0
		var color: Array = sprite.get("color", [255, 255, 255])
		draw_list.append({"scale": sprite_scale, "frame": frame_name, "pos": point + offset, "sort_y": float(sprite.get("sort_y",point.y + float(sprite.get("sort_y_offset", 0)))), "anchor": Simulation.vec(sprite.get("anchor", {"x": 0.5, "y": 0.5})), "z": int(runtime.get("sprite_z",sprite.get("z", 3000))), "draw_order": int(layer.get("draw_order",sprite.get("draw_order",order))), "order": draw_list.size(), "flip": layer.get("flip", runtime.get("flip", sprite.get("flip_x", flip))), "rotation": float(runtime.get("rotation", sprite.get("r", 0))), "tint": Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0, alpha)})

func _draw_boss_bar() -> void:
	for unit: Dictionary in sim.enemies:
		if not unit.has("boss") or unit.hp <= 0 or unit.get("health_bar_hidden",false): continue
		var origin := Vector2((view_width - 440) / 2, 20)
		var hp: float = clampf(unit.hp / unit.max_hp, 0, 1)
		var panel := StyleBoxFlat.new(); panel.bg_color = Color(0, 0, 0, 0.55); panel.set_corner_radius_all(5)
		draw_style_box(panel, Rect2(origin, Vector2(440, 42)))
		draw_rect(Rect2(origin + Vector2(40, 26), Vector2(392, 8)), Color("801414"))
		draw_rect(Rect2(origin + Vector2(40, 26), Vector2(392 * hp, 8)), Color("d94d33") if hp < 0.3 else Color("33d933"))
		_art(unit.get("portrait",sim.templates[unit.template].info.portrait), origin + Vector2(20, 21), Vector2(0.5, 0.5), 0.6)
		_text(sim.data.ui.strings.get(unit.template.to_upper() + "_NAME", unit.template), origin + Vector2(40, 19), 14)

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
	if sim != null and sim.veznan.hud_hidden and sim.result == "": return
	queue_redraw()
	if input is InputEventMouseMotion:
		var point: Vector2 = input.position / zoom
		pointer = point
		feedback.inside = true; feedback.sync_cursor()
		if not volume_drag.is_empty(): _set_volume(volume_drag, point.x)
		_refresh_hover()
		return
	if input is InputEventMouseButton and not input.pressed:
		volume_drag.clear(); return
	if not input is InputEventMouseButton or not input.pressed: return
	accept_event()
	if input.button_index == MOUSE_BUTTON_RIGHT:
		interface.wave_flags.pending_click.clear()
		if developer.opened: developer.close(); return
		targeting = ""; invalid_point_time = 0; selected = ""; selected_unit = 0; hits.clear(); feedback.sync_cursor(); return
	if input.button_index != MOUSE_BUTTON_LEFT: return
	var point: Vector2 = input.position / zoom
	pointer = point
	for i in range(hits.size() - 1, -1, -1):
		var hit: Dictionary = hits[i]
		if hit.rect.has_point(point):
			if hit.action == "wave" and hit.enabled:
				interface.wave_flags.click(int(hit.args.path), input.double_click); return
			interface.wave_flags.pending_click.clear()
			if hit.action == "volume":
				volume_drag = hit.args
				_set_volume(hit.args, point.x)
			elif hit.enabled: _action(hit.action, hit.args)
			return
	interface.wave_flags.pending_click.clear()
	if not sim.notices.is_empty() or sim.paused or sim.result != "": return
	var world_point := Vector2(point.x - margin, 768 - point.y)
	if targeting != "":
		var success: bool
		if targeting=="hero":success=sim.command("move_hero",{"id":selected_unit,"pos":world_point})
		else:success=sim.command("rally", {"id": selected, "pos": world_point}) if targeting == "rally" else sim.command("cast", {"power": targeting, "pos": world_point})
		if success:
			if targeting == "rally": feedback.rallied(sim.tower_by_id(selected).rally)
			if targeting == "hero":feedback.rallied(world_point);selected_unit=0
			targeting = ""; selected = ""; invalid_point_time = 0
		else: invalid_point_time = INVALID_POINT_DURATION
		feedback.sync_cursor()
		return
	var interactive:int=0
	for unit:Dictionary in sim.enemies:
		if unit.hp<=0 or unit.get("hidden",false) or not (unit.has("jt") or sim.behaviors.role(unit.template)=="sheep"):continue
		var area:Dictionary=sim.templates[unit.template].ui.click_rect
		if Rect2(unit.pos+Simulation.vec(area.pos),Simulation.vec(area.size)).has_point(world_point):interactive=unit.id
	if interactive!=0:
		sim.command("unit_click",{"id":interactive})
		if not sim.unit_by_id(interactive).has("jt") or sim.unit_by_id(interactive).get("dying",false):return
	var clicked_tower:String=pick_tower(world_point)
	if clicked_tower!="" and sim.tower_by_id(clicked_tower).get("blocked",false):sim.command("tower_click",{"id":clicked_tower});selected="";return
	selected_unit = UnitInfo.pick(sim.soldiers + sim.enemies, sim.templates, world_point)
	if selected_unit != 0:
		if sim.unit_by_id(selected_unit).has("hero"):targeting="hero";feedback.sync_cursor()
		selected = ""; return
	var picked := pick_tower(world_point)
	if picked != "": selected = picked; _sound("GUIQuickMenuOpen"); return
	selected = ""
	for decal: Dictionary in sim.decals:
		if decal.removed or decal.hidden: continue
		if not sim.templates[decal.template].get("delayed_play", {}).has("required_clicks"): continue
		var area: Dictionary = sim.templates[decal.template].ui.click_rect
		if Rect2(decal.pos + Simulation.vec(area.pos), Simulation.vec(area.size)).has_point(world_point):
			sim.command("decal_click", {"id": decal.id}); return

func pick_tower(point: Vector2) -> String:
	for tower: Dictionary in sim.towers:
		var template: Dictionary = sim.tower_template(tower)
		var area: Dictionary = template.ui.click_rect
		if template.ui.get("can_click",true) and tower.ready <= sim.tick and Rect2(tower.pos+Simulation.vec(area.pos),Simulation.vec(area.size)).has_point(point): return str(tower.id)
	return ""

func hovered_tower() -> String:
	if sim == null or sim.paused or not sim.notices.is_empty() or sim.result != "" or targeting != "" or pointer.x < -999: return ""
	var id := selected if selected != "" else pick_tower(Vector2(pointer.x-margin,768-pointer.y))
	var tower: Dictionary = sim.tower_by_id(id)
	return id if not tower.is_empty() and sim.tower_template(tower).tower.get("can_hover",false) and tower.ready <= sim.tick else ""

func _refresh_hover() -> void:
	var previous := hovered
	var previous_tower := tower_hover_id
	tower_hover_id = hovered_tower()
	hovered = ""
	for hit: Dictionary in hits:
		if hit.rect.has_point(pointer): hovered = hit.action + str(hit.args)
	if previous != hovered or previous_tower != tower_hover_id:
		if hovered.begins_with("build") or tower_hover_id != "" and previous_tower != tower_hover_id: _sound("GUIQuickMenuOver")
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if hovered != "" or tower_hover_id != "" else CURSOR_ARROW
		queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		pointer = Vector2(-1000, -1000); hovered = ""; tower_hover_id = ""; mouse_default_cursor_shape = CURSOR_ARROW
		if feedback != null:
			if what == NOTIFICATION_WM_MOUSE_EXIT: feedback.inside = false
			else: feedback.focused = false
			feedback.sync_cursor(); interface.wave_flags.pending_click.clear()
	elif what in [NOTIFICATION_WM_MOUSE_ENTER, NOTIFICATION_APPLICATION_FOCUS_IN] and feedback != null:
		if what == NOTIFICATION_WM_MOUSE_ENTER: feedback.inside = true
		else: feedback.focused = true
		pointer = get_local_mouse_position() / zoom; feedback.sync_cursor()

func _input(input: InputEvent) -> void:
	if sim == null or not visible: return
	if sim.veznan.hud_hidden and sim.result == "": return
	if input is InputEventKey and input.pressed and not input.echo:
		if input.keycode == KEY_F8:
			_action("developer"); get_viewport().set_input_as_handled(); return
		if input.keycode == KEY_ESCAPE:
			if developer.opened: developer.close()
			elif not sim.notices.is_empty(): _action("confirm")
			elif targeting != "" or selected != "" or selected_unit != 0: targeting = ""; invalid_point_time = 0; selected = ""; selected_unit = 0
			elif sim.result == "": _action("pause")
			get_viewport().set_input_as_handled()
			feedback.sync_cursor(); interface.wave_flags.pending_click.clear()
		elif not developer.opened and sim.notices.is_empty() and not sim.paused and sim.result == "":
			if input.keycode == KEY_1: _action("target", {"power": "fire"})
			elif input.keycode == KEY_2: _action("target", {"power": "reinforcements"})
			elif input.keycode == KEY_SPACE: _action("wave")
			elif input.keycode == KEY_P: _action("pause")

func _action(action: String, args: Dictionary = {}) -> void:
	# A command can replace the entire composition before the next rendered frame.
	# Never dispatch a subsequent click through hit regions from the old mode.
	hits.clear()
	interface.wave_flags.pending_click.clear()
	if action == "developer": developer.toggle(); feedback.sync_cursor(); return
	if action.begins_with("dev_"):
		if not developer.execute(action): _message("当前开发操作不可用")
		queue_redraw(); return
	if developer.opened: return
	match action:
		"hero_select":
			var hero: Dictionary=sim.unit_by_id(int(args.id))
			if hero.is_empty() or hero.hp<=0 or hero.hero_phase=="respawn":return
			selected_unit=int(hero.id);selected="";targeting="hero";feedback.sync_cursor();return
		"skip_tutorial":
			while not sim.notices.is_empty() and str(sim.notices[0]).begins_with("TUTORIAL_"): sim.command("confirm")
		"locked", "unit_info": return
		"target":
			var power: String = args.power
			if power != "rally" and (sim.wave == 0 or not sim.unlocked.get(power, false) or sim.cooldowns.get(power, 0) > 0): return
			selected_unit = 0
			interface.power_fx.clear()
			invalid_point_time = 0
			if power == "rally" or (sim.unlocked.get(power, false) and sim.cooldowns.get(power, 0) == 0): targeting = power
			pointer = get_local_mouse_position() / zoom
			interface.power_hint_hidden = true
		"restart":
			flush_seen()
			developer.close()
			outcome.clear()
			victory_elapsed = -1; victory_star_sounds = 0
			sim.reset(); interface.reset(); selected = ""; selected_unit = 0; targeting = ""; invalid_point_time = 0; tip = ""
			feedback.reset()
			_music(sim.data.get("level", {}).get("prep_music", "Level01PrepMusic"))
			for player: AudioStreamPlayer in fx_players: player.stop()
		"map":
			targeting = ""; feedback.sync_cursor(); flush_seen()
			if sim.result=="victory" and outcome.get("next_item_name","")!="":routed.emit(outcome.next_item_name)
			else:returned_to_map.emit()
			return
		"tip": sim.notices.append(tip); tip = ""
		"enemy_notice":
			if sim.alerts.has(str(args.id)):
				sim.alerts.erase(str(args.id)); sim.notices.append(str(args.id))
		_:
			if not sim.command(action, args):
				if action in ["build", "upgrade", "upgrade_power", "sell", "buy_soldier"]: return
				_message("当前操作不可用")
			elif action == "upgrade_power": interface.power_bought(str(args.id), str(args.power))
			elif action in ["build", "upgrade", "sell", "buy_soldier"]:
				selected = ""; interface.power_fx.clear()
	feedback.sync_cursor()
	_sound("GUIButtonCommon")
	queue_redraw()

func flush_seen() -> void:
	if sim == null: return
	sim.data.seen = sim.seen_enemies.duplicate()
	seen_flushed.emit(sim.data.seen)

func _message(value: String) -> void:
	message = value; message_time = 3.0

func _set_volume(args: Dictionary, x: float) -> void:
	var value := clampf((x - args.track.position.x) / args.track.size.x, 0, 1)
	var settings: Node = get_parent().settings
	settings.set_volumes(value if args.bus == "music" else settings.music_volume, value if args.bus == "sfx" else settings.sfx_volume)
	queue_redraw()
