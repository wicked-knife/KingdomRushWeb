extends "res://tests/verify_level08.gd"
func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level08_source.json")
	for scenario:String in source.enemy_ranged:enemy_ranged_sample(scenario)
	var hashes:Dictionary={}
	for path:String in ["tests/verify_level11_ranged_shared.gd","tests/verify_level08.gd","tests/fixtures/level08_source.json","scripts/battle/dove_enemy_ranged.gd","scripts/battle/dove_enemy_melee.gd","scripts/battle/level01_sim.gd","data/level08/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("level11_ranged_shared",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_hashes":hashes,"scope":"six source axe-thrower ranged timing and interruption regressions"})
	print("LEVEL11_RANGED_SHARED: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
