extends RefCounted
## Shared source tunnel, aura_unit_regen and particle emitters. No level IDs.
const Anim = preload("res://scripts/battle/dove_animation.gd")
var tunnels: Array = []
var particles: Array = []
var lights: Array = []
var emitters: Array = []
var rng := RandomNumberGenerator.new()

func reset(sim) -> void:
	tunnels.clear(); particles.clear(); lights.clear(); emitters.clear(); rng.seed = 4717
	for entity: Dictionary in sim.data.layout.entities_list:
		var template: Dictionary = sim.templates.get(entity.template,{})
		if template.has("tunnel"):
			var t: Dictionary = template.tunnel.duplicate(true)
			t.pick_pi=int(t.pick_pi)-1; t.place_pi=int(t.place_pi)-1
			t.pick_ni=int(t.get("pick_ni",sim.data.paths.paths[t.pick_pi][0].size()-1))-1
			t.place_ni=int(t.get("place_ni",1))-1; t.queue=[]
			t.length=sim.vec(sim.data.paths.paths[t.pick_pi][0][t.pick_ni]).distance_to(sim.vec(sim.data.paths.paths[t.place_pi][0][t.place_ni]))
			tunnels.append(t)
		elif template.get("template_name","") == "decal_tunnel_light": lights.append({"template":entity.template,"pos":sim.vec(entity.pos),"names":entity.get("track_names",[])})
		elif template.has("particle_system"):
			var emitter := {"template":entity.template,"pos":sim.vec(entity.pos),"next":0.0}
			emitters.append(emitter)
			var ps: Dictionary = template.particle_system
			var warm := int(-float(ps.get("ts_offset",0))*30)
			for age in range(-warm,0,maxi(1,roundi(30/float(ps.emission_rate)))): _emit(sim,emitter.template,emitter.pos,age)

func occupied() -> bool:
	return tunnels.any(func(t): return not t.queue.is_empty())

func enemy_inserted(sim, enemy: Dictionary) -> void:
	if sim.templates[enemy.template].get("auras",{}).get("list",[]).any(func(a): return a.get("name","") == "aura_troll_regen"):
		enemy.regen_ts=float(sim.tick)/30

func step(sim) -> void:
	for tunnel: Dictionary in tunnels:
		for enemy: Dictionary in sim.enemies.duplicate():
			if enemy.hp<=0 or enemy.path!=tunnel.pick_pi or enemy.node<tunnel.pick_ni: continue
			var speed: float = float(sim.templates[enemy.template].motion.max_speed)*float(sim.data.rules.enemy_speed_factor)*sim.modifiers.speed(enemy.id,sim)
			var release: float = float(sim.tick)+float(tunnel.length)/(float(tunnel.speed_factor)*maxf(speed,0.000001))*30
			sim._unblock(enemy)
			for m: Dictionary in sim.modifiers.active.duplicate():
				if m.target==enemy.id: sim.modifiers._release(sim,m); sim.modifiers.active.erase(m)
			enemy.erase("regen_ts"); enemy.pending={}; enemy.casting={}
			sim.enemies.erase(enemy); sim.cell_for_enemy.erase(enemy.id); sim.spatial_tick=-1
			tunnel.queue.append({"enemy":enemy,"release":release})
			sim.event.emit("tunnel_enter",{"id":enemy.id,"tick":sim.tick,"release":release,"name":tunnel.name})
		for index in range(tunnel.queue.size()-1,-1,-1):
			var transfer: Dictionary = tunnel.queue[index]
			if float(sim.tick)+0.000001<float(transfer.release): continue
			var enemy: Dictionary = transfer.enemy
			enemy.path=tunnel.place_pi; enemy.node=tunnel.place_ni; enemy.progress=float(enemy.node)
			enemy.pos=sim.vec(sim.data.paths.paths[enemy.path][enemy.subpath][enemy.node]); enemy.last_dir=Vector2.ZERO
			enemy.attack_at=sim.tick; enemy.heal_at=sim.tick
			sim.enemies.append(enemy); sim.behaviors.enemy_inserted(sim,enemy); sim.spatial_tick=-1
			tunnel.queue.remove_at(index)
			sim.event.emit("tunnel_exit",{"id":enemy.id,"tick":sim.tick,"name":tunnel.name})
	for enemy: Dictionary in sim.enemies:
		if enemy.hp<=0 or not enemy.has("regen_ts"): continue
		var regen: Dictionary = sim.templates.aura_troll_regen.regen
		if int(enemy.get("silence_count",0))>0: enemy.regen_ts=float(sim.tick)/30; continue
		if float(sim.tick)/30-float(enemy.regen_ts)>=float(regen.cooldown):
			enemy.regen_ts+=float(regen.cooldown)
			if (regen.get("ignore_stun",false) or int(enemy.get("stun_count",0))==0) and (regen.get("ignore_mods",false) or (int(enemy.get("vis",sim.templates[enemy.template].vis).bans)&int(sim.data.constants.F_MOD))==0): enemy.hp=minf(enemy.max_hp,enemy.hp+float(regen.health))
	for emitter: Dictionary in emitters:
		var ps: Dictionary = sim.templates[emitter.template].particle_system
		if sim.tick>=float(emitter.next):
			_emit(sim,emitter.template,emitter.pos,sim.tick); emitter.next+=30/float(ps.emission_rate)
	particles=particles.filter(func(p):return sim.tick-p.at<p.duration)

func emit_trail(sim, projectile: Dictionary, template: String) -> void:
	var ps: Dictionary = sim.templates[template].particle_system
	if sim.tick<float(projectile.get("particle_at",0)): return
	projectile.particle_at=float(sim.tick)+30/float(ps.emission_rate)
	_emit(sim,template,projectile.pos,sim.tick,float(projectile.rotation))

func _emit(sim, template: String, point: Vector2, at: int, rotation: float = 0) -> void:
	var ps: Dictionary = sim.templates[template].particle_system
	var area: Vector2 = sim.vec(ps.get("emit_area_spread",{"x":0,"y":0}))
	var spread := float(ps.get("emit_spread",0))
	var angle := float(ps.get("emit_direction",0))+rng.randf_range(-spread/2,spread/2)
	var speed: Array = ps.get("emit_speed",[0,0])
	var life: Array = ps.particle_lifetime
	var scale_value: Array = ps.get("scale_var",[1,1])
	particles.append({"template":template,"pos":point+Vector2(rng.randf_range(-area.x/2,area.x/2),rng.randf_range(-area.y/2,area.y/2)),"at":at,
		"velocity":Vector2(cos(angle),sin(angle))*rng.randf_range(speed[0],speed[1]),"duration":maxi(1,roundi(rng.randf_range(life[0],life[1])*30)),"scale":rng.randf_range(scale_value[0],scale_value[1]),"rotation":rotation})

func queue(view) -> void:
	var sim = view.sim
	for light: Dictionary in lights:
		if tunnels.any(func(t):return t.name in light.names and not t.queue.is_empty()): view._queue_template(light.template,light.pos,"",0,false,false,1,false,"",{"layers":{1:{"visible":true,"state":"","at":0,"loop":true}}})
	for particle: Dictionary in particles:
		var ps: Dictionary = sim.templates[particle.template].particle_system
		var elapsed: int = sim.tick-int(particle.at)
		var fraction := clampf(float(elapsed)/particle.duration,0,1)
		var alphas: Array = ps.get("alphas",[255,0])
		var segment := fraction*(alphas.size()-1)
		var index := mini(int(segment),alphas.size()-2)
		var alpha := lerpf(float(alphas[index]),float(alphas[index+1]),segment-index)/255
		var frame: String = ps.name
		if ps.get("animated",false): frame=Anim.frame({"name":ps.name,"animated":true},sim.animations,{"elapsed":elapsed,"loop":ps.get("loop",true)})
		var pos: Vector2 = particle.pos+particle.velocity*float(elapsed)/30
		view.draw_list.append({"scale":Vector2.ONE*float(particle.scale),"frame":frame,"pos":pos,"sort_y":pos.y,"anchor":Vector2(0.5,0.5),"z":int(ps.get("z",3000)),"order":view.draw_list.size(),"flip":false,"rotation":particle.rotation,"tint":Color(1,1,1,alpha)})
