extends SceneTree
## Verify the mounted pack itself, rather than accidentally resolving files from the dev tree.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the exported PCK after --")
		quit(1)
		return
	# Spawn an isolated resource namespace so missing files cannot fall back to the workspace.
	if args.size() == 1:
		var folder := ProjectSettings.globalize_path("res://build/pack_check")
		DirAccess.make_dir_recursive_absolute(folder)
		var ignore := FileAccess.open(ProjectSettings.globalize_path("res://build/.gdignore"), FileAccess.WRITE)
		ignore.close()
		var project := FileAccess.open(folder + "/project.godot", FileAccess.WRITE)
		project.store_string("config_version=5\n")
		project.close()
		DirAccess.copy_absolute(get_script().resource_path, folder + "/verify.gd")
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", folder, "--script", folder + "/verify.gd", "--", args[0], "isolated"], output, true)
		for line: String in output:
			print(line)
		quit(result)
		return
	if not ProjectSettings.load_resource_pack(args[0]):
		push_error("Unable to mount " + args[0])
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu_manifest.json"))
	var expected: Array = [manifest.catalog, manifest.locale, manifest.sounds, manifest.font, manifest.background]
	expected.append_array(manifest.scenes)
	expected.append_array(manifest.scripts)
	expected.append_array(manifest.textures)
	expected.append_array(manifest.audio.values())
	expected.append_array(manifest.atlases.values())
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/manifest.json"))
	expected.append_array(level.resources)
	expected.append_array(level.data)
	expected.append("res://data/level01/manifest.json")
	expected.append("res://scripts/battle/level01_sim.gd")
	expected.append("res://scripts/battle/battle_view.gd")
	expected.append("res://scripts/battle/battle_ui.gd")
	expected.append("res://scripts/battle/dove_ui_layout.gd")
	expected.append("res://scripts/battle/dove_animation.gd")
	expected.append("res://scripts/battle/dove_projectile.gd")
	expected.append("res://scripts/battle/dove_unit_info.gd")
	var campaign_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_kr1/manifest.json"))
	expected.append_array(campaign_map.resources)
	expected.append_array(campaign_map.data)
	expected.append("res://data/map_kr1/manifest.json")
	var allowed_data := expected.duplicate()
	allowed_data.append("res://data/menu_manifest.json")
	var failures: Array[String] = []
	for path: String in expected:
		if path.ends_with(".json"):
			if not FileAccess.file_exists(path):
				failures.append("Missing JSON: " + path)
		elif not ResourceLoader.exists(path):
			failures.append("Missing resource: " + path)
	if load("res://scenes/app_root.tscn") == null:
		failures.append("Exported main scene or script dependencies failed to load")
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/definition.json"))
	if definition.waves.groups.size() != 7 or definition.waves.cash != 270:
		failures.append("First campaign data invalid")
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/atlas.json"))
	for frame: Dictionary in atlas.frames.values():
		if not ResourceLoader.exists(atlas.texture_directory + frame.sheet):
			failures.append("Missing first-level atlas " + frame.sheet)
	var sim_script = load("res://scripts/battle/level01_sim.gd")
	var map_definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_kr1/definition.json"))
	if map_definition.levels.size() != 27 or map_definition.animations.size() != 124:
		failures.append("Generation-one map data incomplete")
	var map_catalog = load("res://scripts/dove_asset_catalog.gd").new("res://data/map_kr1/catalog.json")
	var map_atlas: Dictionary = map_catalog.load_group("map_kr1")
	for frame: Dictionary in map_atlas.frames.values():
		if not ResourceLoader.exists(map_atlas.texture_directory + frame.sheet): failures.append("Missing map atlas " + frame.sheet)
	if map_catalog.get_frame("map_kr1", "map_background_kr1").is_empty(): failures.append("Map background unavailable")
	if sim_script == null: failures.append("First-level simulation cannot be loaded")
	else:
		var simulation = sim_script.new(definition)
		if simulation.towers.size() != 8: failures.append("Exported simulation initialization failed")
	var background := load(manifest.background) as Texture2D
	if background == null or background.get_size() != Vector2(1920, 1080):
		failures.append("Exported menu background or its atlas dependency failed to load")
	var files: Array[String] = []
	_collect("res://", files)
	files.erase("res://verify.gd")
	files.erase("res://project.godot")
	for path: String in files:
		if path.begins_with("res://assets/") and not path.trim_suffix(".import") in allowed_data:
			failures.append("Unexpected asset: " + path)
		for excluded: String in ["source_assets", "reports", "tests", "tools", "docs"]:
			if path.begins_with("res://" + excluded + "/"):
				failures.append("Excluded directory found: " + path)
	var report := {"passed": failures.is_empty(), "failures": failures, "files": files}
	var report_path := args[0].get_base_dir().path_join("pack_files.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("WEB_PACK_VERIFICATION: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " (", files.size(), " files)")
	quit(0 if failures.is_empty() else 1)


func _collect(path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(path)
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if directory.current_is_dir():
				_collect(child, output)
			else:
				output.append(child)
		entry = directory.get_next()
	directory.list_dir_end()
