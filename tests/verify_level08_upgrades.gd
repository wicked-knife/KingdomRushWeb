extends "res://tests/verify_upgrades.gd"
## Actual Dove patch functions on stage-eight templates, including power prices.

func run() -> void:
	var reference := Levels.read_json("res://tests/fixtures/level08_upgrades_source.json")
	check(reference.get("reference_level",0)==8 and reference.get("source",{})==Levels.catalog().source,"stage-eight technology reference uses frozen Dove")
	if reference.get("cases",[]).is_empty():quit(1);return
	var base := Levels.load_definition(8)
	var frozen := var_to_str(base)
	for row: Dictionary in reference.cases:
		var data := Setup.create(base,{"upgrades":row.levels})
		data.layout.level_mode_overrides[0].max_upgrade_level=row.limit
		var sim=Sim.new(data,42)
		var actual := {}
		for name: String in row.templates:actual[name]=project(sim.templates[name],row.templates[name])
		var difference := first_difference(row.templates,actual,"templates")
		check(difference=="","stage-eight actual source patch "+row.name+": "+difference)
		comparisons[row.name]={"expected":row.templates,"actual":actual,"first_difference":difference}
		source_rows+=row.templates.size()
		for name: String in ["soldier_barbarian","soldier_sasquash","tower_barbarian","tower_sasquash","tower_bfg","bomb_bfg","bomb_bfg_cluster","missile_bfg"]:
			check(row.templates.has(name) and not name in reference.unpublished_inert_targets,"source compares real published target "+row.name+"/"+name)
		check(sim.upgrades.effective.barracks==mini(int(row.levels.barracks),int(row.limit)) and sim.upgrades.effective.engineers==mini(int(row.levels.engineers),int(row.limit)),"source technology cap "+row.name)
		bfg_runtime(sim,row)
	check(var_to_str(base)==frozen,"stage-eight technology never mutates loaded definition")
	var hashes := {}
	for path: String in ["tests/verify_level08_upgrades.gd","tests/verify_upgrades.gd","tests/fixtures/level08_upgrades_source.json","tools/prepare_upgrades.py","tools/upgrade_reference/main.lua","scripts/battle/dove_upgrades.gd","scripts/battle/dove_bfg.gd","scripts/services/battle_setup.gd","data/upgrades/definition.json","data/level08/definition.json"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level08_upgrade_comparisons.json",comparisons)
	preload("res://tests/report_writer.gd").json_file("res://reports/level08_upgrades.json",{"passed":failures.is_empty(),"checks":checks,"source_patch_scenarios":reference.cases.size(),"source_template_rows":source_rows,"failures":failures,"source_hashes":hashes})
	print("LEVEL08_UPGRADES: ","PASS" if failures.is_empty() else JSON.stringify(failures)," checks=",checks," cases=",reference.cases.size()," rows=",source_rows)
	quit(0 if failures.is_empty() else 1)

func bfg_runtime(sim, row: Dictionary) -> void:
	sim.notices.clear();sim.gold=100000
	check(sim.command("build",{"id":"11","type":"engineer"}),"technology BFG build "+row.name)
	sim.tick+=30
	for target: String in ["tower_engineer_2","tower_engineer_3","tower_bfg"]:
		check(sim.command("upgrade",{"id":"11","upgrade_to":target}),"technology BFG upgrade "+row.name+"/"+target)
	var tower: Dictionary=sim.tower_by_id("11")
	var enemy: Dictionary=sim._spawn_enemy("enemy_goblin",0)
	enemy.node=40;enemy.pos=tower.pos+Vector2(40,0)
	for rank in range(1,4):
		for power: String in ["missile","cluster"]:
			check(sim.command("upgrade_power",{"id":"11","power":power}),"technology power purchase "+row.name+"/"+power+str(rank))
		var expected: Dictionary=row.bfg_attacks[rank-1]
		var missile: Dictionary=Sim.Behaviors.Bfg.attack(sim,tower,1)
		var cluster: Dictionary=Sim.Behaviors.Bfg.attack(sim,tower,2)
		check(is_equal_approx(float(missile.range),float(expected.range)) and is_equal_approx(float(missile.cooldown),float(expected.missile_cooldown)) and is_equal_approx(float(cluster.cooldown),float(expected.cluster_cooldown)),"source BFG upgrade callbacks reach runtime "+row.name+"/"+str(rank))
		sim.tick+=1000;tower.bfg.job={};tower.bfg.cursor=1;tower.bfg.ts=[0,0,0]
		Sim.Behaviors.Bfg.step(sim,tower)
		check(not tower.bfg.job.is_empty() and tower.bfg.job.index==2 and is_equal_approx(float(tower.bfg.missile_cooldown),float(expected.mixed_cooldown)),"source BFG ground targeting uses mixed cooldown "+row.name+"/"+str(rank))
