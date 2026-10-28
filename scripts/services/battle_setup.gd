extends RefCounted
## Immutable slot snapshot at the map/battle boundary. No live save references.
const Upgrades = preload("res://scripts/battle/dove_upgrades.gd")
static var last_error := ""

static func create(definition: Dictionary, slot_snapshot: Dictionary) -> Dictionary:
	last_error = Upgrades.slot_error(slot_snapshot)
	if not last_error.is_empty(): return {}
	var result := definition.duplicate(true)
	result.seen = slot_snapshot.get("seen", {}).duplicate(true)
	result.slot_locked_towers = slot_snapshot.get("locked_towers", []).duplicate(true)
	result.battle_upgrades = {"list_id": "1", "levels": Upgrades.levels(slot_snapshot.get("upgrades", {}))}
	return result
