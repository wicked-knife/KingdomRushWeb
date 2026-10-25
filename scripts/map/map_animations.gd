extends RefCounted
## Source map animation scheduling, independent of rendering, input, and campaign state.
var entries: Array = []
var time := 0.0
var rng := RandomNumberGenerator.new()

func _init(definitions: Array, seed_value: int = 0) -> void:
	if seed_value == 0: rng.randomize()
	else: rng.seed = seed_value
	for source: Dictionary in definitions:
		var entry := {"data": source, "start": 0.0, "next": 0.0, "sequence": 0, "offset": 0.0}
		if source.has("sequence"):
			entry.next = _duration(source.animations[source.sequence[0][0]]) + _wait(source.sequence[0].slice(1))
		elif source.has("move"):
			entry.offset = rng.randf() * float(source.move.time) if source.get("random_start", false) else 0.0
			entry.start = -float(entry.offset) if source.get("random_start", false) else _wait(source.get("wait", [0, 0]))
			entry.next = float(entry.start) + float(source.move.time)
		elif source.get("loop", false) and source.has("animation"):
			entry.offset = rng.randf() * _duration(source.animation)
		elif source.has("wait"):
			entry.start = -_duration(source.animation); entry.next = _wait(source.wait)
		entries.append(entry)

func _wait(bounds: Array) -> float: return rng.randf_range(float(bounds[0]), float(bounds[1]))
func _duration(a: Dictionary) -> float: return (int(a.to) - int(a.from) + 1) / 30.0
func _frame(a: Dictionary, elapsed: float, looping: bool = true) -> String:
	var count := int(a.to) - int(a.from) + 1
	var index := maxi(0, int(elapsed * 30))
	return "%s_%04d" % [a.prefix, int(a.from) + (index % count if looping else mini(index, count - 1))]
static func vec(value: Dictionary) -> Vector2: return Vector2(value.x, value.y)

func advance(delta: float) -> void:
	time += delta
	for entry: Dictionary in entries:
		var d: Dictionary = entry.data
		if d.has("sequence"):
			while time >= entry.next:
				entry.start = entry.next; entry.sequence = (int(entry.sequence) + 1) % d.sequence.size()
				var sequence: Array = d.sequence[entry.sequence]
				entry.next += _duration(d.animations[sequence[0]]) + _wait(sequence.slice(1))
		elif d.has("move"):
			while time >= entry.next:
				entry.start = float(entry.next) + _wait(d.get("wait", [0, 0]))
				entry.next = float(entry.start) + float(d.move.time)
		elif d.has("wait"):
			while time >= entry.next:
				entry.start = entry.next
				entry.next += _duration(d.animation) + _wait(d.wait)

func items(layer: int) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		var d: Dictionary = entry.data
		if int(d.layer) != layer: continue
		if str(d.get("id", "")) == "ma_big_boat":
			out.append_array(_boat(d)); continue
		var elapsed: float = time - float(entry.start) + float(entry.offset)
		var pos := vec(d.get("pos", {"x": 0, "y": 0}))
		var animation: Dictionary = d.get("animation", {})
		if d.has("sequence"): animation = d.animations[d.sequence[entry.sequence][0]]
		if d.has("move"):
			if time < float(entry.start): continue
			var fraction := (time - float(entry.start)) / float(d.move.time)
			pos = vec(d.move.from).lerp(vec(d.move.to), fraction)
		out.append({"image": _frame(animation, elapsed, bool(d.get("loop", false)) and not d.has("sequence")), "pos": pos,
			"scale": vec(d.get("scale", {"x": 1, "y": 1})), "alpha": float(d.get("alpha", 1)), "anchor": d.get("anchor", {})})
	return out

func _boat(d: Dictionary) -> Array:
	var arrive := float(d.wait_out)
	var idle := arrive + float(d.sail_time) * 0.8
	var fade := idle + float(d.wait_in)
	var leave := fade + float(d.wait_in)
	var phase := fmod(time, leave + float(d.sail_time))
	var pos := vec(d.pos_out)
	if phase >= arrive and phase < leave:
		var t := clampf((phase - arrive) / float(d.sail_time), 0, 1)
		pos = vec(d.pos_out).lerp(vec(d.pos_in), 1 - (1 - t) * (1 - t))
	elif phase >= leave:
		var t := (phase - leave) / float(d.sail_time)
		pos = vec(d.pos_in).lerp(vec(d.pos_out), t * t)
	var blend := clampf(phase - fade, 0, 1) if phase < leave else 1.0
	if phase < arrive: blend = 1.0
	elif phase < fade: blend = 0.0
	var incoming: Dictionary = d.animations.in_sail if phase < idle else d.animations.in_idle
	var outgoing: Dictionary = d.animations.out_sail if phase < arrive or phase >= leave else d.animations.out_idle
	return [
		{"image": _frame(outgoing, phase - leave if phase >= leave else time), "pos": pos + Vector2(0, -8), "scale": Vector2.ONE, "alpha": blend, "anchor": {"x": 0, "y": 0}},
		{"image": _frame(incoming, time), "pos": pos, "scale": Vector2.ONE, "alpha": 1 - blend, "anchor": {"x": 0, "y": 0}}
	]
