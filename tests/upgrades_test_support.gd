extends RefCounted
## Acceptance receipts become stale whenever the exercised implementation changes.
static func hashes() -> Dictionary:
	var paths := ["data/upgrades/definition.json","scripts/app_root.gd","scripts/services/battle_setup.gd","scripts/services/campaign_progress.gd","scripts/services/campaign_levels.gd","scripts/battle/dove_upgrades.gd","scripts/battle/dove_modifiers.gd","scripts/battle/dove_arcane.gd","scripts/battle/dove_behaviors.gd","scripts/battle/level01_sim.gd","scripts/battle/battle_view.gd","scripts/map/upgrades_room.gd","scripts/map/map_screen.gd","scripts/map/map_interface.gd"]
	var result := {}
	for path: String in paths: result[path]=FileAccess.get_sha256("res://"+path)
	return result
