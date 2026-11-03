extends "res://tests/verify_upgrades.gd"
## Execute actual frozen patch functions on tenth-stage templates.
func run() -> void:
	var reference:=Levels.read_json("res://tests/fixtures/level10_upgrades_source.json")
	check(reference.get("reference_level",0)==10,"tenth source technology reference")
	var base:=Levels.load_definition(10)
	for row:Dictionary in reference.cases:
		var data:=Setup.create(base,{"upgrades":row.levels})
		data.layout.level_mode_overrides[0].max_upgrade_level=row.limit
		var sim=Sim.new(data,42)
		var actual:Dictionary={}
		for name:String in row.templates:actual[name]=project(sim.templates[name],row.templates[name])
		var difference:=first_difference(row.templates,actual,"templates")
		check(difference=="","source tenth patch "+row.name+": "+difference)
		comparisons[row.name]={"expected":row.templates,"actual":actual,"first_difference":difference};source_rows+=row.templates.size()
		for name:String in ["tower_tesla","ray_tesla","mod_ray_tesla"]:check(row.templates.has(name),"real tenth technology target "+name)
	var hashes:=preload("res://tests/upgrades_test_support.gd").hashes()
	for path:String in ["tests/verify_level10_upgrades.gd","tests/fixtures/level10_upgrades_source.json","tools/upgrade_reference/main.lua","data/level10/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level10_upgrades.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_patch_scenarios":reference.cases.size(),"source_template_rows":source_rows,"source_hashes":hashes})
	preload("res://tests/report_writer.gd").json_file("res://reports/level10_upgrade_comparisons.json",comparisons)
	print("LEVEL10_UPGRADES: ","PASS" if failures.is_empty() else JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
