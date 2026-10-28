extends SceneTree
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Factors = preload("res://scripts/battle/dove_damage_factors.gd")
var failures: Array = []
var checks := 0
var results := {}
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func close_enough(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i] is Array:
			if not close_enough(a[i],b[i]): return false
		elif a[i] is String:
			if a[i] != b[i]: return false
		elif absf(float(a[i])-float(b[i])) > 0.0001: return false
	return true
func run() -> void:
	var ref := Levels.read_json("res://tests/fixtures/dove_current_source.json")
	check(ref.source.commit == Levels.catalog().source.commit, "oracle uses current source")
	for received in [false,true]:
		var unit := {}; var template := {"unit":{"damage_factor":1.1},"health":{"damage_factor":1.1}}
		var actual := []
		for op: Array in ref.operations:
			Factors.change(unit,template,float(op[0]),received,bool(op[1])); actual.append(Factors.value(unit,template,received))
		check(close_enough(actual,ref.factors["received" if received else "unit"]), "source factor stack/removal %s" % received)
	var sim = Sim.new(Levels.load_definition(6),42)
	sim.notices.clear();sim.gold=10000
	var tower: Dictionary = sim.towers.filter(func(t):return t.type=="")[0]
	sim.command("build",{"id":tower.id,"type":"barrack"})
	var soldier: Dictionary = sim._soldier("soldier_militia",tower.id,0,tower.pos,tower.pos)
	var dead: Dictionary = sim._soldier("soldier_militia",tower.id,1,tower.pos,tower.pos)
	soldier.damage_factor=1.1;dead.hp=0;sim.soldiers=[soldier,dead]
	Factors.tower_buff(sim,tower,0.2);Factors.tower_buff(sim,tower,0.3)
	var replacement := {"template":"soldier_militia","damage_factor":1.1}
	Factors.inherit(sim,replacement,tower)
	check(close_enough([Factors.value(tower,sim.templates[tower.template]),soldier.damage_factor,dead.damage_factor,replacement.damage_factor],ref.tower),"tower propagation includes corpses and new garrison")
	Factors.tower_buff(sim,tower,-0.2)
	check(close_enough([tower.damage_factor,soldier.damage_factor,dead.damage_factor],ref.tower_removed),"tower incremental removal")
	for name: String in ref.bolts:
		bolt(name,ref.bolts[name])
	# Snapshot survives attacker removal; filters and mods-over-mod precedence use source flags.
	sim = Sim.new(Levels.load_definition(5),42);sim.notices.clear()
	var target: Dictionary = sim._spawn_enemy("enemy_fat_orc",0)
	var attacker: Dictionary = sim.towers[0]; attacker.template="tower_archer_1";attacker.damage_factor=1.5
	sim._projectile("arrow_1",target.id,target.pos,target.pos,0.01,attacker)
	var p: Dictionary = sim.projectiles[-1]
	sim.templates.arrow_1.bullet.mods=["mod_ranger_poison","mod_thorn"]
	sim.templates.arrow_1.bullet.mod="mod_elf_bleed"
	sim.templates.mod_thorn.modifier.vis_bans=int(sim.templates[target.template].vis.flags)
	sim.towers.clear();sim.tick=2;sim._bullet_step(p)
	check(sim.modifiers.active.size()==1 and sim.modifiers.active[0].template=="mod_ranger_poison", "modifier list precedence and visibility filter")
	if sim.modifiers.active.size()==1:
		var m: Dictionary=sim.modifiers.active[0]
		check(m.source==str(attacker.id) and m.damage_factor==1.5,"projectile preserves shooter and damage factor")
	check(not Levels.load_definition(5).templates.arrow_1.bullet.has("mods"),"runtime templates remain isolated")
	var before: float=target.hp
	Factors.change(target,sim.templates[target.template],0.8,true)
	check(is_equal_approx(sim.damage(target,10,1),8),"received factor applied to damage")
	check(is_equal_approx(before-target.hp,8),"received health result")
	var report := {"passed":failures.is_empty(),"source":ref.source,"checks":checks,"bolt_scenarios":results,"failures":failures}
	var file=FileAccess.open("res://reports/current_dove_combat.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CURRENT_DOVE: ","PASS" if failures.is_empty() else str(failures)," checks=",checks)
	quit(0 if failures.is_empty() else 1)
func bolt(name: String, expected: Dictionary) -> void:
	var sim=Sim.new(Levels.load_definition(1),42);sim.notices.clear()
	var target: Dictionary=sim._spawn_enemy("enemy_goblin",0)
	target.pos=Vector2(300,100);sim.templates[target.template].unit.hit_offset={"x":0,"y":10}
	var bullet: Dictionary=sim.templates.bolt_1.bullet
	bullet.min_speed=30;bullet.max_speed=300;bullet.acceleration_factor=0.1;bullet.max_track_distance=60
	var to := Vector2(100.5,100) if name=="near" else Vector2(300,110)
	sim._projectile("bolt_1",target.id,Vector2(100,100),to,1)
	var p: Dictionary=sim.projectiles[-1];var samples := [];var first := -1
	for tick in 81:
		sim.tick=tick
		if name=="moving" and tick>2: target.pos.x+=1
		if name=="teleport" and tick==5: target.pos.x+=200
		if name=="dead" and tick==5: target.hp=0
		if name=="ranged_ban" and tick==4: target.vis={"flags":sim.templates[target.template].vis.flags,"bans":128}
		var done: bool=sim._bolt_step(p,bullet,target)
		var row: Array=[tick,p.pos.x,p.pos.y,p.to.x,p.to.y];samples.append(row)
		if first==-1 and (tick>=expected.samples.size() or not close_enough(row,expected.samples[tick])): first=tick
		if done: break
	check(first==-1 and samples.size()==expected.samples.size(),"source bolt %s first differing frame=%d" % [name,first])
	var hits := 1 if target.hp>0 and not p.target_invalid and p.get("has_tracked",false) else 0
	check(hits==int(expected.hits),"source bolt hit eligibility %s" % name)
	results[name]={"expected":expected.samples,"actual":samples,"first_difference":first,"hits":hits}
