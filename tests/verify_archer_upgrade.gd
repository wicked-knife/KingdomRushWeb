extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Arena = preload("res://tests/archer_upgrade_arena.gd")
const Sprites = preload("res://scripts/battle/dove_animation.gd")
const UPGRADE := {"id": "8", "upgrade_to": "tower_archer_2"}
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func dismiss(sim) -> void:
	while not sim.notices.is_empty(): sim.command("confirm")

func fresh() -> RefCounted:
	var sim = Sim.new(Arena.definition())
	dismiss(sim)
	check(sim.command("build", {"id": "8", "type": "archer"}), "fixture builds first tier")
	for i in range(25): sim.step()
	return sim

func denied(sim, args: Dictionary, label: String) -> void:
	var before: Array = [sim.gold, sim.towers.duplicate(true), sim.projectiles.duplicate(true), sim.effects.duplicate(true)]
	check(not sim.command("upgrade", args), label + " rejected")
	check(before == [sim.gold, sim.towers, sim.projectiles, sim.effects], label + " leaves state untouched")

func enemy_at(sim, offset: Vector2) -> Dictionary:
	var e: Dictionary = sim._spawn_enemy("enemy_fat_orc", 0)
	e.pos = sim.tower_by_id("8").pos + offset
	e.hp = 10000; e.max_hp = 10000
	return e

func _run() -> void:
	var data := Arena.definition()
	var sim = Sim.new(data)
	check(not sim.tower_locked("tower_archer_2") and sim.tower_locked("tower_mage_2"), "arena only unlocks archer two")
	data.layout.level_mode_overrides[0].locked_towers.append("tower_archer_2")
	check(not sim.tower_locked("tower_archer_2"), "simulation owns a deep rules copy")
	denied(sim, UPGRADE, "tutorial")
	dismiss(sim)
	denied(sim, UPGRADE, "empty holder")
	denied(sim, {"id": "missing", "upgrade_to": "tower_archer_2"}, "unknown holder")
	check(sim.command("build", {"id": "8", "type": "archer"}), "build before construction guard")
	denied(sim, UPGRADE, "under construction")
	for i in range(25): sim.step()
	sim.gold = 109; denied(sim, UPGRADE, "109 gold")
	sim.gold = 110
	denied(sim, {"id": "8", "upgrade_to": "tower_archer_3"}, "tier three")
	denied(sim, {"id": "8", "upgrade_to": "tower_mage_1"}, "cross family")
	denied(sim, {"id": "8"}, "missing target")
	sim.command("pause"); denied(sim, UPGRADE, "paused"); sim.command("pause")
	var original: Dictionary = sim.tower_by_id("8").duplicate(true)
	check(sim.command("upgrade", UPGRADE) and sim.gold == 0, "exactly 110 gold succeeds once")
	var tower: Dictionary = sim.tower_by_id("8")
	check(tower.template == "tower_archer_2" and tower.spent == 180, "template and cumulative investment committed")
	check(tower.id == original.id and tower.pos == original.pos and tower.holder == original.holder and tower.rally == original.rally, "holder position terrain and rally preserved")
	denied(sim, UPGRADE, "duplicate upgrade")
	sim.result = "victory"; denied(sim, UPGRADE, "finished battle")
	sim.reset(); dismiss(sim)
	check(sim.gold == 270 and sim.towers.all(func(t): return t.type == "" and t.spent == 0), "reset clears tier and investment")
	check(not sim.tower_locked("tower_archer_2"), "arena rules survive reset")
	sim.command("build", {"id": "8", "type": "mage"})
	for i in range(25): sim.step()
	denied(sim, UPGRADE, "non archer tower")

	# Real first-level rules cannot be bypassed through the command bus or debug gold.
	sim = Sim.new({}, 1, true); dismiss(sim)
	sim.command("build", {"id": "8", "type": "archer"})
	for i in range(25): sim.step()
	sim.command("dev_add_gold"); denied(sim, UPGRADE, "campaign lock with debug gold")
	for target in ["tower_archer_2", "tower_barrack_2", "tower_mage_2", "tower_engineer_2"]:
		check(sim.tower_locked(target), "campaign lock " + target)
	for i in range(3):
		sim.reset(); dismiss(sim)
		check(sim.tower_locked("tower_archer_2") and sim.gold == 270, "campaign reset isolation %d" % i)
	check(Sim.new().tower_locked("tower_archer_2"), "new campaign after arena remains locked")

	sim = fresh()
	sim.notices.append("TIP_ARMOR"); denied(sim, UPGRADE, "modal notice on completed tower"); dismiss(sim)
	sim.result = "defeat"; denied(sim, UPGRADE, "finished battle with eligible first tier")
	sim = fresh()
	var target: Dictionary = enemy_at(sim, Vector2(150, 0))
	sim._tower_step(sim.tower_by_id("8"))
	check(sim.tower_by_id("8").pending.is_empty(), "tier one cannot reach 150")
	check(sim.command("upgrade", UPGRADE), "combat upgrade")
	tower = sim.tower_by_id("8")
	var upgraded_at: int = sim.tick
	var definition: Dictionary = sim.tower_template(tower)
	check(definition.attacks.range == 160 and definition.tower.level == 2 and definition.tower.price == 110, "source tier two attributes")
	check(definition.render.sprites[1].name == "archer_tower_0002" and definition.render.sprites[2].offset.y == 52, "source tier two body and shooter height")
	for i in range(17): sim.tick += 1; sim._tower_step(tower)
	check(tower.pending.is_empty(), "new tower waits full cooldown")
	sim.tick += 1; sim._tower_step(tower)
	check(sim.tick - upgraded_at == 18 and tower.pending.target == target.id, "18 frame cooldown and upgraded range")
	check(tower.layers.has(4) and not tower.layers.has(3) and tower.pending.offset.x == 10, "first shot belongs to right archer")
	var shot_at: int = sim.tick
	for i in range(4): sim.tick += 1; sim._tower_step(tower)
	check(sim.projectiles.is_empty(), "no projectile before frame five")
	sim.tick += 1; sim._tower_step(tower)
	check(sim.projectiles.size() == 1 and sim.projectiles[0].template == "arrow_2" and sim.projectiles[0].duration == 21, "frame five emits 21 frame arrow two")
	check(sim.projectiles[0].from == tower.pos + Vector2(10, 50), "right archer muzzle preserves source offset")
	while sim.tick < shot_at + 18: sim.tick += 1; sim._tower_step(tower)
	check(tower.layers.has(3) and tower.pending.offset.x == -10 and tower.shot_at - shot_at == 18, "next shot alternates after 18 frames")
	for direction in ["Down", "Up"]:
		var animation: Dictionary = sim.animations["shooterarcherlvl2_shooting" + direction]
		check(animation.frames.size() == 8, "full eight frame " + direction + " animation")
		for frame in range(8):
			var name := Sprites.frame(definition.render.sprites[2], sim.animations, {"state": "shooting" + direction, "elapsed": frame, "loop": false})
			check(name == "tower_archer_lvl2_shooter_%04d" % (frame + (3 if direction == "Down" else 11)), "source attack frame %s %d" % [direction, frame])
	target.pos = tower.pos + Vector2(161, 0)
	check(sim._target(tower.pos + Vector2(0, 12), 160).is_empty(), "outside tier two range excluded")
	for delta in [Vector2(-70, 70), Vector2(70, 70), Vector2(-70, -30), Vector2(70, -30)]:
		target.pos = tower.pos + delta; tower.pending = {}; tower.attack_at = sim.tick
		sim._tower_step(tower)
		var sid: int = 3 if tower.pending.offset.x < 0 else 4
		check(tower.layers[sid].state == ("shootingUp" if delta.y > 50 else "shootingDown") and tower.layers[sid].flip == (delta.x < 0), "source facing and flip " + str(delta))

	# An upgrade discards the old wind-up while existing arrows retain their damage.
	sim = fresh(); target = enemy_at(sim, Vector2(60, 0)); tower = sim.tower_by_id("8")
	sim._tower_step(tower)
	check(not tower.pending.is_empty(), "old attack is winding up")
	check(sim.command("upgrade", UPGRADE) and sim.tower_by_id("8").pending.is_empty() and not sim.tower_by_id("8").has("layers"), "upgrade cancels old wind-up and animation")
	sim = fresh(); target = enemy_at(sim, Vector2(60, 0)); tower = sim.tower_by_id("8")
	sim._tower_step(tower)
	sim.tick += 5; sim._tower_step(tower)
	check(sim.projectiles.size() == 1 and sim.projectiles[0].template == "arrow_1", "old arrow launched")
	sim.command("upgrade", UPGRADE)
	check(sim.projectiles.size() == 1 and sim.projectiles[0].template == "arrow_1", "upgrade retains in-flight old arrow")
	var bullet: Dictionary = sim.projectiles[0]
	var hp: float = target.hp
	sim.tick = int(bullet.at) + int(bullet.duration); sim._bullet_step(bullet)
	check(hp - target.hp >= 2.8 - 0.0001 and hp - target.hp <= 5.6 + 0.0001, "old arrow retains 4-8 physical damage against armor")
	var damage_values: Array = []
	for i in range(40):
		hp = target.hp
		sim._projectile("arrow_2", target.id, target.pos + Vector2(0, 50), target.pos + Sim.vec(sim.templates[target.template].unit.hit_offset), 0.7)
		bullet = sim.projectiles.back(); sim.tick += 21; sim._bullet_step(bullet)
		var damage: float = hp - target.hp
		damage_values.append(damage)
		check(damage >= 5.6 - 0.0001 and damage <= 9.1 + 0.0001, "8-13 physical damage respects orc armor")
	check(damage_values.min() < damage_values.max(), "tier two damage is sampled rather than fixed")

	for type in Sim.TYPES:
		for started in [false, true]:
			sim = Sim.new(Arena.definition()); dismiss(sim)
			var price: int = sim.templates["tower_" + type + "_1"].tower.price
			sim.command("build", {"id": "8", "type": type})
			for i in range(25): sim.step()
			if started: sim.command("wave")
			var refund: int = roundi(price * 0.6) if started else price
			check(sim.sell_refund(sim.tower_by_id("8")) == refund, "refund quote " + type + str(started))
			var gold: int = sim.gold
			check(sim.command("sell", {"id": "8"}) and sim.gold == gold + refund, "refund transaction " + type + str(started))
			check(sim.tower_by_id("8").template == "tower_holder_grass" and sim.tower_by_id("8").spent == 0, "sale restores clean holder")
	for started in [false, true]:
		sim = fresh(); sim.command("upgrade", UPGRADE)
		if started: sim.command("wave")
		var gold: int = sim.gold
		check(sim.sell_refund(sim.tower_by_id("8")) == (108 if started else 180), "upgraded sale quote")
		check(sim.command("sell", {"id": "8"}) and sim.gold == gold + (108 if started else 180), "upgraded cumulative refund")
		check(not sim.command("sell", {"id": "8"}), "duplicate sale rejected")
		check(sim.command("build", {"id": "8", "type": "archer"}) and sim.tower_by_id("8").spent == 70 and sim.tower_by_id("8").template == "tower_archer_1", "rebuild does not retain second tier investment")
	sim = fresh(); sim.command("wave"); sim.tower_by_id("8").spent = 181
	check(sim.sell_refund(sim.tower_by_id("8")) == 109, "source rounding rather than floor")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "source_commit": sim.data.source.commit,
		"upgrade_price": 110, "investment": 180, "damage": [8, 13], "range": 160, "cooldown_frames": 18, "shoot_frame": 5, "flight_frames": 21, "refunds": [180, 108]}
	var file := FileAccess.open("res://reports/archer_upgrade_logic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ARCHER_UPGRADE: ", "PASS" if failures.is_empty() else str(failures), " checks=", checks)
	quit(0 if failures.is_empty() else 1)
