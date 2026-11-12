extends "res://scripts/battle/controllers/level10.gd"

func extra_fire_point(point:Vector2) -> bool:return Rect2(95,318,117,58).has_point(point)

func step(sim) -> void:
	if not sim.veznan.hud_hidden:super.step(sim)
	if int(sim.data.level.mode)!=1:return
	var boss:Dictionary=sim.unit_by_id(sim.veznan.boss_id)
	if boss.is_empty() or boss.veznan.phase!="castle":return
	if sim.wave<sim.data.waves.groups.size() or not sim.spawn_queue.is_empty() or not sim.pending_entities.is_empty():return
	if sim.enemies.any(func(e):return e.id!=boss.id and e.hp>0):return
	boss.veznan.signal=true
	sim.event.emit("music",{"id":"MusicBossFight"})

func can_finish(sim) -> bool:
	if int(sim.data.level.mode)==1:return sim.veznan.complete
	return super.can_finish(sim)

func victory_route(sim) -> String:
	return "kr1_end" if int(sim.data.level.mode)==1 else ""
