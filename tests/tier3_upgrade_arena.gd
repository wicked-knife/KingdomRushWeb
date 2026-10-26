extends "res://tests/tower_upgrade_arena.gd"
## Fourth-stage fixture with separate settings and no campaign save connection.

static func definition() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level04/definition.json"))
	data.waves.cash = 2500
	return data

func _ready() -> void:
	DisplayServer.window_set_title("Kingdom Rush Web · 三级防御塔测试场")
	settings = Settings.new(); add_child(settings)
	settings.initialize("user://tier3_upgrade_arena_settings.json")
	loader = Loader.new(); add_child(loader)
	loader.failed.connect(func(message): push_error(message); get_tree().quit(1))
	await loader.initialize()
	if loader.state != "ready": return
	audio = Audio.new(); add_child(audio)
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu], loader.resources[loader.manifest.audio.GUIButtonCommon], settings)
	battle = Battle.new(); add_child(battle)
	battle.return_label = "退出测试场"
	battle.initialize(loader, audio, definition())
	battle.returned_to_map.connect(func(): get_tree().quit())
	while not battle.sim.notices.is_empty(): battle.sim.command("confirm")
	var label := Label.new()
	label.text = "三级防御塔测试场 · 本局不保存"
	label.add_theme_font_override("font", loader.fonts.font_for("body"))
	label.add_theme_font_size_override("font_size", 17)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-155, 10); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
