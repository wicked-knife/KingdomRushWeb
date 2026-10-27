extends RefCounted
## Test setup explicitly includes the map visit required by Dove settlement.
static func complete(progress: RefCounted, outcome: Dictionary) -> bool:
	var before: Dictionary = progress.data.duplicate(true)
	progress.record_result(outcome)
	progress.enter_map()
	return progress.data != before
