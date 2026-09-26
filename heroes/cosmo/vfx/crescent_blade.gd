extends Node2D

# The Crescent's look: a pale blade curving forward, spinning.

@export var radius: float = 34.0
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _t * 14.0)
	draw_arc(Vector2.ZERO, radius, -1.2, 1.2, 20, Color(0.85, 0.92, 1.0, 0.95), 9.0, true)
	draw_arc(Vector2(-6, 0), radius, -1.0, 1.0, 20, Color(0.6, 0.75, 1.0, 0.4), 14.0, true)
	draw_set_transform(Vector2.ZERO)
