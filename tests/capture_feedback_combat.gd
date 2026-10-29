extends SceneTree
## Capture the same bounded zero-technology samples in the published PCK and workspace.
var Levels
var Sim
func _init():call_deferred("run")
func dismiss(sim):
	while not sim.notices.is_empty():sim.command("confirm")
func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()>1 and not ProjectSettings.load_resource_pack(args[1]):quit(1);return
	Levels=load("res://scripts/services/campaign_levels.gd");Sim=load("res://scripts/battle/level01_sim.gd")
	var samples:={}
	for id in [1,3,5]:
		var sim=Sim.new(Levels.load_definition(id),42);dismiss(sim);sim.gold=10000
		var empty: Array=sim.towers.filter(func(t):return t.type=="")
		for index in Sim.TYPES.size():assert(sim.command("build",{"id":empty[index].id,"type":Sim.TYPES[index]}))
		for tick in 25:sim.step()
		if id==5:
			assert(sim.command("upgrade",{"id":"4","upgrade_to":"tower_ranger"}))
			assert(sim.command("upgrade_power",{"id":"4","power":"poison"}))
			assert(sim.command("upgrade",{"id":"5","upgrade_to":"tower_elf"}))
			assert(sim.command("buy_soldier",{"id":"5","type":"soldier_elf"}))
			assert(sim.command("upgrade_power",{"id":"5","power":"bleed"}))
			var mother: Dictionary=sim._spawn_enemy("enemy_spider_big",0,0);mother.egg_at=sim.tick-1
		assert(sim.command("wave"))
		var rows:=[]
		for index in 1200:
			dismiss(sim);sim.step()
			if index%100==99:
				var state: Array=[sim.tick,sim.gold,sim.lives,sim.kills,sim.leaks,sim.rng.state,sim.towers,sim.enemies,sim.soldiers,sim.projectiles,sim.modifiers.active,sim.eggs,sim.spawn_log]
				rows.append({"hash":var_to_str(state).sha256_text(),"state":state.duplicate(true)})
		samples[str(id)]=rows
	var file=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(samples));file.close()
	print("FEEDBACK_COMBAT_CAPTURE: 3 scenarios / 3600 ticks");quit()
