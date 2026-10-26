extends SceneTree
## Targeted skill cooldown/disabled-input regression; native mode captures the HUD.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
class ObservedBattle extends Battle:
	var requested: Array[String] = []
	func _sound(id: String, limit_repeats: bool = true) -> void:
		requested.append(id); super._sound(id, limit_repeats)

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func click(battle: Control, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = point * battle.zoom
	battle._gui_input(event)

func capture(battle: Control, label: String) -> void:
	battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var path := "power_feedback_" + label + ".png"
	root.get_texture().get_image().save_png("res://reports/" + path); captures.append(path)

func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Power feedback timeout"); quit(1))
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://power_feedback_settings_" + token + ".json"
	app.progress_path = "user://power_feedback_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready; app.menu.hide(); app.menu.set_process_input(false)
	var battle := ObservedBattle.new(); app.add_child(battle)
	battle.initialize(app.loader, app.audio, Levels.load_definition(2))
	battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui: RefCounted = battle.interface
	for power: String in ["fire", "reinforcements"]:
		var prefix := "fire" if power == "fire" else "reinforcements"
		var ready := "fire_ready" if power == "fire" else "reinforcement_ready"
		battle._action("restart"); battle.sim.notices.clear(); battle.requested.clear()
		check(ui.power_frame(power, 0) == ready + "_0030", "pre-wave skill is visibly locked")
		check(battle.sim.command("wave") and battle.sim.unlocked[power], "first wave unlocks skill")
		check(ui.power_frame(power, 0.1) == ready + "_0030", "first-wave unlock uses source door animation")
		ui.power_at[power] = -1.0
		check(ui.power_frame(power, 0.2) == prefix + "_0001", "first-wave unlock settles on available art")
		battle.sim.cooldowns[power] = 30
		check(ui.power_frame(power, 1) == prefix + "_0001", "cooldown keeps normal art under timer mask")
		battle.sim.cooldowns[power] = 0
		check(ui.power_frame(power, 2) == ready + "_0001", "cooldown completion starts source ready flash")
		for elapsed in [0.1, 0.4, 0.8]:
			var frame: String = ui.power_frame(power, 2 + elapsed)
			check(frame.begins_with(ready) and int(frame.right(4)) <= 28, "refresh uses ready frames, never unlock doors")
		check(ui.power_frame(power, 3) == prefix + "_0001", "refresh settles on normal skill art")
		check(battle.requested.count("GUISpellRefresh") == 1, "refresh sound plays once per cooldown")
		battle.hovered = "target" + str({"power": power})
		check(ui.power_frame(power, 4) == prefix + "_0002", "ready hover artwork remains available")
		battle.targeting = power; check(ui.power_frame(power, 5) == ready + "_0029", "selected artwork preserved")
		battle.targeting = ""; battle.hovered = ""
		check(ui.power_frame(power, 6) == prefix + "_0001", "deselection never replays unlock or refresh")
		battle.sim.unlocked[power] = false; ui.power_frame(power, 7)
		battle.sim.unlocked[power] = true
		check(ui.power_frame(power, 8) == ready + "_0030" and ui.power_frame(power, 8.6) == prefix + "_0001", "door animation reserved for first tutorial unlock")
		battle.sim.cooldowns[power] = 60; battle.targeting = "rally"; battle.selected_unit = 42
		battle.requested.clear(); battle.message = ""; battle.message_time = 0
		battle.hits = [{"rect": Rect2(10,10,60,60), "action":"target", "args":{"power":power}, "enabled":false}]
		click(battle, Vector2(30,30))
		check(battle.message_time == 0 and battle.targeting == "rally" and battle.sim.cooldowns[power] == 60, "disabled click is silent, consumes input and never casts")
		battle._action("target", {"power":power})
		check(battle.requested.is_empty() and battle.selected_unit == 42 and battle.targeting == "rally", "cooling shortcut preserves selection and emits no feedback")
	# Early-wave bonuses that finish a cooldown follow the same ready transition.
	battle._action("restart"); battle.sim.notices.clear(); battle.sim.unlocked.fire = true; battle.sim.cooldowns.fire = 30
	ui.power_frame("fire", 0); battle.sim.wave = 1; battle.sim.next_wave_tick = 300
	battle.sim.command("wave")
	check(ui.power_frame("fire", 1) == "fire_ready_0001", "early-wave cooldown completion also avoids door animation")
	var native := DisplayServer.get_name() != "headless"
	if native:
		battle._action("restart"); battle.sim.notices.clear(); battle.sim.wave = 1
		battle.sim.unlocked = {"fire":true, "reinforcements":true}; battle.sim.cooldowns = {"fire":90, "reinforcements":90}
		await capture(battle, "cooldown")
		for power: String in ["fire", "reinforcements"]:
			var hit: Dictionary = battle.hits.filter(func(entry): return entry.action == "target" and entry.args.power == power)[0]
			check(not hit.enabled, "native cooldown button is disabled")
			click(battle, hit.rect.get_center())
			check(battle.message_time == 0 and battle.targeting == "", "native disabled button click shows no message")
		battle.sim.cooldowns = {"fire":0, "reinforcements":0}; battle.requested.clear()
		await capture(battle, "refresh")
		check(battle.requested.count("GUISpellRefresh") == 2 and battle.sound_cache.has("GUISpellRefresh"), "native source refresh sound requested for both powers")
		for power: String in ["fire", "reinforcements"]: ui.power_at[power] -= 1.0
		await capture(battle, "ready")
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed":failures.is_empty(), "checks":checks, "failures":failures, "native":native, "captures":captures, "scope":"skill ready transitions and disabled input only"}
	var file := FileAccess.open("res://reports/power_feedback_" + ("native" if native else "logic") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("POWER_FEEDBACK: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
