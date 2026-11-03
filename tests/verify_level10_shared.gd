extends "res://tests/verify_level09.gd"
## Representative regressions for shared particle, modifier and death integrations.
func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level09_source.json")
	for scenario:String in ["sorcerer_normal","sunray_normal"]:tower9(scenario)
	freeze9();death9();polymorph9();elemental9()
	var hashes:Dictionary={}
	for path:String in ["tests/verify_level10_shared.gd","tests/verify_level09.gd","tests/fixtures/level09_source.json","data/level09/definition.json","scripts/battle/dove_modifiers.gd","scripts/battle/level01_sim.gd","scripts/battle/dove_snow.gd","scripts/battle/dove_behaviors.gd","scripts/battle/dove_jt.gd","scripts/battle/dove_sorcerer.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("level10_shared_logic",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_hashes":hashes,"scope":"source Sorcerer/Sunray attacks; freeze/thaw, JT death, polymorph and elemental lifecycle; no campaign replay"})
	print("LEVEL10_SHARED: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
