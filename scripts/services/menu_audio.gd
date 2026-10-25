extends Node

var music_player: AudioStreamPlayer
var click_player: AudioStreamPlayer
var unlocked := false
var configured := false


func _ready() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	click_player = AudioStreamPlayer.new()
	click_player.bus = "SFX"
	add_child(click_player)


func configure(music: AudioStream, click: AudioStream, settings: Node) -> void:
	music_player.stop()
	music_player.stream = music
	if music is AudioStreamOggVorbis:
		music.loop = true
	click_player.stream = click
	if not settings.changed.is_connected(set_volumes):
		settings.changed.connect(set_volumes)
	set_volumes(settings.music_volume, settings.sfx_volume)
	configured = true
	if not OS.has_feature("web") or unlocked:
		unlock()


func unlock() -> void:
	unlocked = true
	if configured and not music_player.playing and DisplayServer.get_name() != "headless":
		music_player.play()


func play_click() -> void:
	unlock()
	if configured and DisplayServer.get_name() != "headless":
		click_player.play()


func set_volumes(music: float, sfx: float) -> void:
	for pair: Array in [["Music", music], ["SFX", sfx]]:
		var index := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_linear(index, pair[1])


func _exit_tree() -> void:
	music_player.stop()
	click_player.stop()
	music_player.stream = null
	click_player.stream = null
