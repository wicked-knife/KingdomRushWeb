extends SceneTree

const Boot = preload("res://scripts/services/menu_boot_loader.gd")
const Settings = preload("res://scripts/services/menu_settings.gd")
const Art = preload("res://scripts/ui/menu_art.gd")
var failures: Array[String] = []
var observed_progress: Array[float] = []
var temporary_directory := "user://menu_test_" + str(Time.get_ticks_usec())


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _run() -> void:
	create_timer(15.0).timeout.connect(func():
		push_error("Menu bootstrap test timed out")
		quit(1)
	)
	DirAccess.make_dir_recursive_absolute(temporary_directory)
	var path := temporary_directory + "/settings.json"
	var settings := Settings.new()
	settings.initialize(path)
	check(settings.music_volume == 1.0 and settings.sfx_volume == 1.0, "missing settings defaults")
	settings.set_volumes(0.37, 0.0)
	var restored := Settings.new()
	restored.initialize(path)
	check(is_equal_approx(restored.music_volume, 0.37) and restored.sfx_volume == 0.0, "settings persist including mute")
	write_json(path, {"schema_version": 1, "music_volume": 5, "sfx_volume": -1})
	restored.initialize(path)
	check(restored.music_volume == 1.0 and restored.sfx_volume == 0.0, "out of range volumes clamp")
	write_json(path, {"schema_version": 1, "music_volume": "loud", "sfx_volume": true})
	restored.initialize(path)
	check(restored.music_volume == 1.0 and restored.sfx_volume == 1.0, "invalid volume types default")
	write_json(path, {"schema_version": 99})
	restored.initialize(path)
	check(not restored.notice.is_empty(), "unsupported settings schema notice")
	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	restored.initialize(path)
	check(restored.music_volume == 1.0 and not restored.notice.is_empty(), "malformed settings recover")
	restored.initialize(temporary_directory + "/missing_parent/settings.json")
	restored.set_volumes(0.42, 0.13)
	check(is_equal_approx(restored.music_volume, 0.42) and not restored.notice.is_empty(), "save failure retains session preferences")
	settings.free()
	restored.free()
	var boot := Boot.new()
	root.add_child(boot)
	await boot.initialize("res://data/absent_menu_manifest.json")
	check(boot.state == "failed", "missing manifest fails without hanging")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Boot.MANIFEST_PATH))
	var original: String = manifest.textures[0]
	manifest.textures[0] = "res://assets/kingdom_rush/absent_texture.png"
	write_json(temporary_directory + "/manifest.json", manifest)
	await boot.initialize(temporary_directory + "/manifest.json")
	check(boot.state == "failed" and "absent_texture" in boot.error_message, "missing resource has actionable failure")
	manifest.textures[0] = original
	write_json(temporary_directory + "/manifest.json", manifest)
	boot.progress_changed.connect(func(done: int, total: int, _description: String): observed_progress.append(float(done) / total))
	await boot.initialize(temporary_directory + "/manifest.json")
	check(boot.state == "ready" and boot.catalog != null, "retry reaches ready")
	var background: Texture2D = boot.resources.get(manifest.background)
	check(background != null and background.get_size() == Vector2(1920, 1080), "menu background loads at design size")
	check(observed_progress[-1] == 1.0, "progress completes")
	for index in range(1, observed_progress.size()):
		check(observed_progress[index] >= observed_progress[index - 1], "progress is monotonic")
	var padded := Art.texture(boot.catalog, "homeMenu_buttonsBg")
	check(padded.get_size() == Vector2(570, 448), "trimmed sprite restores original hit/layout size")
	check(padded.margin.position == Vector2(0, 13), "trim offset preserved")
	check(str(boot.locale.get("OPTIONS")) == "选项", "Chinese locale loads")
	boot.free()
	for filename: String in DirAccess.get_files_at(temporary_directory):
		DirAccess.remove_absolute(temporary_directory + "/" + filename)
	DirAccess.remove_absolute(temporary_directory)
	print("MENU_BOOTSTRAP_TESTS: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
