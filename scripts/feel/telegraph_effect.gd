extends Node2D
class_name TelegraphEffect

# A warning line from the caster to where an attack will land, shown for the
# windup so opponents can read it. Context: target_position, duration.
#
# Live aim mode: when the context carries `charge_ability` (the
# <id>_charge_start cue does) and `range`, the line instead follows that
# ability's aim for as long as it is charging: thin and faint at first,
# brightening with the charge, bright at full charge, flashing during the
# perfect window. Attach the cue to the actor so the line moves with it.

@export var color: Color = Color(1.0, 0.55, 0.15, 0.55)
@export var width: float = 70.0

@export_group("Live aim mode")
@export var aim_width: float = 5.0
@export var aim_full_width: float = 8.0
@export var aim_color: Color = Color(1.0, 0.95, 0.8, 0.9)
@export var aim_perfect_color: Color = Color(1.0, 1.0, 1.0, 1.0)

var _target := Vector2.ZERO
var _duration: float = 0.2
var _t: float = 0.0
var _ability: Ability
var _range: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	var ability = context.get("charge_ability")
	if ability is Ability:
		_ability = ability
		_range = context.get("range", 800.0)
		return
	_target = context.get("target_position", global_position) - global_position
	_duration = maxf(context.get("duration", _duration), 0.05)


func _process(delta: float) -> void:
	_t += delta
	if _ability != null:
		if not is_instance_valid(_ability) or not _ability.is_charging():
			queue_free()
	elif _t >= _duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if _ability != null:
		_draw_aim()
		return
	var fill := clampf(_t / _duration, 0.0, 1.0)
	var faint := color
	faint.a *= 0.35
	draw_line(Vector2.ZERO, _target, faint, width)
	draw_line(Vector2.ZERO, _target * fill, color, width * 0.5)


func _draw_aim() -> void:
	if not is_instance_valid(_ability):
		return
	var ratio := _ability.get_charge_ratio()
	var end := _ability.cast_direction * _range
	var line_color := aim_color
	line_color.a *= lerpf(0.25, 1.0, ratio)
	var line_width := aim_width if ratio < 1.0 else aim_full_width
	if _ability.is_in_perfect_window():
		# Strobe: unmistakable, and readable for opponents too.
		line_color = aim_perfect_color if int(_t * 20.0) % 2 == 0 else aim_color
		line_width = aim_full_width * 1.5
	draw_line(Vector2.ZERO, end, line_color, line_width)
	# The charged part, to show progress along the line.
	draw_line(Vector2.ZERO, end * ratio, line_color.lightened(0.3), line_width * 0.5)
