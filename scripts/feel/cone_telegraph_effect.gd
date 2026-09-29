extends AreaTelegraphEffect
class_name ConeTelegraphEffect

# A warning cone on the ground for a telegraphed cone attack (a stare, a
# breath): fills from the caster over the windup, rim pulsing faster toward
# the hit. Faces context.direction. The cone's size is set on the scene
# (radius, arc_degrees) since windup cues don't carry it; context.radius /
# .arc_degrees override. Attach the cue to the actor so it follows.

@export var cone_radius: float = 300.0
@export var arc_degrees: float = 90.0


func setup_cue(context: Dictionary) -> void:
	super(context)
	radius = context.get("radius", cone_radius)
	arc_degrees = context.get("arc_degrees", arc_degrees)
	var direction: Vector2 = context.get("direction", Vector2.RIGHT)
	rotation = direction.angle()


func _draw() -> void:
	var k := get_progress()
	var half := deg_to_rad(arc_degrees) / 2.0
	_fan(radius, half, fill_color)
	var inner := fill_color
	inner.a = minf(fill_color.a * 2.5, 1.0)
	_fan(radius * k, half, inner)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * lerpf(pulse_start, pulse_end, k))
	var rim := color
	rim.a *= lerpf(0.55, 1.0, pulse)
	var width := rim_width * lerpf(1.0, 1.6, k)
	draw_arc(Vector2.ZERO, radius, -half, half, 32, rim, width, true)
	draw_line(Vector2.ZERO, Vector2.from_angle(-half) * radius, rim, width, true)
	draw_line(Vector2.ZERO, Vector2.from_angle(half) * radius, rim, width, true)


func _fan(r: float, half: float, c: Color) -> void:
	if r <= 1.0:
		return
	var points := PackedVector2Array([Vector2.ZERO])
	for i in 25:
		points.append(Vector2.from_angle(lerpf(-half, half, i / 24.0)) * r)
	draw_colored_polygon(points, c)
