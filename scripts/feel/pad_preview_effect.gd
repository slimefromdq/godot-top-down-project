extends Node2D
class_name PadPreviewEffect

# Live preview for a PlacePadAbility while it charges (the press-drag-release
# aim): a ring where the pad will go, a ring where launched allies will land,
# and a dashed arc between them. Hook it to the <id>_charge_start cue; it
# reads the ability from context.charge_ability and frees itself when the
# charge ends. Drawn in world space, so the cue needn't attach to the actor.

@export var color: Color = Color(0.98, 0.8, 0.1, 0.8)
@export var line_width: float = 4.0
@export var landing_radius: float = 45.0
@export var dash_count: int = 14

var _ability: PlacePadAbility
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	top_level = true
	global_position = Vector2.ZERO
	rotation = 0.0
	var ability = context.get("charge_ability")
	if ability is PlacePadAbility:
		_ability = ability
		var pad_data := _ability.get_pad_data()
		if pad_data != null and pad_data.pad_color.a > 0.0:
			color = Color(pad_data.pad_color, color.a)


func _process(delta: float) -> void:
	_t += delta
	if _ability == null or not is_instance_valid(_ability) or not _ability.is_charging():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _ability == null or not is_instance_valid(_ability):
		return
	var pad_data := _ability.get_pad_data()
	var from := _ability.get_place_point()
	var to := _ability.landing_for(_ability.cast_target)
	var pulse := 0.75 + 0.25 * sin(_t * 8.0)
	var faint := Color(color, color.a * 0.25)
	draw_circle(from, pad_data.pad_radius, faint)
	draw_arc(from, pad_data.pad_radius, 0.0, TAU, 40, color, line_width)
	draw_arc(to, landing_radius, 0.0, TAU, 32, Color(color, color.a * pulse), line_width)
	draw_line(to + Vector2(-12, 0), to + Vector2(12, 0), color, line_width * 0.5)
	draw_line(to + Vector2(0, -12), to + Vector2(0, 12), color, line_width * 0.5)
	# The flight: a dashed arc lifted by the pad's arc_height.
	var lift := Vector2(0, -pad_data.arc_height)
	var steps := maxi(dash_count, 2) * 2
	for i in range(0, steps, 2):
		draw_line(_arc_point(from, to, lift, float(i) / steps),
			_arc_point(from, to, lift, float(i + 1) / steps), color, line_width * 0.75)
	# Arrowhead at the landing end, pointing along the flight.
	var tip := _arc_point(from, to, lift, 1.0)
	var back := (_arc_point(from, to, lift, 0.93) - tip).normalized() * 22.0
	draw_line(tip, tip + back.rotated(0.5), color, line_width)
	draw_line(tip, tip + back.rotated(-0.5), color, line_width)


func _arc_point(from: Vector2, to: Vector2, lift: Vector2, t: float) -> Vector2:
	return from.lerp(to, t) + lift * 4.0 * t * (1.0 - t)
