extends SceneTree
## Verify the mounted pack itself, rather than accidentally resolving files from the dev tree.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the exported PCK after --")
		quit(1)
		return
	# Spawn an isolated resource namespace so missing files cannot fall back to the workspace.
	if args.size() == 1:
		var folder := ProjectSettings.globalize_path("res://build/pack_check")
		DirAccess.make_dir_recursive_absolute(folder)
		var ignore := FileAccess.open(ProjectSettings.globalize_path("res://build/.gdignore"), FileAccess.WRITE)
		ignore.close()
		var project := FileAccess.open(folder + "/project.godot", FileAccess.WRITE)
		project.store_string("config_version=5\n")
		project.close()
		DirAccess.copy_absolute(get_script().resource_path, folder + "/verify.gd")
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", folder, "--script", folder + "/verify.gd", "--", args[0], "isolated"], output, true)
		for line: String in output:
			print(line)
		quit(result)
		return
	if not ProjectSettings.load_resource_pack(args[0]):
		push_error("Unable to mount " + args[0])
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu_manifest.json"))
	var expected: Array = [manifest.catalog, manifest.locale, manifest.sounds, manifest.font, manifest.background]
	expected.append("res://data/save/definition.json")
	expected.append_array(manifest.get("fonts", [manifest.font]))
	expected.append(manifest.font_roles)
	expected.append_array(manifest.scenes)
	expected.append_array(manifest.scripts)
	expected.append_array(manifest.textures)
	expected.append_array(manifest.audio.values())
	expected.append_array(manifest.atlases.values())
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_content.json"))
	expected.append("res://data/campaign_content.json")
	expected.append_array(content.runtime_scripts)
	expected.append_array(content.controllers.values())
	for entry: Dictionary in content.levels.values():
		var base := "res://data/%s/" % entry.folder
		var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
		expected.append_array(level.resources)
		expected.append_array(level.data)
		expected.append(base + "manifest.json")
	var campaign_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_kr1/manifest.json"))
	expected.append_array(campaign_map.resources)
	expected.append_array(campaign_map.data)
	expected.append("res://data/map_kr1/manifest.json")
	var heroes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes/manifest.json"))
	expected.append_array(heroes.resources)
	expected.append_array(heroes.data)
	expected.append("res://data/heroes/manifest.json")
	var allowed_data := expected.duplicate()
	allowed_data.append("res://data/menu_manifest.json")
	var failures: Array[String] = []
	for path: String in expected:
		if path.ends_with(".json"):
			if not FileAccess.file_exists(path):
				failures.append("Missing JSON: " + path)
		elif not ResourceLoader.exists(path):
			failures.append("Missing resource: " + path)
	if load("res://scenes/app_root.tscn") == null:
		failures.append("Exported main scene or script dependencies failed to load")
	var progress_script = load("res://scripts/services/campaign_progress.gd")
	var smoke_path := args[0].get_base_dir() + "/slot_smoke.json"
	var session = progress_script.new(); session.initialize(smoke_path)
	if not progress_script.valid(progress_script.read_json("res://data/save/definition.json").template) or session.max_stars != 645:
		failures.append("Unified slot template or source star total missing")
	session.data.last_victory = {"level_idx": 1, "level_mode": 1, "level_difficulty": 2, "stars": 3, "unlock_towers": ["tower_ranger"]}
	var settlement: Dictionary = session.enter_map()
	if session.record(1).get(1, 0) != 2 or settlement.unlocked != [2] or session.data.has("last_victory") or "tower_ranger" in session.data.locked_towers:
		failures.append("Exported unified slot settlement failed")
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(smoke_path + suffix): DirAccess.remove_absolute(smoke_path + suffix)
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/definition.json"))
	var hero_definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes/definition.json"))
	if hero_definition.get("heroes", []).size() != 79: failures.append("Hero roster incomplete")
	if definition.waves.groups.size() != 7 or definition.waves.cash != 270:
		failures.append("First campaign data invalid")
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level01/atlas.json"))
	for frame: Dictionary in atlas.frames.values():
		if not ResourceLoader.exists(atlas.texture_directory + frame.sheet):
			failures.append("Missing first-level atlas " + frame.sheet)
	var sim_script = load("res://scripts/battle/level01_sim.gd")
	for script: String in ["res://scripts/map/dove_map_flag.gd", "res://scripts/battle/battle_wave_flags.gd"]:
		if not ResourceLoader.exists(script) or load(script) == null: failures.append("Interaction script missing: " + script)
	for id: int in content.levels.keys().map(func(key): return int(key)):
		var stage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level%02d/definition.json" % id))
		if stage.get("locations", {}).get("entrances", []).size() != {1:1, 2:1, 3:2, 4:2, 5:3, 6:5}[id]: failures.append("Exported entrances incomplete %d" % id)
		var art = load("res://scripts/dove_asset_catalog.gd").new(stage.level.root + "catalog.json")
		for image: String in ["nextwaveTimer_Full", "nextwaveTimer_0001", "nextwaveTimer_0002", "nextwaveTimer_0020", "nextwaveTimer_glow_0001"]:
			if art.get_frame(stage.level.group, image).is_empty(): failures.append("Exported wave flag art missing: " + image)
		for image: String in ["nextwave_coin_0001", "nextwave_coin_0014", "waveReward_0011", "waveRewardTimer_0011", "waveRewardTimer_0012"]:
			if art.get_frame(stage.level.group, image).is_empty(): failures.append("Exported wave reward art missing: " + image)
		for frame in range(1,15):
			if art.get_frame(stage.level.group, "error_feedback_%04d" % frame).is_empty(): failures.append("Exported invalid-point feedback missing %d/%d" % [id,frame])
		var placement = sim_script.new(stage)
		var grass: Vector2 = {1:Vector2(256,424), 2:Vector2(256,328), 3:Vector2(256,376), 4:Vector2(100,100), 5:Vector2(100,100), 6:Vector2(100,100)}[id]
		if placement.valid_power_point("reinforcements", grass) or not placement.valid_power_point("reinforcements", placement.towers[0].rally): failures.append("Exported troop placement rules invalid %d" % id)
		if id == 2:
			placement.notices.clear(); placement.command("build", {"id":"5", "type":"barrack"})
			var barrack: Dictionary = placement.tower_by_id("5"); placement.tick = barrack.ready
			if not placement.command("rally", {"id":"5", "pos":Vector2(129,150)}) or barrack.rally.distance_to(Vector2(424.8,150)) > 0.002: failures.append("Exported directional rally fallback invalid")
		if art.get_sound("GUICoins").is_empty(): failures.append("Exported wave reward sound missing %d" % id)
		if art.get_sound("GUIQuestCompleted").is_empty(): failures.append("Exported victory fanfare missing %d" % id)
		if art.get_sound("GUISpellRefresh").is_empty(): failures.append("Exported skill refresh sound missing %d" % id)
	var map_definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_kr1/definition.json"))
	if map_definition.levels.size() != 27 or map_definition.animations.size() != 124:
		failures.append("Generation-one map data incomplete")
	var map_catalog = load("res://scripts/dove_asset_catalog.gd").new("res://data/map_kr1/catalog.json")
	var map_atlas: Dictionary = map_catalog.load_group("map_kr1")
	for frame: Dictionary in map_atlas.frames.values():
		if not ResourceLoader.exists(map_atlas.texture_directory + frame.sheet): failures.append("Missing map atlas " + frame.sheet)
	if map_catalog.get_frame("map_kr1", "map_background_kr1").is_empty(): failures.append("Map background unavailable")
	var hero_catalog = load("res://scripts/dove_asset_catalog.gd").new("res://data/heroes/catalog.json")
	var hero_atlas: Dictionary = hero_catalog.load_group("heroes")
	for frame: Dictionary in hero_atlas.get("frames", {}).values():
		if not ResourceLoader.exists(hero_atlas.texture_directory + frame.sheet): failures.append("Missing hero atlas " + frame.sheet)
	if hero_catalog.get_frame("heroes", "portrait_notxt_0001").is_empty(): failures.append("Hero portrait unavailable")
	for hero: Dictionary in hero_definition.get("heroes", []):
		if not hero_atlas.lookup.has(hero.thumbnail) or not hero_atlas.lookup.has(hero.portrait) or not map_atlas.lookup.has(hero.map_icon): failures.append("Hero artwork unavailable " + hero.name)
	if sim_script == null: failures.append("First-level simulation cannot be loaded")
	else:
		var simulation = sim_script.new(definition)
		if simulation.towers.size() != 8: failures.append("Exported simulation initialization failed")
		var levels = load("res://scripts/services/campaign_levels.gd")
		for id in levels.ids():
			for mode in [1,2,3]:
				var active: Dictionary=levels.load_definition(id,mode,2)
				if active.is_empty():failures.append("Exported mode dependencies invalid %d/%d" % [id,mode]);continue
				var challenge=sim_script.new(active,42)
				if challenge.data.level.id!=id or challenge.data.level.mode!=mode:failures.append("Exported mode identity invalid %d/%d" % [id,mode])
				var art=load("res://scripts/dove_asset_catalog.gd").new(active.level.root+"catalog.json")
				if art.get_frame(active.level.group,"victoryBadges_notxt_%04d" % {1:2,2:3,3:1}[mode]).is_empty():failures.append("Exported mode victory badge missing %d/%d" % [id,mode])
				if mode==1:continue
				if challenge.lives!=1 or challenge.gold!={2:[230,310,400,750,1000,1200],3:[360,275,660,1500,1500,800]}[mode][id-1] or active.waves.groups.size()!=(6 if mode==2 else 1):failures.append("Exported challenge initial state invalid %d/%d" % [id,mode])
				while not challenge.notices.is_empty():challenge.command("confirm")
				for kind: String in sim_script.TYPES:
					if not challenge.tower_locked("tower_build_"+kind):continue
					var empty: Dictionary=challenge.towers.filter(func(t):return t.type=="")[0]
					var gold: int=challenge.gold
					if challenge.command("build",{"id":empty.id,"type":kind}) or challenge.gold!=gold:failures.append("Exported forbidden build accepted %d/%d" % [id,mode])
				if id==6 and mode==3:
					if challenge.towers.filter(func(t):return t.template=="tower_mage_3" and t.spent==0).size()!=2: failures.append("Pack sixth iron free mages invalid")
					if not challenge.command("upgrade",{"id":"8","upgrade_to":"tower_arcane_wizard"}): failures.append("Pack sixth advanced tower transaction failed")
				if id==5 and mode==3:
					if challenge.towers.filter(func(t):return t.template=="tower_archer_3" and t.spent==0).size()!=3:failures.append("Pack fifth iron free archers invalid")
					for site in ["5","7"]:
						if not challenge.command("upgrade",{"id":site,"upgrade_to":"tower_elf"}) or not challenge.command("buy_soldier",{"id":site,"type":"soldier_elf"}):failures.append("Pack fifth iron camp transaction failed "+site)
		for id in [2, 3, 4, 5, 6]:
			var stage: Dictionary = levels.load_definition(id)
			if stage.is_empty(): failures.append("Exported campaign dependencies invalid %d" % id); continue
			var campaign = sim_script.new(stage)
			if campaign.towers.size() != {2: 7, 3: 12, 4: 15, 5:14, 6:15}[id] or campaign.data.waves.groups.size() != {2: 7, 3: 11, 4: 13, 5:15, 6:17}[id]: failures.append("Exported campaign initialization invalid %d" % id)
			if id == 5:
				campaign.notices.clear()
				if campaign.gold != 700 or not campaign.command("upgrade",{"id":"5","upgrade_to":"tower_elf"}) or not campaign.command("buy_soldier",{"id":"5","type":"soldier_elf"}) or not campaign.command("upgrade",{"id":"4","upgrade_to":"tower_ranger"}): failures.append("Pack fifth camp/ranger transactions failed")
				for tick in range(90): campaign.step()
				if campaign.soldiers.size() != 1 or campaign.gold != 180: failures.append("Pack fifth recruitment failed")
				var mother: Dictionary = campaign._spawn_enemy("enemy_spider_big",0,0)
				mother.egg_at = campaign.tick-1; campaign.Spider.lay(campaign,mother)
				if campaign.eggs.size() != 1: failures.append("Pack fifth egg dependency failed")
			if id == 4:
				campaign.notices.clear(); campaign.gold = 2500
				for kind: String in sim_script.TYPES:
					var site: String = {"archer":"01", "barrack":"02", "mage":"03", "engineer":"04"}[kind]
					if not campaign.command("build", {"id":site, "type":kind}): failures.append("Pack build failed " + kind)
					for tick in range(25): campaign.step()
					for tier in [2, 3]:
						if not campaign.command("upgrade", {"id":site, "upgrade_to":"tower_%s_%d" % [kind,tier]}): failures.append("Pack upgrade failed " + kind)
			var art = load("res://scripts/dove_asset_catalog.gd").new(stage.level.root + "catalog.json")
			if art.get_frame(stage.level.group, stage.level.background).is_empty(): failures.append("Exported campaign background missing %d" % id)
	var background := load(manifest.background) as Texture2D
	if background == null or background.get_size() != Vector2(1920, 1080):
		failures.append("Exported menu background or its atlas dependency failed to load")
	var files: Array[String] = []
	_collect("res://", files)
	files.erase("res://verify.gd")
	files.erase("res://project.godot")
	for path: String in files:
		if path.begins_with("res://assets/") and not path.trim_suffix(".import") in allowed_data:
			failures.append("Unexpected asset: " + path)
		for excluded: String in ["source_assets", "reports", "tests", "tools", "docs"]:
			if path.begins_with("res://" + excluded + "/"):
				failures.append("Excluded directory found: " + path)
	var report := {"passed": failures.is_empty(), "failures": failures, "mode_combinations_checked":content.levels.size() * 3, "files": files}
	var report_path := args[0].get_base_dir().path_join("pack_files.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("WEB_PACK_VERIFICATION: ", "PASS" if failures.is_empty() else JSON.stringify(failures), " (", files.size(), " files)")
	quit(0 if failures.is_empty() else 1)


func _collect(path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(path)
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if directory.current_is_dir():
				_collect(child, output)
			else:
				output.append(child)
		entry = directory.get_next()
	directory.list_dir_end()
