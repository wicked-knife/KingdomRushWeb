extends SceneTree
## Targeted regressions from Dove 2.1.0.3: y_enemy_stun, soldier_regen,
## mod_healing_paladin and systems/render.lua's health-bar branch.
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Setup = preload("res://scripts/services/battle_setup.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const UnitInfo = preload("res://scripts/battle/dove_unit_info.gd")
var checks := 0
var failures: Array[String] = []
var observations: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func fresh():
	var definition := Setup.create(Levels.load_definition(6), {"heroes":{"selected":["hero_malik"]}})
	var sim = Sim.new(definition, 42)
	sim.notices.clear(); sim.alerts.clear(); sim.spawn_queue.clear(); sim.soldiers.clear(); sim.gold = 10000
	return sim

func stuns() -> void:
	for name in ["enemy_goblin", "enemy_ogre", "enemy_shaman", "enemy_shadow_archer"]:
		var sim = fresh()
		var enemy: Dictionary = sim._spawn_enemy(name, 0)
		enemy.node = 40; enemy.pos = sim.vec(sim.data.paths.paths[0][0][40])
		sim.step()
		check(str(enemy.state).begins_with("walking") and enemy.last_dir != Vector2.ZERO, name + " starts walking")
		var position: Vector2 = enemy.pos
		check(sim.modifiers.apply(sim, "mod_malik_stun", enemy, 1, "hero"), name + " stun applies")
		var expires: int = sim.modifiers.active[-1].expires
		sim.step()
		check(enemy.state == "idle" and enemy.pos == position and enemy.last_dir == Vector2.ZERO, name + " stunned movement switches to source idle")
		for frame in 10: sim.step()
		check(enemy.state == "idle" and enemy.pos == position, name + " remains idle during stun")
		sim.tick = expires - 1; sim.step()
		check(enemy.stun_count == 0 and enemy.pos != position and str(enemy.state).begins_with("walking"), name + " walks again after stun expires")
		observations.append({"enemy":name, "stun_expires":expires, "resumed":enemy.state})
	var sim = fresh()
	var enemy: Dictionary = sim._spawn_enemy("enemy_goblin", 0)
	sim.modifiers.apply(sim, "mod_malik_stun", enemy, 1, "hero")
	sim.damage(enemy, 9999, 1); sim.step()
	check(enemy.state == "death", "stun never replaces death animation with idle")

func overheal() -> void:
	var sim = fresh()
	check(sim.command("build", {"id":"1", "type":"barrack"}), "build barracks")
	for frame in 30: sim.step()
	for target in ["tower_barrack_2", "tower_barrack_3", "tower_paladin"]:
		check(sim.command("upgrade", {"id":"1", "upgrade_to":target}), "upgrade " + target)
	for level in 3: check(sim.command("upgrade_power", {"id":"1", "power":"healing"}), "buy healing rank " + str(level + 1))
	for frame in 100: sim.step()
	var soldier: Dictionary = sim.soldiers.filter(func(s): return s.home == "1")[0]
	sim.soldiers = [soldier]
	soldier.pos = soldier.dest; soldier.rallying = false; soldier.hp = 170; sim.tick = 400
	sim._soldier_step(soldier)
	check(soldier.state == "healing", "source threshold starts healing")
	for frame in 16: sim.step()
	check(soldier.hp == 170, "no healing before frame seventeen")
	sim.step()
	var healed: float = soldier.hp
	check(healed >= 302 and healed <= 368, "rank three healing exceeds maximum HP")
	for frame in 180: sim.step()
	check(soldier.hp == healed, "idle regeneration preserves overflow across repeated regen intervals")
	var info := UnitInfo.snapshot(soldier, sim.templates, sim.data.ui.strings)
	check(info.hp == healed and info.hp_max == 250, "selection retains actual current HP and original maximum")
	check(sim.damage(soldier, 20, 1) == 20 and soldier.hp == healed - 20, "incoming damage consumes overflow first")
	for frame in 180: sim.step()
	check(soldier.hp == healed - 20, "idle regeneration also preserves damaged overflow")
	soldier.hp = 240; soldier.healing_at = sim.tick; soldier.regen_at = sim.tick; soldier.last_hit = 0
	sim.step()
	check(soldier.hp == soldier.max_hp, "ordinary idle regeneration still heals and caps at maximum")
	observations.append({"scenario":"paladin_healing_and_regeneration", "healed_hp":healed, "max_hp":soldier.max_hp})

func run() -> void:
	stuns(); overheal()
	var hashes := {}
	for path in ["tests/verify_stun_overheal.gd", "scripts/battle/level01_sim.gd", "scripts/battle/battle_view.gd", "scripts/battle/dove_paladin.gd", "scripts/battle/dove_modifiers.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	preload("res://tests/report_writer.gd").json_file("res://reports/stun_overheal_logic.json", {"passed":failures.is_empty(), "checks":checks, "independent_scenarios":6, "observations":observations, "failures":failures, "source_hashes":hashes})
	print("STUN_OVERHEAL ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)
