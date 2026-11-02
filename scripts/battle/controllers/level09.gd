extends "res://scripts/battle/controllers/level06.gd"

func enemy_died(sim,enemy:Dictionary) -> void:
	if not enemy.has("jt"):return
	for other:Dictionary in sim.enemies:
		if other.id==enemy.id or other.hp<=0:continue
		var t:Dictionary=sim.templates[other.template]
		if (int(t.vis.flags)&32)!=0 and int(t.enemy.lives_cost)>=20:continue
		if int(t.health.immune_to)==4294967295:continue
		other.gold_override=0;sim.damage(other,other.hp,1)
	for item:Dictionary in sim.spawners:item.interrupted=true
	sim.pending_entities.clear()

func can_finish(sim) -> bool:
	for enemy:Dictionary in sim.enemies:
		if enemy.has("jt") and not enemy.boss.death_handled:return false
	return super.can_finish(sim)
