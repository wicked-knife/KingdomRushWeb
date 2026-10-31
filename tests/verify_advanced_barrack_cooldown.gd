extends SceneTree
## Exercise real sim.step -> soldier_step -> attack selection, without _begin shortcuts.
## Dove all/script_utils.lua:soldier_pick_melee_attack prefers a shared parent
## cooldown, then the attack's own cooldown, then zero; the boundary is strict.
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
var failures: Array[String] = []
var checks := 0
var observations: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func exercise(label: String, name: String, powers: Array, index: int, animation: String, first_tick: int, probe: String = "") -> void:
	var sim = Sim.new(Levels.load_definition(8), 42)
	sim.notices.clear(); sim.alerts.clear(); sim.towers.clear()
	var enemy: Dictionary = sim._spawn_enemy("enemy_goblin", 0)
	enemy.node = 40; enemy.pos = sim.vec(sim.data.paths.paths[0][0][40])
	enemy.hp = 100000; enemy.max_hp = enemy.hp; enemy.stun_count = 1
	var soldier: Dictionary = sim._soldier(name, "", 0, enemy.pos, enemy.pos)
	for power: String in powers: Sim.Behaviors.AdvancedBarrack._apply_power(sim, soldier, power, 1)
	var template: Dictionary = soldier.combat_template
	if name == "soldier_barbarian":
		check(not template.melee.attacks[1].has("cooldown"), label + ": real twister has no individual cooldown")
		if index == 1: template.melee.attacks[1].chance = 1.0 # Force this legal branch, independent of RNG.
		else: check(template.melee.attacks[1].disabled, label + ": twister remains locked")
	if probe == "own_only": template.melee.erase("cooldown")
	elif probe == "not_shared": template.melee.attacks[0].shared_cooldown = false
	elif probe == "no_cooldown":
		template.melee.erase("cooldown"); template.melee.attacks[0].erase("cooldown")
	soldier.target = enemy.id; enemy.blockers = [soldier.id]; enemy.blocker = soldier.id
	soldier.pos = sim.melee_slot(soldier, enemy); soldier.dest = soldier.pos; soldier.rallying = false
	var attacks: Array = []
	sim.event.connect(func(kind: String, payload: Dictionary):
		if kind == "advanced_barrack_attack": attacks.append(payload.duplicate(true)))
	sim.tick = maxi(0, first_tick - 2)
	if first_tick > 1:
		sim.step()
		check(attacks.is_empty(), label + ": no attack at source cooldown boundary")
	sim.step()
	check(not attacks.is_empty(), label + ": normal soldier update starts attack after cooldown")
	if attacks.is_empty(): return
	check(attacks[0].tick == first_tick and attacks[0].index == index and attacks[0].state == animation, label + ": source attack choice and first tick")
	var hp: float = enemy.hp
	while enemy.hp == hp and sim.tick < first_tick + 30: sim.step()
	check(enemy.hp < hp, label + ": chosen attack reaches its hit")
	check(soldier.melee_ts[index] == first_tick, label + ": hit commits attack start timestamp")
	if template.melee.attacks[index].get("shared_cooldown", false):
		check(soldier.melee_ts[0] == soldier.melee_ts[1], label + ": shared attacks commit the same cooldown")
	if first_tick > 1:
		while sim.tick < first_tick * 2 - 1: sim.step()
		check(attacks.size() == 1, label + ": shared or individual cooldown blocks an early second attack")
		sim.step()
		check(attacks.size() == 2 and attacks[1].tick == first_tick * 2, label + ": second attack becomes ready at source boundary")
	observations.append({"scenario":label, "first_tick":first_tick, "attacks":attacks, "damage":hp-enemy.hp})

func run() -> void:
	create_timer(15.0).timeout.connect(func(): push_error("Cooldown regression aborted before completion"); quit(1))
	exercise("locked twister", "soldier_barbarian", [], 0, "attack", 42)
	exercise("dual axes", "soldier_barbarian", ["dual"], 0, "attack2", 42)
	exercise("twister", "soldier_barbarian", ["twister"], 1, "twister", 42)
	exercise("dual twister", "soldier_barbarian", ["dual", "twister"], 1, "twister2", 42)
	exercise("Sasquatch own cooldown", "soldier_sasquash", [], 0, "attack", 76)
	exercise("missing parent cooldown", "soldier_barbarian", [], 0, "attack", 31, "own_only")
	exercise("non-shared cooldown", "soldier_barbarian", [], 0, "attack", 31, "not_shared")
	exercise("source zero fallback", "soldier_barbarian", [], 0, "attack", 1, "no_cooldown")
	var hashes := {}
	for path: String in ["tests/verify_advanced_barrack_cooldown.gd", "scripts/battle/dove_advanced_barrack.gd", "scripts/battle/level01_sim.gd", "data/level08/definition.json"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	preload("res://tests/report_writer.gd").json_file("res://reports/advanced_barrack_cooldown.json", {"passed":failures.is_empty(), "checks":checks, "independent_scenarios":8, "observations":observations, "failures":failures, "source_hashes":hashes})
	print("ADVANCED_BARRACK_COOLDOWN: ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)
