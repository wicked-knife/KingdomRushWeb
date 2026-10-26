extends Node

var music_player: AudioStreamPlayer
var click_player: AudioStreamPlayer
var unlocked := false
var configured := false
var music_revision := 0


func _ready() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	music_player = AudioStreamPlayer.new()
	music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	music_player.bus = "Music"
	add_child(music_player)
	click_player = AudioStreamPlayer.new()
	click_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	click_player.bus = "SFX"
	add_child(click_player)


func configure(music: AudioStream, click: AudioStream, settings: Node) -> void:
	configured = true
	click_player.stream = click
	if not settings.changed.is_connected(set_volumes):
		settings.changed.connect(set_volumes)
	set_volumes(settings.music_volume, settings.sfx_volume)
	play_music(music)


func play_music(stream: AudioStream, gain: float = 1.0) -> void:
	music_revision += 1
	music_player.stop()
	music_player.stream = stream
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	music_player.volume_db = linear_to_db(gain)
	if configured and (not OS.has_feature("web") or unlocked) and DisplayServer.get_name() != "headless":
		music_player.play()


func stop_music() -> void:
	music_revision += 1
	music_player.stop()
	music_player.stream = null


func unlock() -> void:
	var first_unlock := not unlocked
	unlocked = true
	if configured and music_player.stream != null and not music_player.playing and DisplayServer.get_name() != "headless":
		music_player.play()
	# Godot resumes the Web Audio context asynchronously after the first gesture.
	# Replay on the following frames so a stream started during that gesture is
	# attached after the context is live. Scene changes use play_music normally.
	if first_unlock and OS.has_feature("web"):
		_retry_web_music.call_deferred(music_revision)


func _retry_web_music(revision: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != music_revision or not unlocked or music_player.stream == null:
		return
	music_player.stop()
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
	stop_music()
	click_player.stop()
	click_player.stream = null
