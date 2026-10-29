extends RefCounted
## Dove uses initial_parabola_speed, gravity and either tangent alignment (arrow)
## or angular velocity (bomb). All values are in source world coordinates.
const BOMB_FPS := 144 # main_utils.default_params default, not animation FPS (30).

static func bomb_timing(flight: float, started: float, fps: int = BOMB_FPS) -> Dictionary:
	var steps := 0
	while started + float(steps) / fps < started + flight - 1.0 / fps: steps += 1
	return {"integration_fps":fps,"stop_elapsed":float(steps)/fps,"duration":ceili(float(steps)*30/fps)}

static func launch(from: Vector2, to: Vector2, seconds: float, bullet: Dictionary) -> Vector2:
	return (to - from - Vector2(0, 0.5 * float(bullet.get("g", 0)) * seconds * seconds)) / seconds

static func sample(projectile: Dictionary, bullet: Dictionary, elapsed: float) -> Dictionary:
	var seconds := clampf(elapsed, 0, float(projectile.duration) / 30.0)
	var velocity: Vector2 = projectile.velocity + Vector2(0, float(bullet.get("g", 0)) * seconds)
	var point: Vector2 = projectile.from + projectile.velocity * seconds + Vector2(0, 0.5 * float(bullet.get("g", 0)) * seconds * seconds)
	var angle := velocity.angle()
	if bullet.has("rotation_speed") and not bullet.get("align_with_trajectory", false):
		angle = projectile.initial_rotation + float(bullet.rotation_speed) * (-1 if projectile.to.x > projectile.from.x else 1) * seconds
	var radius := float(bullet.get("hide_radius", 0))
	return {"pos": point, "rotation": angle, "hidden": radius > 0 and (point.distance_to(projectile.from) < radius or point.distance_to(projectile.to) < radius)}

static func sample_bomb(projectile: Dictionary, bullet: Dictionary, elapsed: float) -> Dictionary:
	# Original bomb.update: integrate the previous velocity, then apply gravity.
	var dt := 1.0 / float(projectile.get("integration_fps",30))
	var seconds := minf(floorf(maxf(0,elapsed)/dt+0.00000001)*dt,float(projectile.get("stop_elapsed",float(projectile.duration)/30)))
	var point: Vector2 = projectile.from + projectile.velocity*seconds + Vector2(0,float(bullet.g)*seconds*(seconds-dt)*0.5)
	var velocity: Vector2 = projectile.velocity+Vector2(0,float(bullet.g)*maxf(0,seconds-dt))
	var angle := velocity.angle() if bullet.get("align_with_trajectory",false) else float(projectile.initial_rotation)+float(bullet.get("rotation_speed",0))*(-1 if projectile.to.x>projectile.from.x else 1)*seconds
	if seconds == 0: angle = float(projectile.initial_rotation)
	var radius := float(bullet.get("hide_radius",0))
	return {"pos":point,"rotation":angle,"hidden":radius>0 and (point.distance_to(projectile.from)<radius or point.distance_to(projectile.to)<radius)}
