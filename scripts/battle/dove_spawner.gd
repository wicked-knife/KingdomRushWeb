extends RefCounted
## enemies_spawner payloads use a pending-insert boundary, separate from waves.
static func insert(sim, item: Dictionary) -> void:
	var spec: Dictionary = sim.templates[item.template].spawner
	var nearest = nearest_node(sim, item.pos)
	item.merge({"path": nearest[0], "node": nearest[1], "spawned": 0, "next": sim.tick, "at": sim.tick, "state": spec.get("animation_concurrent", "idle"), "count": int(spec.count) + int(spec.get("count_inc", 0)) * int(item.get("level", 0))}, true)
	sim.spawners.append(item)

static func nearest_node(sim, point: Vector2) -> Array:
	var best = INF
	var found = [0, 0]
	for pi in sim.data.paths.paths.size():
		var path: Array = sim.data.paths.paths[pi][0]
		for ni in path.size():
			var distance: float = point.distance_squared_to(sim.vec(path[ni]))
			if distance < best: best = distance; found = [pi, ni]
	return found

static func random_position(sim, margin: int, terrain: int) -> Dictionary:
	# P:get_random_position: path, subpath, then up to five node rolls.
	# The current source layouts have no NF_RANGE invalid ranges; all nodes
	# are visible in this Dove version (path_db.load's clipping is disabled).
	var active: Array = []
	for i in sim.data.paths.paths.size():
		if sim.data.paths.get("active", [])[i] != false: active.append(i)
	if active.is_empty(): return {}
	var path: int = active[sim.rng.randi_range(0, active.size() - 1)]
	var subpath: int = sim.rng.randi_range(0, 2)
	var route: Array = sim.data.paths.paths[path][subpath]
	var defend := -1
	for entity: Dictionary in sim.data.layout.entities_list:
		if entity.template != "decal_defend_point": continue
		var distance := INF
		var node := -1
		for i in sim.data.paths.paths[path][0].size():
			var d: float = sim.vec(entity.pos).distance_to(sim.vec(sim.data.paths.paths[path][0][i]))
			if d < distance: distance = d; node = i
		if distance < 21: defend = node
	for attempt in 5:
		var node: int = sim.rng.randi_range(0, route.size() - 1)
		var point: Vector2 = sim.vec(route[node])
		if node - margin < 0 or node + margin >= route.size() or defend < 0 or node + margin > defend: continue
		if (sim._terrain_flags(point) & 255 & ~terrain) != 0: continue
		return {"pos": point, "path": path, "subpath": subpath, "node": node}
	return {}

static func step(sim) -> void:
	for item: Dictionary in sim.spawners.duplicate():
		var owner: Dictionary = sim.unit_by_id(item.get("owner", 0))
		var spec: Dictionary = sim.templates[item.template].spawner
		if item.get("interrupted", false) or (item.has("owner") and (owner.is_empty() or owner.hp <= 0)):
			item.spawned = item.count
		if sim.tick < item.next: continue
		if item.spawned < item.count:
			var subpath = int(spec.allowed_subpaths[int(item.spawned) % spec.allowed_subpaths.size()]) - 1
			var node = mini(int(item.node) + int(spec.node_offset), sim.data.paths.paths[item.path][subpath].size() - 1)
			var gold = int(sim.templates[spec.entity].enemy.gold) if spec.get("keep_gold", false) else 0
			if sim.templates[item.template].has("total_gold"): gold = floori(float(sim.templates[item.template].total_gold) / float(sim.templates[spec.entity].enemy.gold))
			sim.pending_entities.append({"kind": "enemy", "template": spec.entity, "path": item.path, "subpath": subpath, "node": node, "pos": item.pos + sim.vec(spec.pos_offset), "gold": gold})
			item.spawned += 1; item.next = sim.tick + sim.frames(spec.cycle_time)
		elif not item.has("fade_at"):
			item.fade_at = sim.tick; item.next = sim.tick + 120
		else: sim.spawners.erase(item)

static func flush(sim) -> void:
	var pending: Array = sim.pending_entities
	sim.pending_entities = []
	for item: Dictionary in pending:
		if item.kind == "spawner": insert(sim, item)
		elif item.kind == "enemy":
			var enemy: Dictionary = sim._spawn_enemy(item.template, item.subpath, item.path, "payload")
			enemy.node = item.node; enemy.pos = item.pos; enemy.progress = float(item.node); enemy.gold_override = item.gold
