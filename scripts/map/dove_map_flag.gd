extends RefCounted
## Dove LevelFlagView: only hover uses 180/181; normal animations stop at 64/134.
var completed := false
var hovered := false
var elapsed := 1000000000.0
var wait := 0.0
var rng := RandomNumberGenerator.new()

func _init(has_stars: bool = false, seed_value: int = -1) -> void:
	completed = has_stars
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	wait = rng.randf_range(3, 10)

func set_hovered(value: bool) -> void:
	if hovered == value: return
	hovered = value
	if not hovered:
		elapsed = 0
		wait = rng.randf_range(3, 10)

func advance(delta: float) -> void:
	if hovered: return
	elapsed += delta
	wait -= delta
	if wait < 0:
		wait = rng.randf_range(3, 10.1)
		elapsed = 0

func frame() -> String:
	if hovered: return "map_flag_0181" if completed else "map_flag_0180"
	var first := 90 if completed else 24
	var last := 134 if completed else 64
	return "map_flag_%04d" % mini(last, first + int(elapsed * 30))
