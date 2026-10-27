extends SceneTree
## Targeted settlement audio regression; native mode also checks real players.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
class ObservedBattle extends Battle:
	var requested: Array[String] = []
	func _sound(id: String, limit_repeats: bool = true) -> void:
		requested.append(id); super._sound(id, limit_repeats)

var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Victory audio timeout"); quit(1))
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://victory_audio_settings_" + token + ".json"
	app.slots_path = "user://victory_audio_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready
	app.menu.hide(); app.menu.set_process_input(false)
	var battle := ObservedBattle.new(); app.add_child(battle)
	battle.initialize(app.loader, app.audio, Levels.load_definition(2)); battle.set_process(false)
	for id in [1, 2, 3]:
		var sounds := Levels.read_json("res://data/level%02d/sounds.json" % id)
		var manifest := Levels.read_json("res://data/level%02d/manifest.json" % id)
		check(sounds.GUIQuestCompleted.files == ["Sound_QuestCompleted.ogg"] and not sounds.GUIQuestCompleted.loop, "source non-looping victory fanfare level %d" % id)
		check("res://assets/kingdom_rush/kr1-desktop/sounds/files/Sound_QuestCompleted.ogg" in manifest.resources, "victory fanfare in manifest level %d" % id)
	for stars in [1, 2, 3]:
		battle._action("restart"); battle.sim.notices.clear(); battle.requested.clear()
		battle.sim.lives = [5, 10, 20][stars - 1]; battle.sim._finish("victory")
		check(battle.requested == ["GUIQuestCompleted"], "completion cue plays once before stars %d" % stars)
		check(not app.audio.music_player.playing, "battle music stopped at victory")
		battle.sim._finish("victory")
		check(battle.requested.size() == 1, "repeated finish cannot replay fanfare")
		battle._advance_victory_audio(0.64)
		check(battle.requested.size() == 1, "star cue waits for source 0.65-second reveal")
		battle._advance_victory_audio(0.02)
		check(battle.requested.count("GUIWinStars") == 1, "first star cue starts at reveal")
		for i in range(1, stars):
			battle._advance_victory_audio(0.7)
			check(battle.requested.count("GUIWinStars") == i + 1, "star cues use source spacing")
		battle._advance_victory_audio(10)
		check(battle.requested.count("GUIWinStars") == stars, "cue count matches awarded stars")
	battle._action("restart"); battle.requested.clear(); battle._advance_victory_audio(10)
	check(battle.requested.is_empty() and battle.victory_elapsed < 0, "restart cancels pending result audio")
	battle.sim._finish("defeat")
	check(not "GUIQuestCompleted" in battle.requested, "defeat never plays victory fanfare")
	var native := DisplayServer.get_name() != "headless"
	if native:
		battle._action("restart"); battle.sim.notices.clear(); battle.requested.clear()
		battle._sound("GUIQuickMenuOpen"); battle.sim._finish("victory")
		var fanfare: AudioStream = battle.sound_cache.GUIQuestCompleted.streams[0]
		check(not fanfare.loop and battle.fx_players.any(func(p): return p.playing and p.stream == fanfare), "native fanfare stream is playing without looping")
		check(battle.fx_players.all(func(p): return not p.playing or p.stream == fanfare), "native combat sounds stopped before fanfare")
		app.audio.unlock()
		check(not app.audio.music_player.playing and app.audio.music_player.stream == null, "input audio unlock cannot restart battle music during results")
		battle.set_process(true); await create_timer(2.25).timeout
		check(battle.requested.count("GUIWinStars") == 3, "native process plays three timed star cues")
		battle._action("restart")
		check(app.audio.music_player.playing, "native restart restores preparation music")
		battle.set_process(false)
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "native": native, "scope": "victory audio only"}
	var file := FileAccess.open("res://reports/victory_audio_" + ("native" if native else "logic") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("VICTORY_AUDIO: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
