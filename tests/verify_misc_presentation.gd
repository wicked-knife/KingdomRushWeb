extends SceneTree
const Levels = preload("res://scripts/services/campaign_levels.gd")
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Info = preload("res://scripts/battle/dove_unit_info.gd")
var failures: Array[String] = []
var checks := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func run() -> void:
	check(Info.armor_text(0)=="无", "zero armor matches Dove None")
	check(Info.armor_text(0.5)=="50", "armor is integer points without percent suffix")
	check(Info.armor_text(0.5,true)=="免疫", "immunity overrides armor points")
	for length: int in [20, 100]:
		var sim = Sim.new(Levels.load_definition(9,1),42)
		sim.notices.clear(); sim.enemies.clear(); sim.soldiers.clear()
		sim.spawn_queue.clear(); sim.pending_entities.clear(); sim.spawners.clear()
		sim.wave = sim.data.waves.groups.size()
		var enemy: Dictionary = sim._spawn_enemy("enemy_marauder",0)
		var key: String = sim.SpriteAnimation.key(sim.templates[enemy.template].render.sprites[0],"death")
		sim.animations = sim.animations.duplicate(true)
		sim.animations[key].frames.resize(length)
		sim.damage(enemy,enemy.hp,1)
		var death_tick: int = sim.tick
		var deadline: int = maxi(death_tick+61,death_tick+length)
		while sim.tick < deadline-1:
			sim.step()
			check(sim.result=="", "victory waits through final death tick %d/%d" % [sim.tick,length])
		sim.step()
		check(sim.result=="victory" and sim.tick>=death_tick+length,"victory follows source delay and completed death %d" % length)
		sim.reset()
		check(sim.victory_ready_at==-1 and sim.victory_animation_end==-1,"restart clears pending settlement")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"armor source formatting; final enemy death and two-second settlement delay"}
	preload("res://tests/report_writer.gd").json_file("res://reports/misc_presentation_logic.json",report)
	print("MISC_PRESENTATION: ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
