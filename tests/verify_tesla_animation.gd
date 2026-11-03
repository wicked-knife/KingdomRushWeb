extends "res://tests/verify_level10.gd"
func run() -> void:
	source=Levels.read_json("res://tests/fixtures/level10_source.json")
	for scenario:String in source.ray_visuals:
		var sim=fresh();sim.enemies.clear();sim.soldiers.clear()
		for i in 3:
			var e:Dictionary=sim._spawn_enemy("enemy_dark_knight",0);e.pos=Vector2(530+i*40,350+i*20)
		sim.tick=-1
		sim.Behaviors.Tesla.launch(sim,sim.tower_by_id("1"),sim.enemies[0],Vector2(500,400),0)
		check(sim.projectiles[0].hidden,"new source ray remains hidden while queued "+scenario)
		var jobs:Array=[sim.projectiles[0]];var actual:Array=[]
		for n in 23:
			sim.tick=n
			for i in 3:
				var e:Dictionary=sim.enemies[i]
				if scenario=="moving":e.pos=Vector2(530+i*40+n*2,350+i*20+n)
				if scenario=="teleport_source" and i==0 and n>=5:e.pos.x=1000
				if scenario=="teleport_target" and i==1 and n>=5:e.pos.y=700
			for p:Dictionary in sim.projectiles.duplicate():sim._bullet_step(p)
			for p:Dictionary in sim.projectiles:
				if p not in jobs:jobs.append(p)
			sim.projectiles=sim.projectiles.filter(func(p):return not p.done)
			for j in jobs.size():
				var p:Dictionary=jobs[j]
				if p.get("tesla_started",false) and not p.done:actual.append([n,j+1,p.pos.x,p.pos.y,p.to.x,p.to.y,p.rotation,p.sprite_scale.x,p.sprite_scale.y,p.hidden,n-p.at])
		compare8("source ray visuals "+scenario,source.ray_visuals[scenario],actual,0.00001)
	var hashes:Dictionary={}
	for path:String in ["tests/verify_tesla_animation.gd","scripts/battle/dove_tesla.gd","scripts/battle/battle_view.gd","tests/fixtures/level10_source.json","tools/level10_reference/behavior.lua"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	write8("tesla_animation_logic",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"scenarios":source.ray_visuals.size(),"comparisons":comparisons,"source_hashes":hashes})
	print("TESLA_ANIMATION: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
