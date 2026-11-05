extends SceneTree
func _init() -> void:
	var feeds:Dictionary={}
	var offsets:Array=[[2,0,0],[3,0,0],[1,3,8],[2,3,8],[3,3,8]]
	for scenario:String in ["normal","blocked","silenced","silenced_cast","stun_windup","stun_boundary","stun_delay","dead_cast","dead_after","invalid_node","cap"]:
		var random:=RandomNumberGenerator.new();random.seed=42
		var values:Array=[]
		for i in 1000:
			var slot:int=(i-1)%5 if scenario=="stun_delay" and i>0 else i%5
			var offset:Array=offsets[slot]
			values.append(random.randf());values.append(random.randi_range(offset[1],offset[2]));values.append(random.randf())
		feeds[scenario]=values
	var file:=FileAccess.open("res://output/level11_random_input.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(feeds));file.close();quit()
