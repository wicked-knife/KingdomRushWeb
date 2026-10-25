extends RefCounted
## Shared source-sprite sampling. State owners decide when to start/repeat an
## animation; rendering never guesses looping from an entity/template name.

static func key(sprite: Dictionary, state: String = "", prefix: String = "") -> String:
	var name: String = state if state != "" else str(sprite.get("name", "idle"))
	var stem: String = prefix if prefix != "" else str(sprite.get("prefix", ""))
	return stem + "_" + name if stem != "" else name

static func duration(animations: Dictionary, name: String) -> int:
	return animations[name].frames.size() if animations.has(name) else 1

static func frame(sprite: Dictionary, animations: Dictionary, playback: Dictionary = {}) -> String:
	var name := key(sprite, playback.get("state", ""), playback.get("prefix", ""))
	if not animations.has(name): name = key(sprite)
	if not animations.has(name): return str(sprite.get("name", "")).replace("%04i", "0001")
	var animation: Dictionary = animations[name]
	var elapsed := maxi(0, int(playback.get("elapsed", 0)))
	var looping: bool = playback.get("loop", sprite.get("loop", true))
	var index: int = elapsed % animation.frames.size() if looping else mini(elapsed, animation.frames.size() - 1)
	return "%s_%04d" % [animation.prefix, int(animation.frames[index])]

static func vector_track(keys: Array, seconds: float) -> Vector2:
	for i in range(1, keys.size()):
		if seconds <= float(keys[i][0]):
			var fraction := clampf((seconds - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0])), 0, 1)
			return Vector2(keys[i - 1][1].x, keys[i - 1][1].y).lerp(Vector2(keys[i][1].x, keys[i][1].y), fraction)
	return Vector2(keys[-1][1].x, keys[-1][1].y)

static func scalar_track(keys: Array, seconds: float) -> float:
	for i in range(1, keys.size()):
		if seconds <= float(keys[i][0]):
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), clampf((seconds - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0])), 0, 1))
	return float(keys[-1][1])
