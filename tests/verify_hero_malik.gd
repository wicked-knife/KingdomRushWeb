extends SceneTree
const Levels=preload("res://scripts/services/campaign_levels.gd")
const Setup=preload("res://scripts/services/battle_setup.gd")
const Sim=preload("res://scripts/battle/level01_sim.gd")
const Heroes=preload("res://scripts/battle/dove_heroes.gd")
const Grid=preload("res://scripts/battle/dove_grid_path.gd")
var failures: Array[String]=[]
var checks := 0
var scenarios := 0
var comparisons := {}
func _init() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func difference(a: Variant,b: Variant,path: String="") -> String:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return path+" keys"
		for key in a:
			if not b.has(key):return path+" missing "+str(key)
			var found:=difference(a[key],b[key],path+"/"+str(key))
			if found!="":return found
	elif a is Array and b is Array:
		if a.size()!=b.size():return path+" count "+str(a.size())+" != "+str(b.size())
		for i in a.size():
			var found:=difference(a[i],b[i],path+"/"+str(i))
			if found!="":return found
	elif (a is float or a is int) and (b is float or b is int):
		if absf(float(a)-float(b))>(0.002 if path.begins_with("walk_") else 0.00002):return path+": "+str(a)+" != "+str(b)
	elif a!=b:return path+": "+str(a)+" != "+str(b)
	return ""
func compare(name: String,expected: Variant,actual: Variant) -> void:
	var found:=difference(expected,actual,name)
	comparisons[name]={"expected":expected,"actual":actual,"first_difference":found}
	check(found=="",found);scenarios+=1
func arena(id: int=3,mode: int=1,selected: Array=["hero_malik"]):
	var definition := Setup.create(Levels.load_definition(id,mode),{"heroes":{"selected":selected},"upgrades":{}})
	check(not definition.is_empty(),"combat resources load: "+Setup.last_error)
	var sim=Sim.new(definition,42)
	while not sim.notices.is_empty():sim.command("confirm")
	return sim
func set_level(sim,h: Dictionary,level: int) -> void:
	for l in range(1,level+1):h.hero.level=l;Heroes.level_up(sim,h)
	h.hero_phase="active";h.health_bar_hidden=false
func stats(reference: Dictionary) -> void:
	var sim=arena();var h: Dictionary=sim.soldiers[0];var result: Array=[]
	for l in range(1,11):
		set_level(sim,h,l)
		var a: Array=sim.templates.hero_malik.melee.attacks;var au: Dictionary=sim.templates.aura_malik_fissure.aura
		result.append({"level":l,"hp":h.hp,"armor":h.armor,"regen":ceilf(h.max_hp*float(sim.data.hero_rules.soldier_regen_factor)),
			"min":a[0].damage_min,"max":a[0].damage_max,"smash":h.hero.skills.smash.level,"fissure":h.hero.skills.fissure.level,
			"smash_min":a[2].get("damage_min",0),"smash_max":a[2].get("damage_max",0),"stun_chance":a[2].mod_chance,"fissure_min":au.damage_min,"fissure_max":au.damage_max})
	compare("levels",reference.levels,result)
	var lengths := {}
	for name: String in reference.animation_lengths:lengths[name]=sim.animations["hero_malik_"+name].frames.size()
	compare("animation_lengths",reference.animation_lengths,lengths)
	compare("attack_order",reference.order.map(func(i):return int(i)-1),h.attack_order)
	for sample: Dictionary in reference.xp:
		sim=arena(int(sample.level_id));h=sim.soldiers[0];result=[]
		for row: Dictionary in sample.steps:
			h.hero.xp_queued=float(row.queued);var changed: bool=Heroes.update_xp(sim,h)
			result.append({"queued":row.queued,"xp":h.hero.xp,"level":h.hero.level,"changed":changed})
		compare("xp_"+str(sample.level_id),sample.steps,result)
	for sample: Dictionary in reference.choices:
		sim=arena();h=sim.soldiers[0];set_level(sim,h,10)
		var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",0);e.pos=h.pos
		for seed_value in 1000:
			sim.rng.seed=seed_value;var draw: float=sim.rng.randf()
			if (draw<0.3)==(float(sample.draw)<0.3):sim.rng.seed=seed_value;break
		sim.tick=int(sample.tick)
		compare("choice_"+str(sample.tick)+"_"+str(sample.draw),int(sample.index),Heroes.choose_attack(sim,h,e,sim.templates.hero_malik))
func attacks(reference: Dictionary) -> void:
	for row: Dictionary in reference.attacks:
		var sim=arena();var h: Dictionary=sim.soldiers[0];set_level(sim,h,10)
		h.pos=Vector2(440,400)
		var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",0);e.pos=h.pos+Vector2(22,0);e.hp=10000;e.max_hp=10000;e.armor=0
		h.target=e.id;e.blockers=[h.id];e.blocker=h.id
		var a: Dictionary=sim.templates.hero_malik.melee.attacks[int(row.index)]
		a.damage_min=row.value;a.damage_max=row.value
		sim.tick=int(row.start);h.hero_phase="attack";sim._state(h,a.animation,true)
		h.pending={"index":int(row.index),"target":e.id,"started":sim.tick,"at":sim.tick+sim.source_wait_ticks(sim.tick,float(a.hit_time)),"resolved":false}
		h.busy_until=sim.tick+Heroes.animation_ticks(sim,h,a.animation)
		var hit_tick := -1
		while h.hero_phase=="attack":
			if not h.pending.resolved and sim.tick>=h.pending.at:hit_tick=sim.tick
			sim.heroes.attack_step(sim,h,sim.templates.hero_malik)
			if h.hero_phase!="attack":break
			sim.tick+=1
		compare("attack_"+str(row.index)+"_"+str(row.start),row,{"index":row.index,"start":row.start,"hit":hit_tick,"stop":sim.tick,"value":10000-e.hp,"xp":float(a.get("xp_gain_factor",0))})
		check(is_equal_approx(float(h.hero.xp_queued),(10000-e.hp)*float(row.xp)),"actual damage queues attack XP")
		check(h.attack_ts[int(row.index)]==int(row.start),"cooldown committed at impact")
	var sim=arena();var h: Dictionary=sim.soldiers[0];set_level(sim,h,10)
	Heroes.gain_skill_xp(h,"fissure");h.hero_phase="attack";h.pending={"at":9999}
	h.hero_move_pending=true;h.dest=h.pos;sim.heroes.step(sim,h)
	check(h.pending.is_empty() and h.hero.xp_queued==200,"new rally interrupts windup but retains skill XP");scenarios+=1
func deaths(reference: Dictionary) -> void:
	for sample: Dictionary in reference.deaths:
		var sim=arena();var h: Dictionary=sim.soldiers[0];h.hero_phase="active";h.pos=Vector2.ZERO;h.hp=0;h.last_damage_types=int(sample.kind)
		var actual: Array=[];var expected: Array=[]
		for tick in range(470):
			sim.tick=tick;sim.heroes.step(sim,h)
			for row: Dictionary in sample.states:
				if int(row.tick)!=tick:continue
				expected.append({"tick":row.tick,"hidden":row.hidden,"click":row.click,"hp":row.hp,"ignore":row.ignore})
				actual.append({"tick":tick,"hidden":h.get("hidden",false),"click":h.can_click,"hp":h.hp,"ignore":h.get("ignore_damage",false)})
				if tick==60:check(sim.effects.any(func(f):return f.template=="decal_hero_tombstone"),"source tombstone insertion")
				if tick==450:check(not sim.effects.any(func(f):return f.template=="decal_hero_tombstone"),"source tombstone removal")
		compare("death_"+str(sample.kind),expected,actual)
		check(h.hero_phase=="active" and h.state=="idle","respawn returns to combat idle")
	var sim=arena();var h: Dictionary=sim.soldiers[0];h.hp=100;h.hero_phase="active"
	var pulses: Array=[]
	for tick in range(101):
		sim.tick=tick;var old: float=h.hp;sim.heroes.step(sim,h)
		if old!=float(h.hp):pulses.append({"tick":tick,"hp":h.hp})
	compare("regen",reference.regen,pulses)
func fissures(reference: Dictionary) -> void:
	for row: Dictionary in reference.fissures:
		var sim=arena(int(row.level_id));var point: Vector2=sim.vec(row.pos)
		var e := {}
		if row.has_target:e=sim._spawn_enemy("enemy_fat_orc",0);e.path=0;e.node=79;e.pos=point
		var aura: Dictionary=sim.templates.aura_malik_fissure.aura.duplicate(true);aura.level=int(row.rank)
		sim.heroes.fissures=[{"template":"aura_malik_fissure","pos":point,"target":e.get("id",0),"source":0,"aura":aura,"at":31,"spread":0,"paths":[]}]
		var result: Array=[]
		for tick in range(31,81):
			sim.tick=tick;var before: int=sim.effects.size();sim.heroes.step_auras(sim)
			for f: Dictionary in sim.effects.slice(before):result.append({"name":f.template,"tick":tick,"x":f.pos.x,"y":f.pos.y})
			if sim.heroes.fissures.is_empty():break
		compare("fissure_"+str(row.level_id)+"_"+str(row.rank)+"_"+str(row.has_target),{"pulses":row.pulses,"stop":row.stop},{"pulses":result,"stop":sim.tick})
func paths(reference: Dictionary) -> void:
	for index in reference.paths.size():
		var row: Dictionary=reference.paths[index];var sim=arena(int(row.level_id))
		var points: Variant=Grid.new().waypoints(sim.data.terrain,sim.vec(row.from),sim.vec(row.fallback),sim.vec(row.to),2049)
		var result: Array=[]
		if points!=null:
			for p: Vector2 in points:result.append({"x":p.x,"y":p.y})
		compare("grid_"+str(index),{"found":row.found,"points":[] if row.points is Dictionary else row.points},{"found":points!=null,"points":result})
		if row.has("walk"):
			var h: Dictionary=sim.soldiers[0];h.hero_phase="active";h.pos=sim.vec(row.from);h.dest=sim.vec(row.to);h.rally_center=h.dest;h.waypoints=points;h.hero_move_pending=true
			var walked: Array=[]
			for tick in range(501):
				sim.tick=tick;sim.heroes.step(sim,h)
				for frame: Dictionary in row.walk:
					if int(frame.tick)==tick:walked.append({"tick":tick,"x":h.pos.x,"y":h.pos.y,"done":h.hero_phase!="moving"})
				if h.hero_phase!="moving":break
			compare("walk_"+str(index),row.walk,walked)
func boundaries() -> void:
	var sim=arena();var h: Dictionary=sim.soldiers[0];var frozen: String=var_to_str(sim.base_templates)
	check(h.hero.level==1 and h.hp==450,"battle starts level one and full HP")
	sim.tick=100;h.hero_phase="active";h.pos=sim.vec(sim.data.paths.paths[0][0][79]);h.dest=h.pos
	var old: float=h.hp;h.move_immune=int(sim.templates.hero_malik.hero_rally.immune_to)
	check(sim.damage(h,50,2)==0 and h.hp==old,"moving hero immune to physical attacks")
	check(sim.damage(h,10,65536)==10,"source movement still permits poison");h.move_immune=0
	check(not sim.command("move_hero",{"id":h.id,"pos":Vector2.INF}),"invalid destination rejected")
	set_level(sim,h,10);sim.heroes.fissures.append({});sim.reset(42)
	check(sim.soldiers[0].hero.level==1 and sim.soldiers[0].hero.xp==0 and sim.heroes.fissures.is_empty(),"restart clears progression and generators")
	check(frozen==var_to_str(sim.base_templates),"runtime progression preserves source templates")
	for mode in [2,3]:check(arena(3,mode).soldiers.all(func(s):return not s.has("hero")),"source challenge hero lock "+str(mode))
	check(arena(3,1,[]).soldiers.all(func(s):return not s.has("hero")),"empty selection stays empty")
	check(arena(3,1,["hero_gerald"]).soldiers.all(func(s):return not s.has("hero")),"preview-only hero excluded from battle")
	check(arena(7).soldiers.filter(func(s):return s.has("hero")).size()==1,"shared hero bundle loads in another stage");scenarios+=4
	var e: Dictionary=sim._spawn_enemy("enemy_fat_orc",0)
	check(sim.modifiers.apply(sim,"mod_malik_stun",e,1,"hero"),"source stun inserts")
	check(e.stun_count==1 and sim.modifiers.active[-1].prefix=="stun_small","stun counter and source size-specific sprite")
	sim.tick+=30;sim.modifiers.apply(sim,"mod_malik_stun",e,1,"hero")
	check(e.stun_count==1 and sim.modifiers.count(e.id,"mod_malik_stun")==1,"same stun refreshes without stacking")
	sim.tick+=59;sim.modifiers.step(sim);check(e.stun_count==1,"stun stays until refreshed deadline")
	sim.tick+=1;sim.modifiers.step(sim);check(e.stun_count==0,"stun removes and releases at duration")
	for flag in [32,128]:
		e.vis=sim.templates[e.template].vis.duplicate(true);e.vis.flags=int(e.vis.flags)|flag
		check(not sim.modifiers.apply(sim,"mod_malik_stun",e,1,"hero"),"source boss/flying stun ban "+str(flag))
	var bundle: Dictionary=Levels.read_json("res://data/hero_malik_combat/definition.json")
	for child in ["aura_malik_fissure","mod_malik_stun","decal_hero_tombstone","fx_soldier_desintegrate"]:
		var broken: Dictionary=bundle.duplicate(true);broken.templates.erase(child)
		check(not Setup.Heroes.validate(broken).is_empty(),"missing dependency rejected "+child)
	var intro=arena();var starting: Dictionary=intro.soldiers[0]
	starting.hp=0;intro.tick=5;intro.heroes.step(intro,starting)
	check(starting.hero_phase=="intro","source intro animation is uninterruptible")
	intro.tick=23;intro.heroes.step(intro,starting)
	check(starting.hero_phase=="death","death follows completed intro")
	scenarios+=2
func run() -> void:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/hero_malik_source.json"))
	stats(reference);attacks(reference);deaths(reference);fissures(reference);paths(reference);boundaries()
	var hashes := {}
	for path in ["scripts/battle/dove_heroes.gd","scripts/battle/dove_grid_path.gd","scripts/battle/level01_sim.gd","scripts/battle/dove_modifiers.gd","scripts/services/hero_combat.gd","scripts/services/battle_setup.gd","data/hero_malik_combat/definition.json","tests/fixtures/hero_malik_source.json","tests/verify_hero_malik.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	var report := {"passed":failures.is_empty(),"checks":checks,"behavior_scenarios":scenarios,"source_level_rows":10,"source_hashes":hashes,"failures":failures,"comparisons":comparisons,"browser_tested":false}
	preload("res://tests/report_writer.gd").json_file("res://reports/hero_combat_logic.json",report)
	print("HERO_COMBAT: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"behavior_scenarios":scenarios,"failures":failures}));quit(0 if failures.is_empty() else 1)
