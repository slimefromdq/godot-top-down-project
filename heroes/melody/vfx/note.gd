extends Node2D

# Placeholder look for a Heavy Note: a fat eighth note with a wobble.

@export var size: float = 1.0
@export var color: Color = Color(0.95, 0.75, 1.0)

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# The projectile rotates this node to its flight; keep the note upright.
	draw_set_transform(Vector2.ZERO, -global_rotation + sin(_t * 9.0) * 0.2, Vector2(size, size))
	draw_circle(Vector2(-6, 8), 11.0, color)
	draw_line(Vector2(4, 8), Vector2(4, -22), color, 4.0)
	draw_line(Vector2(4, -22), Vector2(15, -12), color, 4.0)
	draw_arc(Vector2(-6, 8), 11.0, 0.0, TAU, 16, color.darkened(0.5), 2.0)
	draw_set_transform(Vector2.ZERO)
