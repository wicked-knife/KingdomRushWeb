extends "res://tests/verify_upgrades.gd"
## Execute actual frozen patch functions on ninth-stage templates.
func run() -> void:
	var reference:=Levels.read_json("res://tests/fixtures/level09_upgrades_source.json")
	check(reference.get("reference_level",0)==9,"ninth source technology reference")
	var base:=Levels.load_definition(9)
	for row:Dictionary in reference.cases:
		var data:=Setup.create(base,{"upgrades":row.levels})
		data.layout.level_mode_overrides[0].max_upgrade_level=row.limit
		var sim=Sim.new(data,42)
		var actual:Dictionary={}
		for name:String in row.templates:actual[name]=project(sim.templates[name],row.templates[name])
		var difference:=first_difference(row.templates,actual,"templates")
		check(difference=="","source ninth patch "+row.name+": "+difference)
		comparisons[row.name]={"expected":row.templates,"actual":actual,"first_difference":difference};source_rows+=row.templates.size()
		for name:String in ["tower_sorcerer","tower_sunray","soldier_elemental","bolt_sorcerer","ray_sunray"]:check(row.templates.has(name),"real ninth technology target "+name)
	var hashes:=preload("res://tests/upgrades_test_support.gd").hashes()
	for path:String in ["tests/verify_level09_upgrades.gd","tests/fixtures/level09_upgrades_source.json","tools/upgrade_reference/main.lua","data/level09/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level09_upgrades.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_patch_scenarios":reference.cases.size(),"source_template_rows":source_rows,"source_hashes":hashes})
	preload("res://tests/report_writer.gd").json_file("res://reports/level09_upgrade_comparisons.json",comparisons)
	print("LEVEL09_UPGRADES: ","PASS" if failures.is_empty() else JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
