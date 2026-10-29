extends "res://scripts/battle/dove_level_controller.gd"

func reset(sim) -> void:
	sim.notices = []
	_append_notifications(sim, sim.data.waves.groups[0])

func wave_notification(sim, entry: Dictionary) -> void:
	if sim.wave > 1 and entry.has("notification") and sim.data.ui.notifications.has(entry.notification): sim.notices.append(entry.notification)

func _append_notifications(sim, group: Dictionary) -> void:
	for entry: Dictionary in group.waves:
		if entry.has("notification") and sim.data.ui.notifications.has(entry.notification): sim.notices.append(entry.notification)

func can_finish(sim) -> bool:
	# Unhatched eggs never block victory. Hatching has already run this tick.
	return sim.wave == sim.data.waves.groups.size() and sim.spawn_queue.is_empty() and sim.enemies.all(func(e): return e.hp <= 0) and sim.pending_entities.is_empty() and not sim.snow.occupied()
