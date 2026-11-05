extends "res://tests/verify_level10.gd"
func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level10_source.json")
	graveyard10();demons10();tesla10()
	for name:String in source.towers:source_tesla10(name)
	for rank:String in source.rays:source_ray10(int(rank))
	source_dps10()
	var hashes:Dictionary={}
	for path:String in ["tests/verify_level11_shared.gd","tests/verify_level10.gd","tests/fixtures/level10_source.json","scripts/battle/dove_behaviors.gd","scripts/battle/level01_sim.gd","scripts/battle/dove_enemy_ranged.gd","scripts/battle/dove_enemy_projectiles.gd","data/level10/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("level11_shared_logic",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_hashes":hashes,"scope":"representative stage-ten graveyard, demons, skeletons and Tesla source regressions"})
	print("LEVEL11_SHARED: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
