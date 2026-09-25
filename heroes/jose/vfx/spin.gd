extends Node2D

# flourish_reload: a quick circular swoosh around Jose as he flips and spins
# the cylinders. Attached to the hero. Cosmetic only.

@export var duration: float = 0.28
@export var radius: float = 70.0
@export var color: Color = Color(1.0, 0.85, 0.35, 0.9)
@export var width: float = 6.0

var _t: float = 0.0


func setup_cue(_context: Dictionary) -> void:
	rotation = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var p := clampf(_t / duration, 0.0, 1.0)
	var head := p * TAU * 1.25
	var faded := color
	faded.a *= 1.0 - p
	draw_arc(Vector2.ZERO, radius, head - PI * 0.9, head, 24, faded, width * (1.0 - p * 0.5), true)
