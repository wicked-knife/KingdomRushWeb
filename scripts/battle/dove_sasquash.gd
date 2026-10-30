extends RefCounted
## Level fn_can_power + tower_sasquash_holder + doorless mercenary barrack.
static func extra_fire_point(sim, point:Vector2) -> bool:
	for tower:Dictionary in sim.towers:
		var t:Dictionary=sim.tower_template(tower)
		if not t.has("unfreeze_rect"):continue
		return Rect2(sim.vec(t.unfreeze_rect.pos),sim.vec(t.unfreeze_rect.size)).has_point(point)
	return false

static func frozen_step(sim, tower:Dictionary) -> void:
	var t:Dictionary=sim.tower_template(tower)
	for effect:Dictionary in sim.effects:
		if effect.template!="fx_fireball_explosion" or sim.distance(tower.pos+sim.vec(t.tower.range_offset),effect.pos)>float(t.unfreeze_radius):continue
		var upgraded:Dictionary=sim._holder(tower)
		upgraded.template=t.unfreeze_upgrade_to;upgraded.type="barrack";upgraded.inserted=true
		upgraded.hired=0;upgraded.slots=[0];upgraded.terrain_base=false
		sim.towers[sim.towers.find(tower)]=upgraded
		sim.add_effect(t.unfreeze_fx,tower.pos)
		sim.event.emit("sasquash_unfrozen",{"tick":sim.tick,"id":tower.id})
		return

static func price(sim, tower:Dictionary, type:String) -> int:
	if tower.is_empty() or tower.template!="tower_sasquash" or type!="soldier_sasquash" or int(tower.get("hired",0))>=int(sim.tower_template(tower).barrack.max_soldiers):return -1
	return int(sim.templates[type].unit.price)

static func hire(_sim, tower:Dictionary) -> void:
	tower.hired=1

static func step(sim, tower:Dictionary) -> void:
	if int(tower.get("hired",0))==0:return
	if int(tower.slots[0])>0 or -int(tower.slots[0])>sim.tick:return
	var t:Dictionary=sim.tower_template(tower)
	var soldier:Dictionary=sim._soldier(t.barrack.soldier_type,tower.id,0,tower.pos+sim.vec(t.barrack.respawn_offset),tower.rally)
	sim.behaviors.soldier_inserted(sim,soldier,tower)
	tower.slots[0]=soldier.id
	sim.event.emit("sound",{"id":sim.templates[soldier.template].sound_events.insert})
