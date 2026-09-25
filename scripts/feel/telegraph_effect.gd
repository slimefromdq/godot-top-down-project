extends Node2D
class_name TelegraphEffect

# A warning line from the caster to where an attack will land, shown for the
# windup so opponents can read it. Context: target_position, duration.

@export var color: Color = Color(1.0, 0.55, 0.15, 0.55)
@export var width: float = 70.0

var _target := Vector2.ZERO
var _duration: float = 0.2
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	_target = context.get("target_position", global_position) - global_position
	_duration = maxf(context.get("duration", _duration), 0.05)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var fill := clampf(_t / _duration, 0.0, 1.0)
	var faint := color
	faint.a *= 0.35
	draw_line(Vector2.ZERO, _target, faint, width)
	draw_line(Vector2.ZERO, _target * fill, color, width * 0.5)
