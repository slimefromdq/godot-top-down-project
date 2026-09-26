extends Node2D

# Where a Starfall meteor will land: a shadow that darkens and tightens over
# the impact delay (context.duration), then the meteor streaks in.

@export var radius: float = 120.0
var _duration: float = 0.35
var _t: float = 0.0

func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	_duration = maxf(context.get("duration", _duration), 0.05)
	radius = context.get("radius", radius)
	z_index = -3

func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration + 0.05:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var p := clampf(_t / _duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * lerpf(0.4, 1.0, p), Color(0.05, 0.05, 0.15, 0.15 + 0.3 * p))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.7, 0.8, 1.0, 0.6 * p), 2.0)
	# The meteor, falling in from above-left.
	var fall := Vector2(-160, -320) * (1.0 - p)
	draw_line(fall + Vector2(-30, -60), fall, Color(0.8, 0.9, 1.0, 0.5 * p), 6.0)
	draw_circle(fall, 10.0, Color(0.9, 0.95, 1.0, p))
