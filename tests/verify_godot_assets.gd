extends SceneTree
## Run after importing assets: --headless --path . --script tests/verify_godot_assets.gd

const Catalog = preload("res://scripts/dove_asset_catalog.gd")
var failures: PackedStringArray = []


func _init() -> void:
	call_deferred("_verify")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _verify() -> void:
	var assets := Catalog.new()
	check(assets.is_available(), "catalog unavailable")
	check(assets.list_groups().size() == 488, "expected 488 atlas groups")
	var sample: Dictionary = assets.get_frame("go_towers_group4", "soldier_lvl4_barbarian_0003")
	check(not sample.is_empty(), "soldier crop failed")
	if not sample.is_empty():
		check(sample["texture"] is AtlasTexture, "frame is not an AtlasTexture")
		check(sample["logical_size"].x > 0, "logical width must be positive")
	# This atlas intentionally has a 2x actual/declared texture size ratio.
	var group: Dictionary = assets.load_group("go_enemies_mactans_malicia")
	if not group.is_empty():
		var name: String = str(group["frames"].keys()[0])
		var frame: Dictionary = assets.get_frame("go_enemies_mactans_malicia", name)
		check(is_equal_approx(frame["region"].size.x, frame["source_region"].size.x * 2.0), "DDS UV scaling was lost")
		check(frame["logical_size"] == frame["source_region"].size, "logical frame size was changed")
	var animation: Dictionary = assets.get_animation("soldier_barbarian_running")
	check(animation.get("frames", []).size() == 5, "animation frame sequence failed")
	check(animation.get("fps", 0) == 30, "animation FPS changed")
	var composition: Dictionary = assets.get_exoskeleton("archer4Def")
	check(not composition.is_empty(), "EXO3 JSON failed")
	if not composition.is_empty():
		check(composition["entry_fields"][2] == "alpha", "composition float layout changed")
	var sounds: Dictionary = assets.get_sound("AmazonTaunt")
	check(sounds.get("paths", []).size() == 2, "sound mapping failed")
	if not sounds.is_empty():
		var sound: AudioStream = load(sounds["paths"][0]) as AudioStream
		check(sound != null and sound.get_length() > 0, "OGG loading failed")
	var font: Font = load(Catalog.ROOT + "all-desktop/fonts/msyh.ttc") as Font
	check(font != null, "TTC font loading failed")
	if font != null:
		check(font.has_char("国".unicode_at(0)), "Chinese font glyph missing")
	var chinese: Dictionary = assets.get_static("locale_zh-Hans")
	check(chinese.size() == 9516, "Chinese locale entries were lost")
	var has_placeholder: bool = false
	for value in chinese.values():
		if value is String and "%$" in value:
			has_placeholder = true
			break
	check(has_placeholder, "dynamic localization placeholders were lost")
	assets.clear_cache()
	check(not assets.get_animation("soldier_barbarian_running").is_empty(), "cache cannot be reloaded")
	var result: Dictionary = {"passed": failures.is_empty(), "failures": Array(failures), "godot": Engine.get_version_info()["string"]}
	var output: FileAccess = FileAccess.open("res://reports/godot_assets_verification.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result, "\t"))
	print("GODOT_ASSETS_VERIFICATION: ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
