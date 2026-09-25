extends Node2D

# Placeholder look for the thrown Coin: a gold disc flipping end over end.

@export var radius: float = 12.0
@export var color: Color = Color(1.0, 0.82, 0.25, 1.0)
@export var flips_per_second: float = 6.0

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var squash := maxf(absf(cos(_t * TAU * flips_per_second * 0.5)), 0.12)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(squash, 1.0))
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, color.darkened(0.4), 2.0)
	draw_set_transform(Vector2.ZERO)
