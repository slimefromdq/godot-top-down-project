extends Node2D

# The key stuck in a wound-up ally's back (Wind-Up Key's status visual).
# It unwinds: it spins slower and shrinks as the status fades, reading the
# live fade ratio from the status (VisualsComponent passes status_component
# and status_id to status visuals).

var color := Color(0.95, 0.8, 0.4)
var _status: StatusEffectComponent
var _status_id: StringName
var _angle: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	position = Vector2(-46, -44)
	z_index = 2
	_status = context.get("status_component")
	_status_id = context.get("status_id", &"")


func get_ratio() -> float:
	return _status.get_fade_ratio(_status_id) if is_instance_valid(_status) else 0.0


func _process(delta: float) -> void:
	var ratio := get_ratio()
	_angle -= delta * lerpf(1.0, 14.0, ratio)    # unwinding, slowing down
	queue_redraw()


func _draw() -> void:
	var ratio := get_ratio()
	var s := lerpf(0.6, 1.0, ratio)
	var tint := color
	tint.a = lerpf(0.4, 1.0, ratio)
	draw_line(Vector2.ZERO, Vector2(10, 10), tint.darkened(0.3), 4.0)
	draw_set_transform(Vector2.ZERO, _angle, Vector2(s, s))
	draw_circle(Vector2(-10, 0), 8.0, tint)
	draw_circle(Vector2(10, 0), 8.0, tint)
	draw_set_transform(Vector2.ZERO)
	# The spring left: an arc that shrinks with the fade.
	draw_arc(Vector2.ZERO, 20.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 24, Color(1, 1, 1, 0.8), 2.5)
