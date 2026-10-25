extends SceneTree
## Decode the clips which used to lock the editor's audio waveform generator.

func _init() -> void:
	var failures: Array[String] = []
	for filename: String in ["kr6_sfx_ambiance_terrain3_var3_v1.ogg", "Sound_MapRoad.ogg"]:
		var path := "res://assets/kingdom_rush/kr1-desktop/sounds/files/" + filename
		var stream := load(path) as AudioStreamOggVorbis
		if stream == null or stream.get_length() <= 0.0:
			failures.append("Missing or empty audio: " + filename)
			continue
		var playback := stream.instantiate_playback()
		playback.start()
		var samples := playback.mix_audio(1.0, 128)
		if samples.size() != 128:
			failures.append("Decoder did not return samples: " + filename)
		for sample: Vector2 in samples:
			if sample.length() > 0.000001:
				failures.append("Placeholder must remain silent: " + filename)
				break
		playback.stop()
	print("AUDIO_COMPAT_VERIFICATION: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
