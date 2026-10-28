extends "res://scripts/battle/controllers/default_level.gd"
## The source eb_juggernaut branch calls LU.kill_all_enemies(store, true).
func enemy_died(sim, enemy: Dictionary) -> void:
	if sim.behaviors.role(enemy.template) != "juggernaut": return
	for other: Dictionary in sim.enemies:
		var t: Dictionary = sim.templates[other.template]
		if other.id == enemy.id or other.hp <= 0: continue
		if (int(t.vis.flags) & 32) != 0 and int(t.enemy.lives_cost) >= 20: continue
		if int(t.health.immune_to) == 4294967295: continue
		other.gold_override = 0
		sim.damage(other, other.hp, 1)
	for item: Dictionary in sim.spawners: item.interrupted = true
	sim.pending_entities.clear()

func can_finish(sim) -> bool:
	if not sim.pending_entities.is_empty(): return false
	for enemy: Dictionary in sim.enemies:
		if enemy.has("boss") and enemy.hp <= 0 and not enemy.boss.death_handled: return false
	return super.can_finish(sim)
