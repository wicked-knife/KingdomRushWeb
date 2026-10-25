extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Sprites = preload("res://scripts/battle/dove_animation.gd")
const Ballistics = preload("res://scripts/battle/dove_projectile.gd")
const UnitInfo = preload("res://scripts/battle/dove_unit_info.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); push_error(description)

func fresh():
	var sim = Sim.new({}, 42)
	while not sim.notices.is_empty(): sim.command("confirm")
	return sim

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var sim = fresh()
	sim.command("build", {"id": "4", "type": "barrack"})
	var tower: Dictionary = sim.tower_by_id("4")
	sim.event.connect(func(kind, payload):
		if kind == "sound" and payload.id == "GUITowerOpenDoor": set_meta("opened", int(get_meta("opened", 0)) + 1))
	for i in range(int(tower.ready)): sim.step()
	check(tower.door_state == "opening" and sim.soldiers.is_empty(), "wait for opening animation before spawning")
	for i in range(5): sim.step()
	check(tower.door_state == "open" and sim.soldiers.size() == 3, "three soldiers after five-frame door opening")
	for i in range(50): sim.step()
	check(tower.door_state == "closed", "door closes after hold and close animation")
	var close_at: int = tower.layers[3].at
	var sprite: Dictionary = sim.templates.tower_barrack_1.render.sprites[2]
	var closed_frame := Sprites.frame(sprite, sim.animations, {"state": "close", "loop": false, "elapsed": 4})
	for i in range(200):
		sim.step()
		check(tower.layers[3].at == close_at and Sprites.frame(sprite, sim.animations, {"state": "close", "loop": false, "elapsed": sim.tick - close_at}) == closed_frame, "closed door remains still %d" % i)
	check(int(get_meta("opened", 0)) == 1, "no repeated opening without casualties")
	var soldier: Dictionary = sim.soldiers[0]
	sim.damage(soldier, 999, 1)
	for i in range(310): sim.step()
	check(int(get_meta("opened", 0)) == 2 and sim.soldiers.filter(func(s): return s.hp > 0).size() == 3, "one casualty triggers one replenishment opening")
	check(sim.command("rally", {"id": "4", "pos": Vector2(478, 228)}), "rally accepted")
	for s: Dictionary in sim.soldiers:
		if s.hp <= 0: continue
		var origin: Vector2 = s.pos
		var end: Vector2 = s.dest
		var delta := end - origin
		for i in range(80):
			sim._soldier_step(s)
			check(absf(delta.cross(s.pos - origin)) < 0.02, "rally follows a straight segment")
		check(s.pos.distance_to(end) < 0.01 and not s.rallying, "rally arrives at source formation")
	# Changing rally during engagement releases both sides and suppresses reacquisition.
	var alive: Dictionary = sim.soldiers.filter(func(s): return s.hp > 0)[0]
	var enemy: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	enemy.pos = alive.pos; enemy.node = 110
	alive.target = enemy.id; enemy.blockers = [alive.id]; enemy.blocker = alive.id
	check(sim.command("rally", {"id": "4", "pos": Vector2(450, 228)}), "rally while blocked")
	check(enemy.blockers.is_empty() and alive.target == 0 and alive.pending.is_empty(), "rally clears pending melee and blocking")
	sim._soldier_step(alive)
	check(alive.target == 0 and alive.rallying, "moving rally does not reacquire nearby enemy")
	# Validate ballistics against source equations, direction and hide radii.
	for type: String in ["arrow_1", "bomb"]:
		sim = fresh()
		var bullet: Dictionary = sim.templates[type].bullet
		var from := Vector2(400, 320); var to := Vector2(520, 240)
		sim._projectile(type, 0, from, to, bullet.flight_time)
		var p: Dictionary = sim.projectiles[0]
		var seconds: float = p.duration / 30.0
		var midpoint := Ballistics.sample(p, bullet, seconds / 2)
		check(midpoint.pos.is_equal_approx(from.lerp(to, 0.5) + Vector2(0, -bullet.g * seconds * seconds / 8)), type + " source gravity parabola")
		check(Ballistics.sample(p, bullet, seconds).pos.is_equal_approx(to), type + " lands at aim")
		check(Ballistics.sample(p, bullet, 0).hidden and Ballistics.sample(p, bullet, seconds).hidden and not midpoint.hidden, type + " hides near muzzle/impact")
		if type == "arrow_1":
			check(midpoint.rotation > -PI / 2 and midpoint.rotation < PI / 2, "rightward arrow tangent")
			sim._projectile(type, 0, to, from, bullet.flight_time)
			var left := Ballistics.sample(sim.projectiles[1], bullet, seconds / 2)
			check(absf(left.rotation) > PI / 2, "leftward arrow tangent")
		else:
			check(is_equal_approx(midpoint.rotation, p.initial_rotation - bullet.rotation_speed * seconds / 2), "bomb uses source spin")
			for i in range(int(p.duration)): sim.step()
			check(sim.effects.any(func(e): return e.template == "fx_explosion_small") and sim.effects.any(func(e): return e.template == "decal_bomb_crater"), "bomb spawns explosion and crater without target")
			var fx_sprite: Dictionary = sim.templates.fx_explosion_small.render.sprites[0]
			check(sim.animations.has(Sprites.key(fx_sprite)) and sim.animations[Sprites.key(fx_sprite)].frames.size() == 18, "18-frame explosion dependency included")
			check(Vector2(fx_sprite.scale.x, fx_sprite.scale.y) == Vector2(0.9, 0.9), "source explosion scale")
			for i in range(18): sim.step()
			check(not sim.effects.any(func(e): return e.template == "fx_explosion_small") and sim.effects.any(func(e): return e.template == "decal_bomb_crater"), "explosion ends while crater remains")
			for i in range(75): sim.step()
			check(sim.effects.is_empty(), "crater expires after fade")
	sim = fresh()
	# Attack layer ownership: only alternating archer animates; artillery has 35 frames.
	sim.command("build", {"id": "8", "type": "archer"})
	for i in range(30): sim.step()
	enemy = sim._spawn_enemy("enemy_fat_orc", 0); tower = sim.tower_by_id("8")
	enemy.pos = tower.pos + Vector2(65, 0); enemy.node = 100
	sim._tower_step(tower)
	check(tower.layers.has(4) and not tower.layers.has(3) and tower.pending.offset.x == 10, "first shot comes from second archer only")
	tower.pending = {}; tower.attack_at = sim.tick; sim._tower_step(tower)
	check(tower.layers.has(3) and tower.pending.offset.x == -10, "next shot alternates archer and muzzle")
	check(sim.animations.towerengineerlvl1_layer1_shoot.frames.size() == 35, "complete artillery recoil/reload sequence")
	# Sheep click state is simulated, paused and reset with the campaign.
	sim = fresh()
	var sheep: Dictionary = sim.decals.filter(func(d): return d.template.begins_with("decal_sheep"))[0]
	for i in range(7): check(sim.command("decal_click", {"id": sheep.id}), "sheep click %d" % i)
	check(not sheep.removed and sheep.clicks == 7 and sim.effects.is_empty(), "seven clicks do not explode")
	sim.command("pause")
	check(not sim.command("decal_click", {"id": sheep.id}), "pause prevents sheep clicks")
	sim.command("pause"); sim.command("decal_click", {"id": sheep.id})
	check(sheep.removed and sim.effects.size() == 1, "eighth click removes sheep and creates one explosion")
	check(not sim.command("decal_click", {"id": sheep.id}) and sim.effects.size() == 1, "exploded sheep cannot trigger twice")
	sim.reset()
	check(sim.decals.all(func(d): return not d.removed and d.clicks == 0), "restart restores decorative state")
	# Picking and snapshots use source rectangles and live state, not cached UI values.
	sim = fresh(); enemy = sim._spawn_enemy("enemy_fat_orc", 0); enemy.pos = Vector2(500, 400)
	var stats := UnitInfo.snapshot(enemy, sim.templates, sim.data.ui.strings)
	check(stats.name == "兽人" and stats.hp_max == 132 and is_equal_approx(stats.armor, 0.3) and stats.lives == 1, "translated source enemy stats")
	check(UnitInfo.pick(sim.enemies, sim.templates, enemy.pos + Vector2(0, 10)) == enemy.id, "source enemy click rectangle")
	sim.damage(enemy, 10, 4)
	check(UnitInfo.snapshot(enemy, sim.templates, sim.data.ui.strings).hp == 122, "selected unit health refreshes")
	sim.damage(enemy, 999, 1)
	check(UnitInfo.snapshot(enemy, sim.templates, sim.data.ui.strings).is_empty() and UnitInfo.pick(sim.enemies, sim.templates, enemy.pos) == 0, "dead unit cannot stay selected")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	var file := FileAccess.open("res://reports/battle_details_logic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("BATTLE_DETAILS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
