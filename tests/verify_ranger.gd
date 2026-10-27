extends SceneTree
const Sim = preload("res://scripts/battle/level01_sim.gd")
const ArenaSim = preload("res://tests/ranger_arena_sim.gd")
const Arena = preload("res://tests/ranger_arena.gd")
const Ranger = preload("res://scripts/battle/dove_ranger.gd")
const Anim = preload("res://scripts/battle/dove_animation.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func advance(sim, ticks: int) -> void:
	for i in range(ticks): sim.step()
func fresh(upgraded: bool = true):
	var sim = ArenaSim.new(Arena.definition(),42)
	check(sim.command("build",{"id":"03","type":"archer"}),"build fixture")
	advance(sim,25)
	for id in ["tower_archer_2","tower_archer_3"]: check(sim.command("upgrade",{"id":"03","upgrade_to":id}),"upgrade fixture " + id)
	if upgraded: check(sim.command("upgrade",{"id":"03","upgrade_to":"tower_ranger"}),"ranger fixture")
	return sim
func target(sim, type: String = "enemy_ogre", offset: Vector2 = Vector2(0,90)) -> Dictionary:
	var e: Dictionary = sim._spawn_enemy(type,1,0)
	e.pos = sim.tower_by_id("03").pos + offset; e.hp = 10000; e.max_hp = 10000
	return e
func snapshot(sim) -> Array:
	return [sim.gold,sim.towers.duplicate(true),sim.projectiles.duplicate(true),sim.modifiers.active.duplicate(true),sim.rng.state,sim.next_id]
func reject(sim, kind: String, args: Dictionary, label: String) -> void:
	var before := snapshot(sim)
	check(not sim.command(kind,args),label + " rejected")
	check(snapshot(sim) == before,label + " atomic")

func transactions() -> void:
	var sim = fresh(false)
	var args := {"id":"03","upgrade_to":"tower_ranger"}
	sim.gold = 229; reject(sim,"upgrade",args,"ranger insufficient")
	sim.gold = 230; sim.paused = true; reject(sim,"upgrade",args,"ranger paused"); sim.paused = false
	check(sim.command("upgrade",args) and sim.gold == 0,"ranger exact funds")
	var tower: Dictionary = sim.tower_by_id("03")
	check(tower.spent == 570 and tower.type == "archer" and sim.upgrade_target(tower) == "","ranger cost/family/terminal")
	reject(sim,"upgrade",args,"duplicate upgrade")
	for power in ["poison","thorn"]:
		for level in range(1,4):
			var price := 225 if level == 1 else 175
			var command_args := {"id":"03","power":power}
			sim.gold = price - 1; reject(sim,"upgrade_power",command_args,power + " short " + str(level))
			sim.gold = price
			sim.paused = true; reject(sim,"upgrade_power",command_args,"skill paused"); sim.paused = false
			sim.notices.append("TEST"); reject(sim,"upgrade_power",command_args,"skill modal"); sim.notices.clear()
			check(sim.command("upgrade_power",command_args) and sim.gold == 0 and tower.powers[power] == level,power + " level " + str(level))
		check(sim.power_price(tower,power) == -1,power + " max quote")
		reject(sim,"upgrade_power",{"id":"03","power":power},power + " max rejected")
	check(tower.spent == 1720 and sim.sell_refund(tower) == 1720,"all skill costs in setup refund")
	sim.wave = 1; check(sim.sell_refund(tower) == 1032,"all skill costs in combat refund")
	sim.gold = 0; check(sim.command("sell",{"id":"03"}) and sim.gold == 1032,"sell commits quote")
	reject(sim,"upgrade_power",{"id":"03","power":"poison"},"empty tower skill")
	reject(sim,"upgrade_power",{"id":"missing","power":"poison"},"missing tower skill")
	reject(sim,"upgrade_power",{"id":"03","power":"other"},"unknown skill")
	for id in range(1,5):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level%02d/definition.json" % id))
		check(not d.templates.has("tower_ranger") and not d.has("upgrade_targets"),"campaign remains unchanged " + str(id))
		var campaign = Sim.new(d)
		check(not campaign.command("arena_gold") and not campaign.command("arena_spawn",{"type":"enemy_goblin"}),"no arena commands in campaign")

func poison() -> void:
	var sim = fresh(); var e := target(sim); var hp: float = e.hp
	check(sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"03"),"apply poison")
	check(is_equal_approx(sim.modifiers.speed(e.id,sim),0.9),"single slow")
	var born: int = sim.tick
	for dt in range(1,91):
		sim.tick = born + dt; sim.modifiers.step(sim)
		if dt in [1,30,31,60,61,89,90]:
			var hits := 1 if dt < 31 else (2 if dt < 61 else 3)
			check(e.hp == hp - hits * 5,"poison boundary " + str(dt))
	check(sim.modifiers.active.is_empty() and sim.modifiers.speed(e.id,sim) == 1,"poison expires restores speed")
	for i in range(4): check(sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"03"),"BASE duplicate " + str(i))
	check(not sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"03") and sim.modifiers.count(e.id,"mod_ranger_poison") == 4,"BASE fifth copy rejected")
	check(is_equal_approx(sim.modifiers.speed(e.id,sim),pow(0.9,4)),"multiplicative slow")
	check(sim.modifiers.apply(sim,"mod_ranger_poison",e,2,"03") and sim.modifiers.count(e.id,"mod_ranger_poison") == 1,"higher replaces lower")
	check(not sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"03"),"lower cannot replace higher")
	sim.modifiers.clear(sim)
	var spider := target(sim,"enemy_spider_small")
	check(not sim.modifiers.apply(sim,"mod_ranger_poison",spider,3,"03"),"spider poison immunity")
	e.hp = 1; sim.modifiers.apply(sim,"mod_ranger_poison",e,3,"03"); sim.tick += 1
	var kills: int = sim.kills; sim.modifiers.step(sim)
	check(e.hp == 0 and sim.kills == kills + 1 and not sim.modifiers.has(e.id,"mod_ranger_poison"),"poison kills once and cleans")
	sim.modifiers.step(sim); check(sim.kills == kills + 1,"no duplicate kill reward")

func shooting() -> void:
	var sim = fresh(); var tower: Dictionary = sim.tower_by_id("03"); var e := target(sim)
	var shots: Array = []
	sim.event.connect(func(kind,args):
		if kind == "ranger_shot": shots.append(args.duplicate()))
	for i in range(70): sim.tick += 1; Ranger.step(sim,tower)
	check(shots.size() >= 4,"source cadence produces shots")
	for i in range(shots.size()):
		check(shots[i].sid == 3 + i % 2,"alternating shooter " + str(i))
		if i > 0: check(shots[i].tick - shots[i-1].tick == 12,"strict 0.39 second cooldown")
	check(shots[0].tick == 25 + 12 + 4,"initial cooldown and windup")
	var e2 := target(sim,"enemy_fat_orc",Vector2(30,90))
	sim.gold = 10000; sim.command("upgrade_power",{"id":"03","power":"poison"})
	sim.projectiles.clear(); tower.pending = {}; tower.attack_at = sim.tick; tower.ranger.animation_until = sim.tick
	Ranger.step(sim,tower); var first: int = tower.pending.target
	sim.tick += 12; Ranger.step(sim,tower)
	check(not tower.pending.is_empty() and tower.pending.target != first,"poison reserves in-flight targets")
	var poison_bullet: Dictionary = sim.projectiles[0]
	check(poison_bullet.poison_level == 1 and poison_bullet.source == "03","projectile snapshots skill level")
	var victim: Dictionary = sim.unit_by_id(poison_bullet.target)
	poison_bullet.to = victim.pos + sim.vec(sim.templates[victim.template].unit.hit_offset)
	poison_bullet.from = poison_bullet.to; poison_bullet.at = sim.tick - poison_bullet.duration
	sim._bullet_step(poison_bullet)
	check(sim.modifiers.has(victim.id,"mod_ranger_poison"),"actual projectile applies poison")
	sim.command("sell",{"id":"03"}); sim.tick += 1; sim.modifiers.step(sim)
	check(sim.modifiers.has(victim.id,"mod_ranger_poison"),"sale keeps already applied poison")
	check(e2.hp > 0 and e.hp > 0,"controlled fixtures alive")

func thorn() -> void:
	for level in range(1,4):
		var sim = fresh(); var tower: Dictionary = sim.tower_by_id("03")
		for i in range(level): sim.command("upgrade_power",{"id":"03","power":"thorn"})
		var base: int = sim.tick
		for i in range(10): target(sim,"enemy_ogre",Vector2(i * 2,80))
		for dt in [269,270,286,287]:
			sim.tick = base + dt; Ranger._thorn(sim,tower,tower.pos + sim.vec(sim.tower_template(tower).tower.range_offset))
			check(sim.modifiers.active.size() == (2 + 2 * level if dt == 287 else 0),"thorn level/count/windup " + str(level) + "/" + str(dt))
		var m: Dictionary = sim.modifiers.active[0]; var e: Dictionary = sim.unit_by_id(m.target)
		check(e.stun_count == 1 and m.expires == sim.tick + 18 + level * 30,"thorn start animation and duration")
		var hp: float = e.hp
		sim.tick = m.loop_at + 14; sim.modifiers.step(sim); check(e.hp == hp,"no thorn damage before interval")
		sim.tick += 1; sim.modifiers.step(sim); check(e.hp == hp - 20,"thorn first damage")
		sim.tick = m.expires + 1; sim.modifiers.step(sim); check(e.stun_count == 1 and m.phase == "end","stun persists through free animation")
		sim.tick += 6; sim.modifiers.step(sim); check(e.stun_count == 0 and sim.modifiers.active.is_empty(),"thorn releases all stun references")
	var sim = fresh(); var tower: Dictionary = sim.tower_by_id("03")
	for i in range(3): sim.command("upgrade_power",{"id":"03","power":"poison"})
	sim.command("upgrade_power",{"id":"03","power":"thorn"})
	var e := target(sim); var e2 := target(sim,"enemy_ogre",Vector2(20,90))
	sim.modifiers.apply(sim,"mod_ranger_poison",e,3,"03")
	sim.tick += 270; Ranger._thorn(sim,tower,tower.pos)
	sim.tick += 17; Ranger._thorn(sim,tower,tower.pos)
	var roots: Array = sim.modifiers.active.filter(func(m): return m.template == "mod_thorn" and m.target == e.id)
	check(roots.size() == 1 and roots[0].expires - roots[0].loop_at == 75,"poison extends root by tower poison level")
	check(Ranger._thorn_targets(sim,tower,tower.pos,sim.templates.aura_ranger_thorn.aura).is_empty(),"shared per-target thorn cooldown")
	sim.modifiers.clear(sim)
	e.vis = {"flags":32,"bans":0}; e2.vis = {"flags":128,"bans":0}; sim.tick += 300
	check(Ranger._thorn_targets(sim,tower,tower.pos,sim.templates.aura_ranger_thorn.aura).is_empty(),"boss and flying bans")
	sim.command("arena_clear"); e = target(sim)
	tower.ranger.thorn_ts = float(sim.tick - 270); tower.ranger.casting = {}
	Ranger._thorn(sim,tower,tower.pos); check(tower.ranger.casting.is_empty(),"one target never triggers root")
	e2 = target(sim,"enemy_ogre",Vector2(20,90)); tower.ranger.thorn_ts = float(sim.tick - 270)
	Ranger._thorn(sim,tower,tower.pos); sim.damage(e2,100000,1); sim.tick += 17; Ranger._thorn(sim,tower,tower.pos)
	check(not sim.modifiers.has(e.id,"mod_thorn"),"recheck minimum targets at impact")

func arena_controls() -> void:
	var sim = fresh()
	check(sim.command("arena_spawn",{"type":"enemy_ogre","count":5,"path":1}),"manual group")
	advance(sim,61)
	check(sim.spawn_log.size() == 5 and sim.spawn_log[1].tick - sim.spawn_log[0].tick == 15 and sim.spawn_log.all(func(e): return e.path == 1),"manual spawn schedule")
	sim.paused = true; var tick: int = sim.tick; sim.advance(2); check(sim.tick == tick,"pause freezes state")
	check(not sim.command("arena_spawn",{"type":"enemy_goblin","count":1,"path":0}),"paused spawn rejected")
	sim.paused = false; sim.speed = 2; sim.advance(0.1); check(sim.tick == tick + 6,"double speed")
	var gold: int = sim.gold; var template: String = sim.tower_by_id("03").template
	sim.command("arena_clear")
	check(sim.enemies.is_empty() and sim.projectiles.is_empty() and sim.spawn_queue.is_empty() and sim.modifiers.active.is_empty() and sim.gold == gold and sim.tower_by_id("03").template == template,"clear preserves towers and gold")
	advance(sim,1000); check(sim.result == "" and sim.spawn_log.size() == 5,"no auto waves or victory")
	for i in range(3):
		sim.reset(42)
		check(sim.gold == 10000 and sim.lives == 100 and sim.wave == 0 and sim.tick == 0 and sim.modifiers.active.is_empty() and sim.towers.all(func(t): return t.type == ""),"complete reset " + str(i))
	var initial_decals: Array = sim.decals.duplicate(true); var initial_rng: int = sim.rng.state
	sim.reset()
	check(sim.decals == initial_decals and sim.rng.state == initial_rng,"default reset reproduces initial seed including ambient animations")

func movement_and_shared_status() -> void:
	var sim = fresh()
	var e: Dictionary = sim._spawn_enemy("enemy_goblin",1,0)
	var baseline: Dictionary = e.duplicate(true)
	var origin: Vector2 = e.pos
	sim._enemy_step(baseline)
	check(sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"03"),"moving poison from first tower")
	sim._enemy_step(e)
	check(is_equal_approx(e.pos.distance_to(origin),baseline.pos.distance_to(origin) * 0.9),"poison changes actual path movement")
	sim.tick += 30; sim.modifiers.step(sim)
	check(sim.modifiers.apply(sim,"mod_ranger_poison",e,1,"05"),"poison from another tower stacks")
	check(sim.modifiers.active.filter(func(m): return m.visible).size() == 1,"only newest poison sprite is visible")
	sim.tick += 60; sim.modifiers.step(sim)
	check(sim.modifiers.count(e.id,"mod_ranger_poison") == 1 and is_equal_approx(sim.modifiers.speed(e.id,sim),0.9),"older poison expiry preserves newer slow")
	sim.tick += 30; sim.modifiers.step(sim)
	check(sim.modifiers.speed(e.id,sim) == 1,"last poison expiry releases slow")
	e.pending = {"target":0}; e.casting = {"at":sim.tick}
	sim.modifiers.apply(sim,"mod_thorn",e,1,"03",1)
	check(e.pending.is_empty() and e.casting.is_empty(),"root interrupts pending attacks and casting")
	origin = e.pos; sim._enemy_step(e)
	check(e.pos == origin and sim._predict(e,1) == origin,"root prevents actual movement and prediction")
	sim.modifiers.clear(sim); sim._enemy_step(e)
	check(e.pos != origin and e.stun_count == 0,"root cleanup resumes movement")
	var armored := target(sim,"enemy_brigand")
	check(sim.damage(armored,10,2) == 5 and sim.damage(armored,10,65536 | 2048) == 10,"poison flags bypass physical armor")
	sim.templates.enemy_brigand.health.poison_armor = 0.25
	check(sim.damage(armored,20,65536 | 2048) == 15,"combined poison flags respect poison armor")
	# Two overlapping auras share protection stored on the enemy.
	sim.command("arena_clear")
	check(sim.command("build",{"id":"05","type":"archer"}),"second ranger build")
	advance(sim,25)
	for id in ["tower_archer_2","tower_archer_3","tower_ranger"]: check(sim.command("upgrade",{"id":"05","upgrade_to":id}),"second ranger " + id)
	for id in ["03","05"]: sim.command("upgrade_power",{"id":id,"power":"thorn"})
	e = target(sim); var e2 := target(sim,"enemy_ogre",Vector2(20,90))
	var tower: Dictionary = sim.tower_by_id("03"); var other: Dictionary = sim.tower_by_id("05")
	sim.tick += 270; Ranger._thorn(sim,tower,tower.pos)
	sim.tick += 17; Ranger._thorn(sim,tower,tower.pos)
	Ranger._thorn(sim,other,other.pos)
	check(sim.modifiers.count(e.id,"mod_thorn") == 1 and other.ranger.casting.is_empty(),"overlapping towers share thorn protection")
	sim.tick += 215
	check(Ranger._thorn_targets(sim,other,other.pos,sim.templates.aura_ranger_thorn.aura).is_empty(),"shared protection lasts until 7.2 seconds")
	sim.tick += 1
	check(Ranger._thorn_targets(sim,other,other.pos,sim.templates.aura_ranger_thorn.aura).size() == 2,"shared protection expires at 7.2 seconds")
	other.ranger.thorn_ts = sim.tick - 270; Ranger._thorn(sim,other,other.pos)
	check(not other.ranger.casting.is_empty(),"second tower starts valid windup")
	sim.command("sell",{"id":"05"}); advance(sim,18)
	check(sim.modifiers.count(e2.id,"mod_thorn") == 0,"sale cancels unlaunched thorn")

func pending_arrow_lifetime() -> void:
	var sim = fresh(); var tower: Dictionary = sim.tower_by_id("03")
	var dead := target(sim); var replacement := target(sim,"enemy_ogre",Vector2(20,90))
	sim.command("upgrade_power",{"id":"03","power":"poison"})
	tower.attack_at = sim.tick; Ranger.step(sim,tower)
	var first: Dictionary = sim.unit_by_id(tower.pending.target)
	first.hp = 0; sim.tick += 4; Ranger.step(sim,tower)
	check(sim.projectiles.size() == 1 and sim.projectiles[0].target != first.id,"dead windup target retargets nearby enemy")
	var bullet: Dictionary = sim.projectiles[0]
	var survivor: Dictionary = sim.unit_by_id(bullet.target)
	sim.command("sell",{"id":"03"})
	bullet.to = survivor.pos + sim.vec(sim.templates[survivor.template].unit.hit_offset)
	bullet.from = bullet.to; bullet.at = sim.tick - bullet.duration
	sim._bullet_step(bullet)
	check(sim.modifiers.has(survivor.id,"mod_ranger_poison"),"launched poison arrow survives tower sale")
	check(dead.id != replacement.id,"retarget fixtures distinct")

func _run() -> void:
	transactions(); poison(); shooting(); thorn(); arena_controls(); movement_and_shared_status(); pending_arrow_lifetime()
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"poison_same_level_total_cap":4}
	var file := FileAccess.open("res://reports/ranger_logic.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("RANGER_LOGIC: ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)
