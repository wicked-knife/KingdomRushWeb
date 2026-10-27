extends RefCounted
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")

static func path_for(id: int, mode: int) -> String:
	return "res://tests/replays/level%02d_%s.json" % [id, "heroic" if mode == 2 else "iron"]

static func replay(id: int, mode: int, driver: Callable = Callable()) -> Dictionary:
	if not FileAccess.file_exists(path_for(id, mode)): return {"sim": Sim.new(Levels.load_definition(id, mode),42), "rejected": ["missing recording"], "consumed": false}
	var recording: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path_for(id, mode)))
	var sim = Sim.new(Levels.load_definition(id, mode), int(recording.seed))
	var actions: Array = recording.actions
	var cursor := 0
	var rejected: Array = []
	for tick in range(65000):
		while cursor < actions.size() and int(actions[cursor].tick) == sim.tick:
			var action: Dictionary = actions[cursor]
			var args: Dictionary = action.args.duplicate(true)
			if args.has("pos"): args.pos = Sim.vec(args.pos)
			if driver.is_valid(): driver.call(action.kind, args)
			elif not sim.command(action.kind, args): rejected.append(action)
			cursor += 1
		sim.step()
		if sim.result != "": break
	return {"sim": sim, "rejected": rejected, "consumed": cursor == actions.size()}
