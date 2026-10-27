extends "res://scripts/battle/level01_sim.gd"
## Only this standalone simulator accepts arena commands. No campaign persistence.
const ROSTER := ["enemy_goblin","enemy_fat_orc","enemy_wolf_small","enemy_brigand","enemy_ogre","enemy_spider_small"]

func reset(seed_value: int = 42) -> void:
	super.reset(seed_value)

func command(kind: String, args: Dictionary = {}) -> bool:
	if kind == "arena_gold": gold += 10000; return true
	if kind == "arena_clear":
		modifiers.clear(self)
		for enemy: Dictionary in enemies: _unblock(enemy)
		enemies.clear(); spawn_queue.clear(); projectiles.clear(); effects.clear(); alerts.clear()
		enemy_cells.clear(); cell_for_enemy.clear(); spatial_tick = -1
		for tower: Dictionary in towers:
			tower.pending = {}
			if tower.has("ranger"):
				tower.ranger.reservations.clear(); tower.ranger.casting = {}; tower.ranger.thorn_ts = float(tick)
		for soldier: Dictionary in soldiers: soldier.pending = {}
		return true
	if kind == "arena_spawn":
		var type: String = args.get("type","")
		var count := int(args.get("count",1)); var path := int(args.get("path",0))
		if paused or type not in ROSTER or count not in [1,5,10] or path not in [0,1]: return false
		if wave == 0: _start_wave(true)
		for i in range(count): spawn_queue.append({"type":type,"path":path,"subpath":1,"tick":tick + 1 + i * 15})
		spawn_queue.sort_custom(func(a,b): return a.tick < b.tick)
		return true
	return super.command(kind,args)

func _finish(_value: String) -> void:
	pass # Endless manual fixture, no campaign outcome or repeated victory audio.
