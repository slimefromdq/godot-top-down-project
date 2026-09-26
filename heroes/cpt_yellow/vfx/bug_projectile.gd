extends Node2D

# A flying bug (Stinger Volley, Sting). The projectile rotates this node to
# face its flight, so the bug is drawn facing +x.

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var size: float = 22.0
## Draw a stinger (the Sting skillshot).
@export var stinger: bool = false

var _t := randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var flap := 0.5 + 0.5 * sin(_t * 60.0)
	var wobble := Vector2(0, sin(_t * 30.0) * size * 0.08)
	Bug.draw_bug(self, wobble, Vector2.RIGHT, size, 1.0, flap)
	if stinger:
		draw_colored_polygon(PackedVector2Array([Vector2(size * 0.5, -size * 0.1) + wobble,
			Vector2(size * 0.95, 0) + wobble, Vector2(size * 0.5, size * 0.1) + wobble]), Color(0.2, 0.15, 0.05))
