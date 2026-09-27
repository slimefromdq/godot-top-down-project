extends Node2D

# A bubble popping: a quick ring snap and a few droplets flicking outward.
# A Mote fading away, a decoy grabbed. Cosmetic. Context: radius, color.

@export var lifetime: float = 0.35
@export var radius: float = 26.0
@export var color := Color(1.0, 0.95, 0.75)

var _t := 0.0
var _drops: Array[Vector2] = []


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	radius = context.get("radius", radius)
	color = context.get("color", color)
	for i in 7:
		_drops.append(Vector2.from_angle(randf() * TAU) * randf_range(0.7, 1.3))


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / lifetime, 0.0, 1.0)
	var fade := 1.0 - k
	draw_arc(Vector2.ZERO, radius * (1.0 + 0.6 * k), 0.0, TAU, 24, Color(color, fade), 3.0 * fade + 1.0)
	for d in _drops:
		draw_circle(d * radius * (1.0 + 1.8 * k), 3.0 * fade + 0.5, Color(color, fade))
