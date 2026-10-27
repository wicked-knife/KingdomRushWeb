extends SceneTree
## Generate a reproducible legal strategy. Only accepted public commands are recorded.
const Sim = preload("res://scripts/battle/level01_sim.gd")
const Levels = preload("res://scripts/services/campaign_levels.gd")
var actions: Array = []
func _init() -> void: call_deferred("run")
func send(s,kind: String,args: Dictionary = {}) -> bool:
	if not s.command(kind,args): return false
	var stored := args.duplicate(true)
	if stored.has("pos"): stored.pos = {"x":stored.pos.x,"y":stored.pos.y}
	actions.append({"tick":s.tick,"kind":kind,"args":stored}); return true
func target_tower(s,id: String,wanted: String) -> bool:
	var t: Dictionary = s.tower_by_id(id)
	if t.template == wanted: return true
	if wanted != "tower_ranger" and t.type != "" and int(s.tower_template(t).tower.level) >= int(s.templates[wanted].tower.level): return true
	if t.ready > s.tick: return false
	if t.type == "": send(s,"build",{"id":id,"type":"archer" if wanted == "tower_ranger" else wanted.trim_prefix("tower_").split("_")[0]}); return false
	var next: String = s.upgrade_target(t)
	if next != "": send(s,"upgrade",{"id":id,"upgrade_to":next})
	return t.template == wanted
func plan(s) -> void:
	if not s.notices.is_empty():
		while not s.notices.is_empty(): send(s,"confirm")
	var sequence := [["6","tower_barrack_2"],["4","tower_ranger"],["5","hire_2"],["5","bleed_1"],["12","tower_ranger"],["6","tower_barrack_3"],["4","thorn_3"],["5","hire_4"]]
	for item: Array in sequence:
		if str(item[1]).begins_with("hire_"):
			if s.tower_by_id("5").template == "tower_elf_holder":
				send(s,"upgrade",{"id":"5","upgrade_to":"tower_elf"}); break
			if int(s.tower_by_id("5").hired) < int(str(item[1]).trim_prefix("hire_")):
				send(s,"buy_soldier",{"id":"5","type":"soldier_elf"}); break
		elif not str(item[1]).begins_with("tower_"):
			var skill: String = str(item[1]).split("_")[0]
			if int(s.tower_by_id(item[0]).powers[skill]) < int(str(item[1]).split("_")[1]):
				send(s,"upgrade_power",{"id":item[0],"power":skill}); break
		elif not target_tower(s,item[0],item[1]): break
	if s.tower_by_id("6").type == "barrack" and s.tower_by_id("6").rally.distance_to(s.resolve_rally_point(s.tower_by_id("6"),Vector2(650,590))) > 0.1: send(s,"rally",{"id":"6","pos":Vector2(650,590)})
	if s.tower_by_id("5").template == "tower_elf" and s.tower_by_id("5").rally.distance_to(s.resolve_rally_point(s.tower_by_id("5"),Vector2(450,565))) > 0.1: send(s,"rally",{"id":"5","pos":Vector2(450,565)})
	if s.tower_by_id("4").template == "tower_ranger" and s.wave >= 9:
		var t: Dictionary = s.tower_by_id("4")
		for power in ["poison","thorn"]:
			if int(t.powers[power]) < 1: send(s,"upgrade_power",{"id":"4","power":power})
	if s.wave == 0 or (s.can_send_wave() and s.enemies.filter(func(e): return e.hp > 0).size() <= 1): send(s,"wave")
	if s.cooldowns.fire == 0 and not s.enemies.is_empty():
		var best := {}; var score := 0.0
		for e: Dictionary in s.enemies:
			if e.hp <= 0 or not s.valid_power_point("fire",e.pos): continue
			var value := 0.0
			for other: Dictionary in s.enemies:
				if other.hp > 0 and s.distance(e.pos,other.pos) < 65: value += minf(100,other.hp)
			if value > score: score = value; best = e
		if score >= 190: send(s,"cast",{"power":"fire","pos":best.pos})
	if s.cooldowns.reinforcements == 0:
		var best := {}; var left := INF
		for e: Dictionary in s.enemies:
			var remain: float = s.data.paths.paths[e.path][e.subpath].size() - e.progress
			if e.hp > 0 and remain < left and s.valid_ground(e.pos): best = e; left = remain
		if not best.is_empty(): send(s,"cast",{"power":"reinforcements","pos":best.pos})
func run() -> void:
	var s = Sim.new(Levels.load_definition(5),42)
	for i in range(50000):
		if i % 5 == 0: plan(s)
		s.step()
		if s.result != "": break
	print("LEVEL05_STRATEGY: ",s.result," lives=",s.lives," gold=",s.gold," ticks=",s.tick," actions=",actions.size())
	if s.result == "victory":
		var f := FileAccess.open("res://tests/replays/level05_victory.json",FileAccess.WRITE)
		f.store_string(JSON.stringify({"seed":42,"level_id":5,"actions":actions,"outcome":{"lives":s.lives,"tick":s.tick,"gold":s.gold,"spawned":s.spawn_log.size()}},"\t")); f.close()
		quit(0); return
	quit(1)
