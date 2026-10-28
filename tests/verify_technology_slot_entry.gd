extends SceneTree
## Current-schema slot selection and map drawing; never accesses player slots.
const App = preload("res://scenes/app_root.tscn")
const Progress = preload("res://scripts/services/campaign_progress.gd")
var temporary := "user://technology_slot_entry_%d" % Time.get_ticks_usec()
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("slot entry timeout"); quit(1))
	var folder := temporary + "/saves"
	DirAccess.make_dir_recursive_absolute(folder)
	var malformed: Dictionary = Progress.read_json(Progress.SLOT_DEFINITION).template.duplicate(true)
	malformed.upgrade_list_id = 1.0
	var invalid_path := folder + "/slot_1.json"
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed)); file.close()
	var invalid_bytes := FileAccess.get_file_as_bytes(invalid_path)
	var current := Progress.new(); current.initialize(folder + "/slot_2.json")
	check(current.save(), "current template saves a new slot")
	check(Progress.read_json(current.path).upgrade_list_id is String, "new JSON keeps technology ID as a string")
	var app: Control = App.instantiate()
	app.settings_path = temporary + "/settings.json"; app.slots_path = folder
	root.add_child(app); await app.menu_ready
	app.menu.start_button.pressed.emit(); app.menu._select_slot(1); await process_frame
	check(app.campaign_map == null and app.slots.status(1) == "corrupt", "invalid field is rejected before map entry")
	check(FileAccess.get_file_as_bytes(invalid_path) == invalid_bytes, "invalid slot is not converted or rewritten")
	app.menu._select_slot(2); await app.map_ready
	for frame in range(4): await process_frame
	check(app.campaign.data.upgrade_list_id is String and app.campaign.data.upgrade_list_id == "1", "reload retains current technology ID")
	check(app.campaign_map.visible and app.campaign.upgrade_summary().supported, "loaded current slot draws the map")
	app.campaign_map._action("upgrades")
	for frame in range(4): await process_frame
	check(app.campaign_map.upgrades_room.visible and app.campaign_map.upgrades_room.hits.size() >= 36, "current slot opens technology room")
	app.campaign_map.close_overlay(); app._start_level(1, 1, 2)
	for frame in range(4): await process_frame
	check(app.battle != null and app.battle.sim.upgrades.effective.archers == 0, "current slot enters battle with its technology snapshot")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/technology_slot_entry_native.png")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":DisplayServer.get_name()!="headless","invalid_slot_migrated":false,"player_saves_modified":false}
	file = FileAccess.open("res://reports/technology_slot_entry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	app.queue_free(); await process_frame
	remove_tree(temporary)
	print("TECHNOLOGY_SLOT_ENTRY: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func remove_tree(folder: String) -> void:
	assert(ProjectSettings.globalize_path(folder).begins_with(ProjectSettings.globalize_path(temporary)))
	for name in DirAccess.get_directories_at(folder): remove_tree(folder+"/"+name)
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder+"/"+name)
	DirAccess.remove_absolute(folder)
