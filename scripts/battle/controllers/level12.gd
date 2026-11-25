extends "res://scripts/battle/controllers/level10.gd"
## Stage 12: The Dark Tower — graveyard controller + campaign Veznan boss lifecycle.

var boss_id := 0

func reset(sim) -> void:
	super.reset(sim)
	boss_id = 0
	if int(sim.data.level.get("mode", 1)) == 1 and sim.templates.has("eb_veznan"):
		var boss: Dictionary = sim.veznan.spawn_in_castle(sim)
		boss_id = int(boss.id)

func extra_fire_point(point: Vector2) -> bool:
	return Rect2(95, 318, 117, 58).has_point(point)

func extra_power_point(point: Vector2) -> bool:
	return Rect2(95, 318, 117, 58).has_point(point)

func _boss(sim) -> Dictionary:
	return sim.unit_by_id(boss_id) if boss_id != 0 else {}

func _has_other_alive_enemies(sim) -> bool:
	for e: Dictionary in sim.enemies:
		if e.id != boss_id and e.hp > 0:
			return true
	return false

func step(sim) -> void:
	super.step(sim)
	if boss_id == 0: return
	var boss := _boss(sim)
	if boss.is_empty() or not boss.has("veznan"): return
	var v: Dictionary = boss.veznan
	if v.phase == "castle" and v.phase_signal == "":
		var waves_done: bool = sim.wave == sim.data.waves.groups.size() and sim.spawn_queue.is_empty()
		var portals_busy: bool = sim.veznan.portals.any(func(p): return p.phase != "idle" or p.spawn_signal)
		if waves_done and not portals_busy and sim.pending_entities.is_empty() and not _has_other_alive_enemies(sim):
			sim.event.emit("music", {"id": "MusicBossFight"})
			v.phase_signal = "descend"

func enemy_died(sim, enemy: Dictionary) -> void:
	if enemy.has("veznan"):
		sim.custom_game_outcome = {"next_item_name": "kr1_end"}

func can_finish(sim) -> bool:
	if boss_id != 0:
		var boss := _boss(sim)
		if boss.is_empty(): return true
		return bool(boss.boss.get("death_handled", false))
	return super.can_finish(sim)
