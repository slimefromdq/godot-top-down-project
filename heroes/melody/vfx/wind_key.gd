extends Node2D

# The wind-up key in Melody's back. Its rotation shows the turns: each turn
# tightens it a quarter turn (with a quick spin), unwinding ticks it back.
# A notch per turn lights up around the bow, so the count reads at a glance.
# Cosmetic only; `key` (her passive) owns the numbers.

var key: Node    # melody_key.gd
var offset := Vector2(-46, -44)
var color := Color(0.95, 0.8, 0.4)

var _angle: float = 0.0
var _target_angle: float = 0.0
var _last_turns: int = 0


func _ready() -> void:
	# In front of the sprite, poking out over her shoulder: it must read.
	z_index = 2
	position = offset


func _process(delta: float) -> void:
	if not is_instance_valid(key):
		queue_free()
		return
	var turns: int = key.turns
	if turns != _last_turns:
		# A new turn spins a full rotation plus the quarter; unwinding ticks back.
		_target_angle += (turns - _last_turns) * PI / 2.0 + (TAU if turns > _last_turns else 0.0)
		_last_turns = turns
	_angle = lerpf(_angle, _target_angle, minf(delta * 12.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(key):
		return
	var turns: int = key.turns
	var max_turns: int = key.get_max_turns()
	var ready: bool = key.can_encore()
	var tint := color if not ready else Color(1.0, 0.95, 0.6)
	# Shaft into her back, then the two-lobed bow, rotating.
	draw_line(Vector2.ZERO, Vector2(10, 10), tint.darkened(0.3), 5.0)
	draw_set_transform(Vector2.ZERO, _angle)
	draw_circle(Vector2(-11, 0), 9.0, tint)
	draw_circle(Vector2(11, 0), 9.0, tint)
	draw_rect(Rect2(-4, -4, 8, 8), tint.darkened(0.2))
	draw_set_transform(Vector2.ZERO)
	# Notches: lit = turns.
	for i in max_turns:
		var a := -PI / 2.0 + (i - (max_turns - 1) / 2.0) * 0.5
		var at := Vector2.from_angle(a) * 26.0
		if i < turns:
			draw_circle(at, 4.5, Color(1.0, 0.9, 0.3) if not ready else Color.WHITE)
		else:
			draw_arc(at, 4.0, 0.0, TAU, 12, Color(1, 1, 1, 0.45), 1.5)
