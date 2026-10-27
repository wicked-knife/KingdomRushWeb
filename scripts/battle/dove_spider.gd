extends RefCounted
## Eggs are scripted spawners, independent of the campaign's timed wave queue.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, enemy: Dictionary) -> void:
	var attack: Dictionary = sim.templates[enemy.template].timed_attacks.list[0]
	enemy.egg_period = sim.frames(sim.rng.randf_range(attack.min_cooldown,attack.max_cooldown))
	enemy.egg_at = sim.tick + int(enemy.egg_period); enemy.eggs_laid = 0

static func lay(sim, enemy: Dictionary) -> void:
	var a: Dictionary = sim.templates[enemy.template].timed_attacks.list[0]
	var limit: int = int(a.max_count[1]) if a.max_count is Array else int(a.max_count)
	if sim.tick <= int(enemy.egg_at) or enemy.eggs_laid >= limit or enemy.blocker != 0: return
	var t: Dictionary = sim.templates[a.bullet]
	var at: int = sim.tick + Anim.duration(sim.animations,Anim.key(t.render.sprites[0],t.spawner.animation_start))
	sim.eggs.append({"template":a.bullet,"pos":enemy.pos,"path":enemy.path,"node":enemy.node,"at":sim.tick,"next":at,"spawned":0,"state":"start"})
	enemy.eggs_laid += 1
	enemy.egg_at = sim.tick + int(enemy.egg_period)
	sim.event.emit("egg_laid",{"source":enemy.id,"count":enemy.eggs_laid})

static func step(sim) -> void:
	for egg: Dictionary in sim.eggs.duplicate():
		var spec: Dictionary = sim.templates[egg.template].spawner
		if sim.tick < int(egg.next): continue
		if int(egg.spawned) < int(spec.count):
			var subpath: int = int(spec.allowed_subpaths[int(egg.spawned) % spec.allowed_subpaths.size()]) - 1
			var enemy: Dictionary = sim._spawn_enemy(spec.entity,subpath,egg.path,"egg")
			enemy.node = mini(int(egg.node) + int(spec.node_offset),sim.data.paths.paths[egg.path][subpath].size() - 1)
			enemy.pos = egg.pos + sim.vec(spec.pos_offset); enemy.progress = float(enemy.node); enemy.gold_override = 0
			egg.spawned += 1; egg.next = sim.tick + sim.frames(spec.cycle_time)
		else:
			# Frozen spawner enables its four-second alpha tween after the hatch cycle.
			if not egg.has("fade_at"): egg.fade_at = sim.tick; egg.next = sim.tick + 120
			else: sim.eggs.erase(egg)
