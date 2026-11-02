extends RefCounted
## kr1 tower_sorcerer and all/scripts.mod_polymorph. State belongs to one battle.
const Anim = preload("res://scripts/battle/dove_animation.gd")

static func initialize(sim, tower: Dictionary) -> void:
	tower.powers = {"polymorph":0,"elemental":0}
	tower.slots = [0]; tower.hired = 1; tower.layers = {}
	tower.sorcerer = {"timestamps":[sim.tick,0],"casting":{},"resume":0,"elemental_pos":tower.rally}

static func upgraded(sim, tower: Dictionary, power: String) -> void:
	if power == "polymorph" and tower.powers.polymorph == 1: tower.sorcerer.timestamps[1] = sim.tick
	if power != "elemental": return
	var s: Dictionary = sim.unit_by_id(int(tower.slots[0]))
	if s.is_empty(): return
	var t: Dictionary = s.combat_template
	s.armor = float(s.get("armor",t.health.armor))+float(t.health.armor_inc)
	s.max_hp += float(t.health.hp_inc); s.hp = s.max_hp
	for key: String in ["damage_min","damage_max"]: t.melee.attacks[0][key] += float(t.melee.attacks[0].damage_inc)

static func _elemental(sim, tower: Dictionary, t: Dictionary) -> void:
	if tower.powers.elemental == 0: return
	var old: Dictionary = sim.unit_by_id(int(tower.slots[0]))
	if not old.is_empty():
		if old.hp > 0: return
		tower.sorcerer.elemental_pos = old.pos
		if sim.tick-old.dead_at <= sim.frames(sim.templates[old.template].health.dead_lifetime): return
	if int(tower.slots[0]) < 0 and sim.tick <= -int(tower.slots[0]): return
	var s: Dictionary = sim._soldier(t.barrack.soldier_type,tower.id,0,tower.sorcerer.elemental_pos,tower.rally)
	var st: Dictionary = s.combat_template
	var level: int = int(tower.powers.elemental)
	s.max_hp += float(st.health.hp_inc)*level; s.hp = s.max_hp
	s.armor = float(st.health.armor)+float(st.health.armor_inc)*level
	for key: String in ["damage_min","damage_max"]: st.melee.attacks[0][key] += float(st.melee.attacks[0].damage_inc)*level
	sim.DamageFactors.inherit(sim,s,tower)
	s.raise_until = sim.tick+Anim.duration(sim.animations,Anim.key(st.render.sprites[0],"raise"))
	sim._state(s,"raise",true); s.playback_loop = false
	tower.slots[0] = s.id
	sim.event.emit("sound",{"id":st.sound_events.insert})

static func _targets(sim, tower: Dictionary, attack: Dictionary) -> Array:
	var t: Dictionary = sim.tower_template(tower)
	return sim.Ranger.candidates(sim,tower.pos+sim.vec(t.tower.range_offset),float(t.attacks.range),attack)

static func step(sim, tower: Dictionary) -> void:
	var t: Dictionary = sim.tower_template(tower)
	var state: Dictionary = tower.sorcerer
	var cast: Dictionary = state.casting
	if not cast.is_empty():
		var a: Dictionary = t.attacks.list[int(cast.index)]
		if not cast.fired and sim.tick >= cast.at:
			cast.fired = true
			var e: Dictionary = sim.unit_by_id(int(cast.target))
			if e.is_empty() or e.hp <= 0:
				var choices: Array = _targets(sim,tower,a)
				e = {} if choices.is_empty() else choices[0]
			if not e.is_empty() and sim.distance(tower.pos+sim.vec(t.tower.range_offset),e.pos) <= float(t.attacks.range):
				var from: Vector2 = tower.pos+sim.vec(a.bullet_start_offset[int(cast.angle)])
				var bt: Dictionary = sim.templates[a.bullet]
				sim._projectile(a.bullet,e.id,from,e.pos,float(bt.get("ray_duration",1)),tower)
				sim.projectiles[-1].level = maxi(1,int(tower.powers.polymorph)) if int(cast.index)==1 else 1
		if sim.tick < cast.end: return
		state.casting = {}; state.resume = int(cast.order)+1
	if tower.get("blocked",false): return
	_elemental(sim,tower,t)
	var order: Array = [1,0]
	for position: int in range(int(state.resume),2):
		var index: int = int(order[position])
		var a: Dictionary = t.attacks.list[index]
		if index == 1 and (tower.powers.polymorph == 0 or not t.tower.can_do_magic): continue
		var cooldown: float = float(a.cooldown) if index==0 else float(t.powers.polymorph.cooldown_base)+float(t.powers.polymorph.cooldown_inc)*int(tower.powers.polymorph)
		if float(sim.tick)/30-float(state.timestamps[index])/30 <= cooldown*float(tower.get("cooldown_factor",t.tower.cooldown_factor)): continue
		var choices: Array = _targets(sim,tower,a)
		if choices.is_empty(): state.timestamps[index] += 3; continue
		var target: Dictionary = choices[0]
		if index == 0:
			for candidate: Dictionary in choices:
				# The source queries template.mod (nil), so any applied modifier counts.
				if not sim.modifiers.active.any(func(m):return m.target==candidate.id): target=candidate; break
		state.timestamps[index] = sim.tick
		var up: bool = target.pos.y > tower.pos.y+float(t.render.sprites[2].offset.y)
		var animation: String = "polymorph" if index==1 else "shoot"
		tower.layers[2] = {"state":animation,"at":sim.tick,"loop":false}
		tower.layers[3] = {"state":("polymorph" if index==1 else "shooting")+("Up" if up else "Down"),"at":sim.tick,"loop":false,"flip":target.pos.x<tower.pos.x}
		if index==1: tower.layers[4]={"state":"fx_tower_sorcerer_polymorph","at":sim.tick,"loop":false,"visible":true}
		state.casting={"index":index,"order":position,"target":target.id,"angle":0 if up else 1,"at":sim.tick+sim.source_unconditional_wait_ticks(sim.tick,float(a.shoot_time)),"end":sim.tick+Anim.duration(sim.animations,Anim.key(t.render.sprites[1],animation)),"fired":false}
		return
	state.resume = 0
	if float(sim.tick)/30-float(state.timestamps[0])/30>float(t.tower.long_idle_cooldown):
		var point:Vector2=sim.vec(t.tower.long_idle_pos)
		tower.layers[3]={"state":"idleUp" if point.y>tower.pos.y else "idleDown","at":sim.tick,"loop":true,"flip":point.x<tower.pos.x}
	if float(sim.tick)/30-float(state.timestamps[0])/30>float(t.tower.long_idle_cooldown):
		var point:Vector2=sim.vec(t.tower.long_idle_pos)
		tower.layers[3]={"state":"idleUp" if point.y>tower.pos.y else "idleDown","at":sim.tick,"loop":true,"flip":point.x<tower.pos.x}

static func polymorph(sim, target: Dictionary, t: Dictionary) -> bool:
	if (int(target.get("vis",sim.templates[target.template].vis).bans)&2097152)!=0:return false
	if (int(target.get("vis",sim.templates[target.template].vis).bans)&2097152)!=0:return false
	if not sim.modifiers.flags_match(sim,target,t.modifier): return false
	var pm: Dictionary = t.polymorph
	var old: Dictionary = sim.templates[target.template]
	var flying: bool = (int(target.get("vis",old.vis).flags)&128)!=0
	var type: String = pm.custom_entity_names.flying if flying else pm.custom_entity_names.default
	var hp: float = floorf(target.hp*float(pm.transfer_health_factor))
	var gold: int = floori(sim.unit_gold(target)*float(pm.transfer_gold_factor))
	var cost: int = floori(float(target.get("lives_cost",old.enemy.lives_cost))*float(pm.transfer_lives_cost_factor))
	var speed: float = float(old.motion.max_speed)*sim.modifiers.speed(target.id,sim)*float(pm.transfer_speed_factor)
	var e: Dictionary = sim._spawn_enemy(type,target.subpath,target.path,"polymorph")
	e.pos=target.pos; e.node=target.node; e.progress=target.progress
	e.hp=hp; e.max_hp=hp; e.gold_override=gold; e.lives_cost=cost
	e.speed_bonus=speed-float(sim.templates[type].motion.max_speed)
	e.clicks_required=maxi(1,ceili(hp/4000.0*float(sim.templates[type].clicks_to_destroy))) if hp<4000 else int(sim.templates[type].clicks_to_destroy)
	e.sheep_clicks=0; e.click_pending=false
	target.gold_override=0; sim._unblock(target)
	for m: Dictionary in sim.modifiers.active.duplicate():
		if m.target==target.id: sim.modifiers._release(sim,m);sim.modifiers.active.erase(m)
	target.hp=0;target.dead_at=sim.tick;target.hidden=true;target.pending={}
	if pm.has("hit_fx_sizes"): sim.add_effect(pm.hit_fx_sizes[clampi(int(old.unit.size)-1,0,2)],target.pos+sim.vec(old.unit.mod_offset))
	sim.event.emit("sound",{"id":sim.templates[type].sound_events.insert})
	return false

static func sheep_step(sim, e: Dictionary) -> bool:
	if not e.get("click_pending",false): return false
	e.click_pending=false
	var required: int = int(e.get("clicks_required",sim.templates[e.template].clicks_to_destroy))
	e.sheep_clicks=int(e.get("sheep_clicks",0))+1
	sim.damage(e,float(e.max_hp)/required,1)
	if int(e.sheep_clicks)>=required and e.hp>0:sim.damage(e,e.hp,1)
	return e.hp<=0
