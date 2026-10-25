extends RefCounted
## Dove uses initial_parabola_speed, gravity and either tangent alignment (arrow)
## or angular velocity (bomb). All values are in source world coordinates.

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
