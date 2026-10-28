extends RefCounted
## Dove VictoryView, driven by the same elapsed time as its star sounds.
var view: Control
var paint: RefCounted
var particles: Array[Dictionary] = []
var particle_canvas: Control
var particle_transform := Transform2D.IDENTITY

class Sparks extends Control:
	var effect: RefCounted
	func _draw() -> void:
		if effect.view.sim.result == "victory": effect.draw_particles(self)

func _init(owner_view: Control, layout: RefCounted) -> void:
	view = owner_view; paint = layout

func start() -> void:
	reset()
	var random := RandomNumberGenerator.new(); random.seed = 1701
	for i in 150:
		var angle := random.randf_range(-PI / 2 - PI / 3, -PI / 2 + PI / 3)
		particles.append({"velocity": Vector2.from_angle(angle) * random.randf_range(400, 1000), "life": random.randf_range(0, 1.5)})
	if particle_canvas == null:
		particle_canvas = Sparks.new(); particle_canvas.effect = self
		particle_canvas.name = "VictorySparks"; particle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var blend := CanvasItemMaterial.new(); blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particle_canvas.material = blend; view.add_child(particle_canvas)
	particle_canvas.show()

func reset() -> void:
	particles.clear()
	if is_instance_valid(particle_canvas): particle_canvas.hide()

func badge() -> String:
	return "victoryBadges_notxt_%04d" % {1:2, 2:3, 3:1}[int(view.outcome.get("mode", 1))]

func stars_end() -> int:
	return [19,38,54][clampi(int(view.outcome.get("stars", 1)), 1, 3) - 1]

func buttons_ready_at() -> float:
	return view.VICTORY_STAR_DELAY + stars_end() / 30.0 + 1.0

func _back(value: float, overshoot: float = 1.70158) -> float:
	var t := clampf(value, 0, 1) - 1
	return 1 + (overshoot + 1) * t * t * t + overshoot * t * t

func draw() -> void:
	var elapsed: float = maxf(0, view.victory_elapsed)
	var dimensions: Vector2 = paint.image_size(badge())
	var total_height: float = 415 + paint.image_size("button_restart_chains").y + 1.125 * paint.image_size("button_border_0001").y
	var fit := minf(1, minf((view.view_width - 64) / dimensions.x, 650 / total_height))
	var center := Vector2(view.view_width / 2, 256)
	paint.push(center, fit * lerpf(0.6, 1, _back(elapsed / 0.6, 1.5)))
	paint.push(-dimensions / 2)
	particle_transform = paint.transform
	var chain_at: float = view.VICTORY_STAR_DELAY + stars_end() / 30.0
	_chain("button_restart_chains", "button_border_0001", "重新开始", "restart", dimensions.x, 415, elapsed - chain_at - 0.5, elapsed >= buttons_ready_at(), 19)
	_chain("button_continue_chains", "button_border_large_0001", "继续", "map", dimensions.x, 300, elapsed - chain_at, elapsed >= buttons_ready_at(), 24)
	paint.image(badge())
	paint.ellipse_label("胜利", Vector2(dimensions.x / 2, 235), Vector2(320,-30), 78, Color("4c3817"), "h_noti", PI / 6)
	var star_time: float = elapsed - view.VICTORY_STAR_DELAY
	if star_time >= 0:
		paint.image("victoryStars_%04d" % mini(stars_end(), 1 + int(star_time * 30)), Vector2(dimensions.x / 2, 270 if int(view.outcome.get("mode",1)) == 3 else 230), Vector2(0.5,0))
	paint.pop(); paint.pop()
	if view.sim.developer_used: paint.label("调试局", Rect2(12,70,100,24), 14, Color("ffe9b0"))
	if is_instance_valid(particle_canvas): particle_canvas.queue_redraw()

func _chain(chain: String, button: String, caption: String, action: String, width: float, y: float, elapsed: float, enabled: bool, font_size: int) -> void:
	if elapsed < 0: return
	var chain_size: Vector2 = paint.image_size(chain)
	var button_size: Vector2 = paint.image_size(button)
	var anchor_y: float = chain_size.y + 0.9 * button_size.y
	var chain_y: float = anchor_y * _back(elapsed / 0.5) - anchor_y
	paint.push(Vector2(0,y))
	var clip := Rect2(0,0,width,768)
	paint.image_clip(chain, Vector2(width / 2 - chain_size.x / 2, chain_y), clip)
	var at := Vector2((width - button_size.x) / 2, chain_y + chain_size.y + 0.125 * button_size.y)
	var over: bool = view.hovered == action + str({}) and enabled
	paint.image_clip(button.replace("_0001", "_0002") if over else button, at, clip)
	if at.y >= 0:
		paint.label(caption, Rect2(at,button_size), font_size, Color("fffec8"), "center", "middle", 1, 1, "button:"+action, "button")
		if enabled: paint.hit(Rect2(at,button_size), action)
	paint.pop()

func draw_particles(canvas: Control) -> void:
	var age: float = view.victory_elapsed - 0.15
	if age < 0: return
	var frame: Dictionary = view._frame("victory_star")
	var dimensions: Vector2 = paint.image_size(badge())
	var factor: float = frame.ref_scale * view.ART_SCALE
	for particle: Dictionary in particles:
		if age >= particle.life or particle.life <= 0: continue
		var origin := Vector2(dimensions.x / 2, dimensions.y / 3)
		var position: Vector2 = origin + particle.velocity * age + Vector2(0,1000) * age * age - particle.velocity.normalized() * 100 * age * age
		var growth: float = lerpf(1,1.4,age / particle.life)
		canvas.draw_set_transform_matrix(Transform2D(0,Vector2.ONE * view.zoom,0,Vector2.ZERO) * particle_transform * Transform2D(0,Vector2.ONE * growth,0,position))
		canvas.draw_texture_rect(frame.texture, Rect2((frame.trim - frame.original_size / 2) * factor, frame.logical_size * factor), false, Color(1,1,1,1 - age / particle.life))
