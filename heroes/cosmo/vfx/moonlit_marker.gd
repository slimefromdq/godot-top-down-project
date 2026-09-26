extends Node2D

# Moonlit's overhead marker: a pale crescent over the target, brighter the
# stronger the amp (it reads the status' fade to dim as it runs out).

var _status: StatusEffectComponent
var _status_id: StringName
var _t: float = 0.0

func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	position = Vector2(0, -115)
	z_index = 10
	_status = context.get("status_component")
	_status_id = context.get("status_id", &"")

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var left: float = _status.get_fade_ratio(_status_id) if is_instance_valid(_status) else 1.0
	var bob := Vector2(0, sin(_t * 3.0) * 3.0)
	var c := Color(0.85, 0.92, 1.0, lerpf(0.35, 1.0, left))
	draw_circle(bob, 16.0, Color(0.6, 0.75, 1.0, 0.25 * left))
	draw_arc(bob, 12.0, PI * 0.35, PI * 1.65, 20, c, 6.0, true)
