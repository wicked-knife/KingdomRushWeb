extends SceneTree
## Focused regression for targeting balloons and the shared music lifecycle.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Targeting/music timeout"); quit(1))
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://targeting_music_settings_" + token + ".json"
	app.slots_path = "user://targeting_music_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready
	app.menu.hide(); app.menu.set_process_input(false)
	for level in [2, 3]:
		var sim = Sim.new(Levels.load_definition(level), 7)
		var point: Vector2 = sim.towers[0].rally
		check(not sim.unlocked.fire and not sim.unlocked.reinforcements, "powers locked before first wave level %d" % level)
		check(not sim.command("cast", {"power":"fire", "pos":point}) and not sim.command("cast", {"power":"reinforcements", "pos":point}), "simulation rejects pre-wave powers level %d" % level)
		sim.notices.clear()
		check(sim.command("wave") and sim.wave == 1 and sim.unlocked.fire and sim.unlocked.reinforcements, "first wave unlocks both powers level %d" % level)
		check(sim.command("cast", {"power":"reinforcements", "pos":point}), "power works after first wave level %d" % level)
	var tutorial = Sim.new(Levels.load_definition(1), 7)
	tutorial.notices.clear(); check(tutorial.command("wave") and not tutorial.unlocked.fire and not tutorial.unlocked.reinforcements, "level one keeps tutorial power locks")
	for level in [1, 2, 3]:
		var battle := Battle.new(); app.add_child(battle)
		battle.initialize(app.loader, app.audio, Levels.load_definition(level))
		battle.set_process(false); battle.sim.notices.clear(); battle.sim.wave = 1
		for power: String in ["fire", "reinforcements"]:
			battle.targeting = power; battle.interface.begin(); battle.interface._balloons()
			check(battle.interface.paint.audit.all(func(item): return item.text not in ["单击道路", "CLICK ON THE ROAD"]), "targeting has no road balloon level %d %s" % [level, power])
		battle.queue_free(); await process_frame
	var audio: Node = app.audio
	var menu_stream: AudioStream = app.loader.resources[app.loader.manifest.audio.MusicMainMenu]
	check(menu_stream != null, "menu music resource loads")
	for level in [1, 2, 3]:
		var sounds := Levels.read_json("res://data/level%02d/sounds.json" % level)
		var manifest := Levels.read_json("res://data/level%02d/manifest.json" % level)
		for id: String in ["PrepMusic", "BattleMusic"]:
			var path := "res://assets/kingdom_rush/kr1-desktop/sounds/files/" + str(sounds[id].files[0])
			check(path in manifest.resources and load(path) is AudioStream, "%s loads from Web manifest level %d" % [id, level])
	audio.stop_music(); check(audio.music_player.stream == null and not audio.music_player.playing, "stop clears music stream")
	audio.play_music(menu_stream, 0.7)
	check(audio.music_player.stream == menu_stream and is_equal_approx(audio.music_player.volume_db, linear_to_db(0.7)), "shared music setter applies stream and gain")
	var revision: int = audio.music_revision
	audio.play_music(menu_stream, 0.8)
	check(audio.music_revision == revision + 1, "scene music replacement invalidates delayed retries")
	var touch := InputEventScreenTouch.new(); touch.pressed = true
	app._input(touch); check(audio.unlocked, "touch input unlocks Web audio")
	var native := DisplayServer.get_name() != "headless"
	if native:
		check(audio.music_player.playing, "native shared music player is active")
		await create_timer(0.2).timeout
		check(audio.music_player.get_playback_position() > 0, "native music playback advances")
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures, "native":native, "scope":"targeting balloon and music lifecycle only"}
	var file := FileAccess.open("res://reports/targeting_music_" + ("native" if native else "logic") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("TARGETING_MUSIC: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
