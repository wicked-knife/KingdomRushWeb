extends SceneTree
const App = preload("res://scenes/app_root.tscn")
var app: Control
var room: Control
var failures: Array[String] = []
var text_checks := 0
var suffix := ""
func _init() -> void: call_deferred("_run")
func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)
func _run() -> void:
	create_timer(100).timeout.connect(func(): push_error("Hero visual timeout"); quit(1))
	var temporary := "user://hero_visual_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temporary)
	app = App.instantiate(); app.settings_path = temporary + "/settings.json"; app.progress_path = temporary + "/campaign.json"
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await app.map_ready
	app.campaign_map._action("heroes"); room = app.campaign_map.hero_room
	while not room.loader.loaded: await process_frame
	suffix = "%dx%d" % [root.size.x, root.size.y]
	if "--interactive" in OS.get_cmdline_user_args(): return
	await capture("locked")
	for row: Dictionary in app.campaign.hero_definition.heroes:
		room.show_hero(row.name); await capture("audit", false)
	for id in app.campaign.hero_definition.portrait_fallbacks:
		room.show_hero(id); await capture(id)
	for row: Dictionary in app.campaign.hero_definition.heroes:
		if row.portrait.begins_with("generated_portrait_"):
			room.show_hero(row.name); await capture(row.name)
	app.campaign.record_result({"generation": 1, "level_id": 1, "mode": 1, "difficulty": 2, "lives": 20, "result": "victory"})
	room.show_hero("hero_eiskalt"); await capture("unlocked")
	await click_action("select")
	await create_timer(0.15).timeout
	check(room.voice.playing and room.voice.get_playback_position() > 0, "selection voice advances in native audio")
	room.show_hero("hero_asra"); await process_frame; await click_action("select"); await capture("dual")
	check(app.campaign.selected_hero_ids() == ["hero_eiskalt", "hero_asra"], "native clicks select two heroes")
	var key := InputEventKey.new(); key.keycode = KEY_TAB; key.pressed = true; Input.parse_input_event(key); await process_frame
	check(room.shown == "hero_eiskalt" and room.scroll.scroll_vertical > 0, "native Tab cycles and scrolls to selected hero")
	await capture("scrolled")
	var grid_hits: Array = room.grid.hits.filter(func(hit): return hit.args.id == "hero_asra")
	var thumbnail_click := InputEventMouseButton.new(); thumbnail_click.button_index = MOUSE_BUTTON_LEFT; thumbnail_click.pressed = true
	thumbnail_click.position = root.get_final_transform() * (room.grid.get_global_transform_with_canvas() * grid_hits[0].rect.get_center())
	Input.parse_input_event(thumbnail_click); await process_frame
	check(room.shown == "hero_asra", "native thumbnail click uses the scrolled grid transform")
	await click_action("toggle"); await capture("skills")
	# Exercise longest description and its scrollbar without shrinking away content.
	var longest := {"id": "", "index": 0, "length": 0}
	for row: Dictionary in app.campaign.hero_definition.heroes:
		for i in row.details.size():
			if row.details[i].text.length() > longest.length: longest = {"id": row.name, "index": i, "length": row.details[i].text.length()}
	room.show_hero(longest.id); room._action("skill", {"index": longest.index}); await capture("longest_skill")
	check(room.detail_text.get_content_height() > 0 and room.detail_scroll.get_v_scroll_bar().max_value >= room.detail_scroll.size.y, "long description remains readable through native scroll")
	await click_action("close"); await capture("map_portraits")
	check(app.campaign_map.overlay == "" and not room.visible, "done button closes room")
	app.campaign_map._action("heroes"); await process_frame
	key.keycode = KEY_ESCAPE; Input.parse_input_event(key); await process_frame
	check(not room.visible and app.campaign_map.overlay == "", "native Escape closes room")
	app.campaign_map._action("heroes"); await process_frame
	var right := InputEventMouseButton.new(); right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	right.position = root.get_final_transform() * room.detail_scroll.get_global_rect().get_center()
	Input.parse_input_event(right); await process_frame
	check(not room.visible, "native right click over skill text closes room")
	app.campaign_map._action("heroes"); await process_frame
	right.position = root.get_final_transform() * room.scroll.get_v_scroll_bar().get_global_rect().get_center()
	Input.parse_input_event(right); await process_frame
	check(not room.visible, "native right click over scrollbar closes room")
	var report := {"passed": failures.is_empty(), "resolution": suffix, "text_boxes_checked": text_checks, "failures": failures}
	var file := FileAccess.open("res://reports/heroes_visual_" + suffix + ".json", FileAccess.WRITE); file.store_string(JSON.stringify(report)); file.close()
	print("HERO_VISUAL: ", JSON.stringify(report)); app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
func click_action(action: String) -> void:
	await process_frame
	var matches: Array = room.hits.filter(func(hit): return hit.action == action)
	check(not matches.is_empty(), "button exists: " + action)
	if matches.is_empty(): return
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = root.get_final_transform() * (matches[0].rect.get_center() * room.zoom)
	Input.parse_input_event(down); await process_frame
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.position = down.position; Input.parse_input_event(up); await process_frame
func capture(label: String, save_image: bool = true) -> void:
	room.queue_redraw(); await process_frame; await RenderingServer.frame_post_draw
	for audit: Dictionary in room.paint.audit:
		text_checks += 1; check(audit.fits, "text fits " + room.shown + "/" + str(audit.id))
		check(Rect2(Vector2.ZERO, room.view_size).grow(1).encloses(audit.box), "text on screen " + str(audit.id))
	if save_image: root.get_texture().get_image().save_png("res://reports/heroes_" + label + "_" + suffix + ".png")
