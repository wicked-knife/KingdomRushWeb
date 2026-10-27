extends "res://tests/tower_upgrade_arena.gd"
const ArenaSimulation = preload("res://tests/ranger_arena_sim.gd")
var enemy_choice: OptionButton
var count_choice: OptionButton
var path_choice: OptionButton
var status_label: Label
var panel: PanelContainer

static func definition() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ranger_arena/definition.json"))
	data.arena = true
	return data

func _ready() -> void:
	DisplayServer.window_set_title("Kingdom Rush Web · 游侠塔测试场")
	settings = Settings.new(); add_child(settings); settings.initialize("user://ranger_arena_settings.json")
	loader = Loader.new(); add_child(loader)
	loader.failed.connect(func(message): push_error(message); get_tree().quit(1))
	await loader.initialize()
	if loader.state != "ready": return
	audio = Audio.new(); add_child(audio)
	audio.configure(loader.resources[loader.manifest.audio.MusicMainMenu],loader.resources[loader.manifest.audio.GUIButtonCommon],settings)
	battle = Battle.new(); add_child(battle); battle.return_label = "退出测试场"
	var data := definition()
	battle.initialize(loader,audio,data,ArenaSimulation.new(data,42,false))
	battle.returned_to_map.connect(func(): get_tree().quit())
	_controls()

func _button(row: HBoxContainer, title: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = title; button.pressed.connect(callback); row.add_child(button)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _controls() -> void:
	panel = PanelContainer.new(); panel.name = "ArenaControls"; add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.add_theme_font_override("font",loader.fonts.font_for("body")); panel.add_theme_font_size_override("font_size",20)
	var panel_theme := Theme.new()
	panel_theme.default_font = loader.fonts.font_for("body"); panel_theme.default_font_size = 20
	panel.theme = panel_theme
	var box := VBoxContainer.new(); panel.add_child(box)
	var title := Label.new(); title.text = "游侠塔专项场 · 本局不保存"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title)
	var row := HBoxContainer.new(); box.add_child(row)
	enemy_choice = OptionButton.new(); enemy_choice.name = "EnemyChoice"; row.add_child(enemy_choice)
	for id: String in ArenaSimulation.ROSTER: enemy_choice.add_item(data_name(id))
	enemy_choice.selected = 4
	count_choice = OptionButton.new(); count_choice.name = "CountChoice"; row.add_child(count_choice)
	for count in [1,5,10]: count_choice.add_item("%d 个" % count)
	count_choice.selected = 1
	path_choice = OptionButton.new(); path_choice.name = "PathChoice"; row.add_child(path_choice)
	path_choice.add_item("路线 1"); path_choice.add_item("路线 2")
	_button(row,"出怪",func(): battle.sim.command("arena_spawn",{"type":ArenaSimulation.ROSTER[enemy_choice.selected],"count":[1,5,10][count_choice.selected],"path":path_choice.selected}))
	var tools := HBoxContainer.new(); tools.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(tools)
	_button(tools,"+10000 金币",func(): battle.sim.command("arena_gold"))
	_button(tools,"清场",func(): battle.sim.command("arena_clear"))
	_button(tools,"完整重置",func(): battle._action("restart"))
	_button(tools,"退出",func(): get_tree().quit())
	status_label = Label.new(); status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(status_label)
	panel.resized.connect(_center_panel)
	resized.connect(_center_panel)
	_center_panel()

func data_name(id: String) -> String:
	return str(battle.sim.data.ui.strings.get(id.to_upper() + "_NAME",id))

func _center_panel() -> void:
	panel.position = Vector2((size.x - panel.size.x) / 2,65)

func _process(_delta: float) -> void:
	if battle == null or status_label == null: return
	var id: int = battle.selected_unit
	var unit: Dictionary = battle.sim.unit_by_id(id)
	status_label.text = "存活 %d · 待出怪 %d · 暂停/倍速使用右上角按钮" % [battle.sim.enemies.filter(func(e): return e.hp > 0).size(),battle.sim.spawn_queue.size()] if unit.is_empty() else "%s · 毒效果 %d · 束缚 %.2fs" % [data_name(unit.template),battle.sim.modifiers.count(id,"mod_ranger_poison"),battle.sim.modifiers.remaining(id,battle.sim)]
