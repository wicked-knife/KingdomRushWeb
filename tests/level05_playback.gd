extends RefCounted
## Public-command replay, shared by headless verification and the native window.
static var actions := {}
static var outcome := {}
static var failures: Array[String] = []
static func commands(sim, driver: Callable = Callable()) -> void:
	if actions.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/level05_victory.json"))
		outcome = data.outcome
		for action: Dictionary in data.actions:
			var at := int(action.tick)
			if not actions.has(at): actions[at] = []
			actions[at].append(action)
	for action: Dictionary in actions.get(sim.tick,[]):
		var args: Dictionary = action.args.duplicate(true)
		if args.has("pos"): args.pos = Vector2(args.pos.x,args.pos.y)
		if driver.is_valid(): driver.call(action.kind,args)
		elif not sim.command(action.kind,args): failures.append("Rejected %s at %d" % [action.kind,sim.tick])
