extends Node2D

# coin_reset: a coin arcs up from where the marked target died and drops
# back into Jose's hand. Attached to the hero; context.target_position is the
# victim. Cosmetic only.

@export var duration: float = 0.55
@export var arc_height: float = 180.0
@export var radius: float = 12.0
@export var color: Color = Color(1.0, 0.85, 0.3, 1.0)

var _from := Vector2.ZERO
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	var target: Vector2 = context.get("target_position", global_position)
	_from = target - global_position
	# Keep the arc readable even when the victim was far away.
	_from = _from.limit_length(260.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var p := clampf(_t / duration, 0.0, 1.0)
	var pos := _from.lerp(Vector2(0, -40), p) + Vector2(0, -arc_height * 4.0 * p * (1.0 - p))
	var squash := maxf(absf(cos(_t * 30.0)), 0.12)
	draw_set_transform(pos, 0.0, Vector2(squash, 1.0))
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, color.darkened(0.4), 2.0)
	draw_set_transform(Vector2.ZERO)
	if p > 0.85:
		# The catch: a quick glint.
		draw_arc(Vector2(0, -40), radius * 2.5 * (p - 0.85) / 0.15 + radius, 0.0, TAU, 24, Color(1, 1, 0.8, 1.0 - p), 3.0)
