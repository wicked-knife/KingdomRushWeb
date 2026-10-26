extends SceneTree
## Focused regression for early-wave HUD feedback; --visual adds four native captures.
const App = preload("res://scenes/app_root.tscn")
const Battle = preload("res://scripts/battle/battle_view.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var battle: Control

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func prepare(seconds: float, fire: int = 900, reinforcements: int = 150) -> void:
	battle._action("restart"); battle.sim.notices.clear()
	battle.sim.wave = 1; battle.sim.next_wave_tick = roundi(seconds * 30)
	battle.sim.cooldowns = {"fire": fire, "reinforcements": reinforcements}
	battle.message = ""; battle.message_time = 0

func _capture(label: String) -> void:
	battle.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var path := "wave_reward_" + label + ".png"
	root.get_texture().get_image().save_png("res://reports/" + path); captures.append(path)

func _run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Wave reward test timeout"); quit(1))
	var app := App.instantiate(); var token := str(Time.get_ticks_usec())
	app.settings_path = "user://wave_reward_settings_" + token + ".json"
	app.progress_path = "user://wave_reward_progress_" + token + ".json"
	root.add_child(app); await app.menu_ready
	app.menu.hide(); app.menu.set_process_input(false)
	battle = Battle.new(); app.add_child(battle)
	battle.initialize(app.loader, app.audio, Levels.load_definition(2))
	battle.set_process(false); battle.set_process_input(false); battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sim: RefCounted = battle.sim
	var ui: RefCounted = battle.interface
	# The three bundles share this composition and must all supply the sprite digits.
	for id in [1, 2, 3]:
		var atlas := Levels.read_json("res://data/level%02d/atlas.json" % id)
		var complete := true
		for n in range(14): complete = complete and atlas.lookup.has("nextwave_coin_%04d" % (n + 1))
		for n in range(12):
			if n != 10: complete = complete and atlas.lookup.has("waveReward_%04d" % n)
		for n in range(13):
			if n != 10: complete = complete and atlas.lookup.has("waveRewardTimer_%04d" % n)
		check(complete, "reward artwork complete level %d" % id)
		check(Levels.read_json("res://data/level%02d/sounds.json" % id).has("GUICoins"), "coin sound present level %d" % id)
	prepare(10)
	var gold: int = sim.gold
	check(sim.command("wave"), "legal early-wave command accepted")
	check(sim.gold == gold + ceili(10 * float(sim.data.rules.early_wave_reward_per_second)), "gold bonus preserved")
	check(sim.cooldowns.fire == 600 and sim.cooldowns.reinforcements == 0, "cooldown reduction clamps at zero")
	check(ui.reward_fx.size() == 3, "gold and both previously cooling powers animate")
	check(ui.reward_fx[1].text == "-10s" and ui.reward_fx[2].text == "-10s", "source bonus seconds appear even when power becomes ready")
	check(battle.message_time == 0 and battle.message == "", "early reward emits no central prose message")
	var start: Vector2 = ui.reward_bounds(ui.reward_fx[1]).position
	for width in [1024.0, 1365.333, 1536.0]:
		battle.view_width = width
		check(ui.reward_fx.all(func(fx): return Rect2(0, 0, width, 768).encloses(ui.reward_bounds(fx))), "reward bounds fit HUD width %s" % width)
	ui.advance_rewards(0.35)
	check(ui.reward_bounds(ui.reward_fx[1]).position.y < start.y, "cooldown digits float upward")
	ui.advance_rewards(0.66)
	check(ui.reward_fx.size() == 1 and ui.reward_fx[0].power == "", "cooldown effects expire after one second")
	ui.advance_rewards(0.5); check(ui.reward_fx.is_empty(), "gold effect expires after 1.5 seconds")
	prepare(8, 0, 600); sim.command("wave")
	check(ui.reward_fx.size() == 2 and ui.reward_fx[1].power == "reinforcements", "ready powers do not show cooldown reward")
	prepare(8); sim.unlocked.fire = false; sim.command("wave")
	check(ui.reward_fx.size() == 2 and ui.reward_fx[1].power == "reinforcements", "locked powers do not show cooldown reward")
	prepare(1); sim.command("wave")
	check(ui.reward_fx.size() == 1 and ui.reward_fx[0].power == "", "source suppresses timer reward at one second")
	prepare(0.1); gold = sim.gold; sim.command("wave")
	check(ui.reward_fx.is_empty() and sim.gold == gold, "rounded-zero reward creates no effects")
	prepare(10); sim._start_wave(false)
	check(ui.reward_fx.is_empty(), "automatic wave has no reward effects")
	prepare(10); sim.wave = 0; sim.command("wave")
	check(ui.reward_fx.is_empty(), "first wave has no reward effects")
	prepare(10); sim.command("wave"); battle._action("restart")
	check(ui.reward_fx.is_empty(), "restart clears in-flight rewards")
	prepare(10); sim.command("wave")
	sim.spawn_queue.clear(); sim.next_wave_tick = sim.tick + 150; sim.command("wave")
	check(ui.reward_fx.size() == 5, "successive bonuses have independent lifetimes")
	ui.advance_rewards(2); check(ui.reward_fx.is_empty(), "successive effects all release")
	if "--visual" in OS.get_cmdline_user_args():
		prepare(10); battle._action("wave"); battle.interface.wave_flags.sync()
		await _capture("start")
		ui.advance_rewards(0.35); battle.interface.wave_flags.advance(0.35); await _capture("floating")
		ui.advance_rewards(0.75); battle.interface.wave_flags.advance(0.75); await _capture("gold_fading")
		ui.advance_rewards(0.41); await _capture("finished")
	var visual := not captures.is_empty()
	app.queue_free(); await process_frame; await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures,
		"scope": "early-wave rewards only", "native": visual}
	var file := FileAccess.open("res://reports/wave_rewards_" + ("native" if visual else "logic") + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("WAVE_REWARDS: ", JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
