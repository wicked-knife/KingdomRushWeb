extends "res://tests/verify_upgrades.gd"
## Execute actual frozen patch functions on eleventh-stage templates.
func run() -> void:
	var reference:=Levels.read_json("res://tests/fixtures/level11_upgrades_source.json")
	check(reference.get("reference_level",0)==11,"eleventh source technology reference")
	var base:=Levels.load_definition(11)
	for mode:int in [1,2,3]:
		var active=Sim.new(Setup.create(Levels.load_definition(11,mode),{"heroes":{"selected":["hero_malik"]},"upgrades":{"archers":6,"barracks":6,"mages":6,"engineers":6,"rain":6,"reinforcements":6}}),42)
		check(active.soldiers.any(func(s):return s.template=="hero_malik"),"Malik active in mode %d"%mode)
		for branch:String in active.upgrades.effective:check(active.upgrades.effective[branch]==6,"effective technology six %d/%s"%[mode,branch])
	for row:Dictionary in reference.cases:
		var data:=Setup.create(base,{"upgrades":row.levels})
		data.layout.level_mode_overrides[0].max_upgrade_level=row.limit
		var sim=Sim.new(data,42)
		var actual:Dictionary={}
		for name:String in row.templates:actual[name]=project(sim.templates[name],row.templates[name])
		var difference:=first_difference(row.templates,actual,"templates")
		check(difference=="","source eleventh patch "+row.name+": "+difference)
		comparisons[row.name]={"expected":row.templates,"actual":actual,"first_difference":difference};source_rows+=row.templates.size()
		for name:String in ["tower_tesla","ray_tesla","mod_ray_tesla"]:check(row.templates.has(name),"real eleventh technology target "+name)
	var hashes:=preload("res://tests/upgrades_test_support.gd").hashes()
	for path:String in ["tests/verify_level11_upgrades.gd","tests/fixtures/level11_upgrades_source.json","tools/upgrade_reference/main.lua","data/level11/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level11_upgrades.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_patch_scenarios":reference.cases.size(),"source_template_rows":source_rows,"source_hashes":hashes})
	preload("res://tests/report_writer.gd").json_file("res://reports/level11_upgrade_comparisons.json",comparisons)
	print("LEVEL11_UPGRADES: ","PASS" if failures.is_empty() else JSON.stringify(failures));quit(0 if failures.is_empty() else 1)
