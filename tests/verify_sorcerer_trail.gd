extends SceneTree
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
var failures: Array[String] = []
var checks := 0
func _init() -> void:call_deferred("run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func run() -> void:
	var sim=Sim.new(Levels.load_definition(9,1),42)
	sim.snow.particles.clear()
	var p:Dictionary={"from":Vector2.ZERO,"pos":Vector2.ZERO,"at":0,"rotation":0.7}
	for tick in range(1,16):
		sim.tick=tick;p.pos=Vector2(tick*10,0)
		sim.snow.emit_trail(sim,p,"ps_bolt_sorcerer")
	check(sim.snow.particles.size()==30,"60 Hz trail emits two particles per 30 Hz tick")
	check(sim.snow.particles.all(func(row):return is_equal_approx(float(row.duration),12.5)),"source runner uses mean lifetime")
	check(sim.snow.particles.all(func(row):return row.scale>=0.6 and row.scale<=0.8),"source reversed scale range")
	check(sim.snow.particles.all(func(row):return is_equal_approx(float(row.rotation),0.7)),"unused rotation_spread does not randomize source rotation")
	check(sim.snow.particles[0].pos.x<4 and sim.snow.particles[1].pos.x>1 and sim.snow.particles[1].pos.x<9,"tracked emission interpolates positions")
	check(is_equal_approx(sim.snow._phase([1,0.3],0.5),0.65),"source particle scale interpolates")
	var before:int=sim.snow.particles.size()
	sim.snow.emit_trail(sim,p,"ps_bolt_sorcerer")
	check(sim.snow.particles.size()==before,"repeated frame does not emit again")
	sim.snow.emitters.clear();sim.snow.tunnels.clear();sim.enemies.clear()
	sim.tick=40;sim.snow.step(sim)
	check(sim.snow.particles.is_empty(),"particles finish naturally after emitter stops")
	var target:Dictionary=sim._spawn_enemy("enemy_marauder",0)
	target.pos=Vector2(500,300)
	sim._projectile("bolt_sorcerer",target.id,Vector2(100,300),target.pos,1)
	var bolt:Dictionary=sim.projectiles[-1]
	for i in 4:sim.tick+=1;sim._bullet_step(bolt)
	check(not sim.snow.particles.is_empty(),"live generic bolt emits sorcerer trail")
	bolt.pos=bolt.to;sim._bullet_step(bolt)
	check(bolt.done,"bolt impact stops flight")
	var hashes:Dictionary={}
	for path:String in ["tests/verify_sorcerer_trail.gd","scripts/battle/dove_snow.gd","scripts/battle/level01_sim.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/sorcerer_trail_logic.json",{"checks":checks,"failures":failures,"passed":failures.is_empty(),"source_hashes":hashes})
	print("SORCERER_TRAIL: ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
