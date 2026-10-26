extends RefCounted
## Dove WaveFlag / IncomingTooltip, positioned at source entrance markers.
var view: Control
var paint: RefCounted
var active: Array = []
var fading: Array = []
var shown_wave := -1
var tooltip := {}
var tooltip_alpha := 0.0
var time := 0.0

func _init(battle: Control, layout: RefCounted) -> void:
	view = battle; paint = layout

func reset() -> void:
	active.clear(); fading.clear(); shown_wave = -1; tooltip = {}; tooltip_alpha = 0

func advance(delta: float) -> void:
	time += delta
	var hovered := hovered_flag()
	if not hovered.is_empty(): tooltip = hovered
	tooltip_alpha = move_toward(tooltip_alpha, 1.0 if not hovered.is_empty() else 0.0, delta * 4)
	if tooltip_alpha <= 0: tooltip = {}

func enabled() -> bool:
	return view.selected == "" and view.targeting == "" and view.sim.notices.is_empty() and not view.sim.paused and view.sim.result == "" and not view.developer.opened

func sync() -> void:
	var sim: RefCounted = view.sim
	if shown_wave >= 0 and (not sim.can_send_wave() or sim.wave != shown_wave or sim.result != ""):
		for flag: Dictionary in active: flag.hidden_at = time; fading.append(flag)
		active.clear(); shown_wave = -1
	if sim.can_send_wave() and sim.result == "" and shown_wave != sim.wave:
		shown_wave = sim.wave
		var group: Dictionary = sim.data.waves.groups[sim.wave]
		var seen := {}
		for wave: Dictionary in group.waves:
			var path := int(wave.path_index)
			if seen.has(path): continue
			seen[path] = true
			for entrance: Dictionary in sim.data.locations.entrances:
				if int(entrance.path_index) != path: continue
				var report := incoming(group, path)
				if not report.is_empty(): active.append({"path":path, "entrance":entrance, "report":report, "born":time, "group":sim.wave + 1, "some_flying":wave.get("some_flying", false)})
	fading = fading.filter(func(flag): return time - flag.hidden_at < 0.5)

func incoming(group: Dictionary, path: int) -> Array:
	var counts := {}
	for wave: Dictionary in group.waves:
		if int(wave.path_index) != path: continue
		for spawn: Dictionary in wave.spawns:
			for i in range(int(spawn.max)):
				var type: String = spawn.creep
				if spawn.get("max_same", 0) > 0 and spawn.has("creep_aux") and (i / int(spawn.max_same)) % 2 == 1: type = spawn.creep_aux
				counts[type] = int(counts.get(type, 0)) + 1
	var report: Array = []
	for type: String in counts:
		var template: Dictionary = view.sim.templates[type]
		var key: String = template.info.get("i18n_key", type.to_upper()) + "_NAME"
		report.append({"type":type, "name":view.interface.text(key), "count":counts[type]})
	return report

func position(flag: Dictionary) -> Vector2:
	var point: Vector2 = view.world(view.Simulation.vec(flag.entrance.pos))
	return Vector2(clampf(point.x, 60, view.view_width - 60), clampf(point.y, 60, 708))

func scale_for(flag: Dictionary) -> float:
	if flag.has("hidden_at"): return 1.0 + 0.5 * (1 - pow(1 - clampf((time - flag.hidden_at) / 0.5, 0, 1), 2))
	return 0.85 + 0.15 * (0.5 * sin(TAU * (time - flag.born) * 1.25) + 1)

func hovered_flag() -> Dictionary:
	if not enabled(): return {}
	for flag: Dictionary in active:
		if view.hovered == "wave" + str({"path":flag.path}): return flag
	return {}

func draw() -> void:
	sync()
	for flag: Dictionary in fading + active:
		var hidden: bool = flag.has("hidden_at")
		var alpha := pow(1 - clampf((time - flag.hidden_at) / 0.5, 0, 1), 2) if hidden else (1.0 if enabled() else 0.2)
		paint.push(position(flag), scale_for(flag), alpha)
		var over: bool = not hidden and enabled() and view.hovered == "wave" + str({"path":flag.path})
		if over: paint.image("nextwaveTimer_glow_0001", Vector2.ZERO, Vector2(0.5, 0.5))
		var fill := 1.0
		if int(flag.group) > 1:
			var duration: float = view.sim.data.waves.groups[int(flag.group) - 1].interval
			fill = clampf(1 - (view.sim.next_wave_tick - view.sim.tick) / duration, 0, 1) if duration > 0 else 1.0
		paint.image_sector("nextwaveTimer_Full", Vector2.ZERO, fill)
		paint.image("nextwaveTimer_0001", Vector2.ZERO, Vector2(0.5, 0.5))
		paint.image("nextwaveTimer_0003" if flag.some_flying else "nextwaveTimer_0002", Vector2.ZERO, Vector2(0.5, 0.5))
		paint.push(Vector2.ZERO, 1, 1, PI / 2 - float(flag.entrance.r))
		paint.image("nextwaveTimer_0020", Vector2.ZERO, Vector2(0.5, 1))
		paint.pop()
		if not hidden and enabled():
			var dimensions: Vector2 = paint.image_size("nextwaveTimer_glow_0001")
			paint.hit(Rect2(-dimensions * 0.25, dimensions * 0.5), "wave", {"path":flag.path})
		paint.pop()

func draw_path() -> void:
	var flag := hovered_flag()
	if flag.is_empty(): return
	# Dove draws moving dashes: length 25, gap 15, speed 60 world units/sec.
	paint._apply()
	var route: Array = view.sim.data.paths.paths[int(flag.path) - 1][0]
	var travelled := 0.0
	for i in range(1, route.size()):
		var start := view.Simulation.vec(route[i - 1]) as Vector2
		var finish := view.Simulation.vec(route[i]) as Vector2
		var length := start.distance_to(finish)
		var cursor := 0.0
		while cursor < length:
			var phase := fposmod(travelled + cursor - time * 60, 40)
			var span := minf(length - cursor, (25 if phase < 25 else 40) - phase)
			if phase < 25 and span > 0.0001:
				view.draw_line(view.world(start.lerp(finish, cursor / length)), view.world(start.lerp(finish, (cursor + span) / length)), Color(1, 1, 1, 0.5), 4, true)
			cursor += maxf(span, 0.0001)
		travelled += length

func draw_tooltip() -> void:
	if tooltip.is_empty() or tooltip_alpha <= 0 or not enabled(): return
	var point := position(tooltip)
	var width := 200.0
	var height: float = 50 + 19 * tooltip.report.size()
	var left := point.x > 1.5 * width
	var above := point.y >= 3 * height
	var at := point + Vector2(-width - 24 if left else 24, -height - 27 if above else 27)
	at.x = clampf(at.x, 8, view.view_width - width - 8); at.y = clampf(at.y, 8, 700 - height)
	paint.push(at, 1, tooltip_alpha)
	paint._apply()
	var background := Color(21.0 / 255, 17.0 / 255, 13.0 / 255, 220.0 / 255 * tooltip_alpha)
	view.draw_rect(Rect2(0, 0, width, height), background)
	var arrow := Vector2(width if left else 0, height if above else 0)
	var dx := 1.0 if left else -1.0
	var dy := 1.0 if above else -1.0
	view.draw_colored_polygon(PackedVector2Array([arrow, arrow + Vector2(dx * 18, dy * 24), arrow + Vector2(0, dy * 12)]), background)
	paint.label("一波敌人即将到来", Rect2(8, 10, width - 16, 25), 16, Color("ff7337"), "center", "middle", 1, 0, "incoming:title", "body_bold")
	for i in range(tooltip.report.size()):
		var row: Dictionary = tooltip.report[i]
		paint.label("%s × %d" % [row.name, row.count], Rect2(8, 36 + i * 19, width - 16, 19), 13, Color("fff5d2"), "center", "middle", 1, 0, "incoming:" + row.type)
	paint.pop()
