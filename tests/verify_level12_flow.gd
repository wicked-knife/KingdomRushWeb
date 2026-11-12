extends "res://tests/verify_level06.gd"
const Slots=preload("res://scripts/services/save_slots.gd")
const Fixture12=preload("res://tests/slot_fixture.gd")
const Ending=preload("res://scripts/ui/kr1_ending.gd")

func outcome12(mode:int,result:String="victory") -> Dictionary:
	return {"generation":1,"level_id":12,"mode":mode,"difficulty":2,"result":result,"lives":20 if mode==1 else 1,"next_item_name":"kr1_end"}

func run() -> void:
	var directory:="res://output/level12_flow_%d"%Time.get_ticks_usec()
	var slots=Slots.new();slots.initialize(directory)
	var progress=slots.select_slot(1)
	for id in range(1,12):Fixture12.complete(progress,{"generation":1,"level_id":id,"mode":1,"difficulty":2,"result":"victory","lives":20})
	progress.record_result(outcome12(1))
	check(progress.data.has("last_victory") and not progress.record(12).has(1),"finished saves pending before map")
	var stored:String=FileAccess.get_file_as_string(progress.path)
	check(not stored.contains("next_item_name") and not stored.contains("kr1_end") and not stored.contains("ending_seen"),"presentation route and playback position absent from save")
	var reloaded=Progress.new();reloaded.initialize(progress.path)
	check(reloaded.data.has("last_victory") and not reloaded.record(12).has(1),"closing during ending retains pending result")
	var settled:Dictionary=reloaded.enter_map()
	check(reloaded.record(12).get("stars",0)==3 and reloaded.record(12).has(1) and not reloaded.data.has("last_victory"),"reload existing two-stage settlement")
	check(not settled.unlocked.is_empty() and not reloaded.is_playable(13),"source unlocks bonus previews without unsupported gameplay")
	for mode in [2,3]:Fixture12.complete(reloaded,outcome12(mode))
	check(reloaded.record(12).has(2) and reloaded.record(12).has(3),"both challenge results settle")
	var before:Dictionary=reloaded.data.duplicate(true)
	reloaded.record_result(outcome12(3,"defeat"));reloaded.enter_map()
	check(reloaded.record(12)==before.levels[12],"defeat preserves challenge best")
	reloaded.record_result(outcome12(1));check(reloaded.data.has("last_victory"),"repeated campaign victory stays eligible for ending")
	for id in [2,3]:check(slots.select_slot(id).record(12).is_empty(),"save slot isolation %d"%id)
	var definition:=Levels.read_json("res://data/kr1_end/definition.json")
	check(definition.comics.size()==2 and not definition.has("credits"),"only two comics, no credits data")
	for comic:Array in definition.comics:
		for page:Dictionary in comic:
			check(not page.order.is_empty() and page.order.size()==page.sprites.size(),"all source comic layers have drawing order")
			for sprite:Dictionary in page.sprites.values():
				var value:Array=Ending.sample(sprite.keys,page.end_frame)
				check(value[4]>0,"comic last frame retains visible sprite")
	var keys:Array=[[0,0,0,1,1,0,0],[30,100,50,2,2,1,1]]
	check(Ending.sample(keys,30)==[100.0,50.0,2.0,2.0,1.0],"source final keyframe exact")
	check(Ending.sample(keys,15)[0]>50,"source out-expo interpolation")
	var hashes:Dictionary={}
	for path:String in ["tests/verify_level12_flow.gd","scripts/services/campaign_progress.gd","scripts/services/save_slots.gd","scripts/app_root.gd","scripts/ui/kr1_ending.gd","data/kr1_end/definition.json"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	preload("res://tests/report_writer.gd").json_file("res://reports/level12_flow.json",{"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_hashes":hashes})
	print("LEVEL12_FLOW: ",JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
