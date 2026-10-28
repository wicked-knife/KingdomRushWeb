extends "res://scripts/battle/controllers/default_level.gd"

func reset(sim) -> void:
	if int(sim.data.level.mode) == 1: sim.notices = ["TUTORIAL_1", "TUTORIAL_2", "TUTORIAL_3"]
	else: super.reset(sim)

func wave_notification(sim, entry: Dictionary) -> void:
	if entry.has("notification") and sim.data.ui.notifications.has(entry.notification): sim.notices.append(entry.notification)
