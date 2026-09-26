extends Node2D

# Sting's slow: a bug clinging to the target for as long as the slow lasts
# (StatusEffect.attached_vfx; freed when the status ends).

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var size: float = 30.0

var _t := 0.0


func setup_cue(_context: Dictionary) -> void:
	rotation = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# Wriggles in place; a faint slow ring under the target.
	draw_arc(Vector2(0, 40), 46.0, 0.0, TAU, 32, Color(1, 0.85, 0.2, 0.35), 4.0, true)
	var at := Vector2(18, -28) + Vector2(sin(_t * 11.0), cos(_t * 13.0)) * 3.0
	Bug.draw_bug(self, at, Vector2(-0.6, 0.8), size, 1.0, 0.5 + 0.5 * sin(_t * 50.0))
