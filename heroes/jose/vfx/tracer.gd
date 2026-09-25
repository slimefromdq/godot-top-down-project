extends Node2D

# Placeholder bullet look for Jose: a bright streak trailing the round. The
# projectile rotates this node to face its flight, so the tail is along -x.

@export var length: float = 90.0
@export var width: float = 4.0
@export var head_color: Color = Color(1.0, 0.97, 0.8, 1.0)
@export var tail_color: Color = Color(1.0, 0.6, 0.25, 0.0)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var steps := 6
	for i in steps:
		var a := float(i) / steps
		var b := float(i + 1) / steps
		draw_line(Vector2(-length * a, 0), Vector2(-length * b, 0),
			head_color.lerp(tail_color, b), width * (1.0 - a * 0.6))
	draw_circle(Vector2.ZERO, width * 0.9, head_color)
