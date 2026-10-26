extends RefCounted
## Reusable legal player command replay. No money, damage or enemy overrides.
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
static var fourth_commands: Dictionary = {}
static var rejected: Array[String] = []

static func send(sim, kind: String, args: Dictionary = {}, driver: Callable = Callable()) -> bool:
	if not driver.is_valid(): return sim.command(kind, args)
	if kind in ["build", "upgrade"]:
		var name: String = "tower_" + str(args.type) + "_1" if kind == "build" else str(args.upgrade_to)
		if sim.gold < int(sim.templates[name].tower.price) or sim.tower_by_id(str(args.id)).ready > sim.tick: return false
	if kind == "cast" and (sim.cooldowns[args.power] != 0 or not sim.valid_power_point(args.power, args.pos)): return false
	var gold: int = sim.gold; var wave: int = sim.wave; var notices: int = sim.notices.size()
	driver.call(kind, args)
	match kind:
		"build", "upgrade": return sim.gold < gold
		"wave": return sim.wave > wave
		"confirm": return sim.notices.size() < notices
		"cast": return sim.cooldowns[args.power] > 0
	return true

static func dismiss(sim, driver: Callable = Callable()) -> void:
	while not sim.notices.is_empty():
		if not send(sim, "confirm", {}, driver): break

static func orders(id: int) -> Array:
	if id == 2:
		var plan: Array = []
		for site in ["6", "1", "2", "3", "4", "7", "5"]: plan.append([site, "mage"])
		for site in ["6", "1", "2", "3", "4", "7", "5"]: plan.append([site, "mage_2"])
		return plan
	return [["6", "mage"], ["5", "archer"], ["2", "archer"], ["12", "archer"], ["4", "engineer"], ["6", "mage_2"], ["5", "archer_2"], ["4", "engineer_2"], ["2", "archer_2"], ["12", "archer_2"], ["11", "mage"], ["11", "mage_2"], ["3", "archer"], ["3", "archer_2"], ["10", "archer"], ["1", "archer"], ["9", "archer"], ["8", "archer"], ["7", "archer"]]

static func recorded_fourth(sim, driver: Callable) -> void:
	if fourth_commands.is_empty():
		var replay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/level04_victory.json"))
		for action: Dictionary in replay.actions:
			var tick: int = int(action.tick)
			if not fourth_commands.has(tick): fourth_commands[tick] = []
			fourth_commands[tick].append(action)
	for action: Dictionary in fourth_commands.get(sim.tick, []):
		var args: Dictionary = action.args.duplicate(true)
		if args.has("pos"): args.pos = Sim.vec(args.pos)
		if not send(sim, action.kind, args, driver):
			var message := "Fourth replay command rejected at %d: %s" % [sim.tick, action.kind]
			rejected.append(message); push_error(message)

static func commands(sim, driver: Callable = Callable()) -> void:
	dismiss(sim, driver)
	var id: int = sim.data.level.id
	if id == 4:
		recorded_fourth(sim, driver); return
	var plan: Array = orders(id)
	for entry: Array in plan:
		var tower: Dictionary = sim.tower_by_id(entry[0])
		if str(entry[1]).ends_with("_2") or str(entry[1]).ends_with("_3"):
			var desired: String = "tower_" + str(entry[1])
			if int(sim.tower_template(tower).tower.level) < int(sim.templates[desired].tower.level) and not send(sim, "upgrade", {"id": entry[0], "upgrade_to": desired}, driver): break
		elif tower.type == "":
			if not send(sim, "build", {"id": entry[0], "type": entry[1]}, driver): break
	var built: bool = sim.towers.all(func(t): return t.type != "")
	if built:
		for entry: Array in plan:
			var tower: Dictionary = sim.tower_by_id(entry[0])
			var target: String = sim.upgrade_target(tower)
			if target != "":
				if not send(sim, "upgrade", {"id": tower.id, "upgrade_to": target}, driver): break
	if sim.cooldowns.fire == 0:
		var best := {}; var score := -INF
		for e: Dictionary in sim.enemies:
			if e.hp <= 0 or not sim.valid_ground(e.pos): continue
			var value := 0.0
			for other: Dictionary in sim.enemies:
				if other.hp > 0 and sim.distance(e.pos, other.pos) < 70: value += minf(other.hp, 100)
			if value > score: best = e; score = value
		if not best.is_empty() and sim.cooldowns.fire == 0 and (score >= 180 or best.template == "enemy_ogre"):
			send(sim, "cast", {"power": "fire", "pos": best.pos}, driver)
	if sim.cooldowns.reinforcements == 0:
		var target: Dictionary = sim._target(Vector2(600, 220) if id == 3 else (Vector2(570, 630) if id == 4 else Vector2(540, 370)), 180)
		if not target.is_empty() and sim.valid_ground(target.pos): send(sim, "cast", {"power": "reinforcements", "pos": target.pos}, driver)
	if sim.wave == 0: send(sim, "wave", {}, driver)

static func play(id: int, defend: bool = true):
	var sim = Sim.new(Levels.load_definition(id), 42)
	dismiss(sim)
	if defend:
		if id != 4: commands(sim)
	else: sim.command("wave")
	for i in range(60000):
		dismiss(sim)
		if defend and i % 5 == 0: commands(sim)
		sim.step()
		if sim.result != "": break
	return sim
