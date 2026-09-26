extends Node2D

# A launched moon (Moonshot's projectile look), with a soft trail.

@export var radius: float = 11.0

func _draw() -> void:
	for i in 4:
		draw_circle(Vector2(-10.0 * (i + 1), 0), radius * (0.8 - i * 0.15), Color(0.7, 0.8, 1.0, 0.25 - i * 0.05))
	draw_circle(Vector2.ZERO, radius + 5.0, Color(0.6, 0.75, 1.0, 0.35))
	draw_circle(Vector2.ZERO, radius, Color(0.9, 0.93, 1.0))
