extends Node2D

# CHARGE! wind-up: loud on purpose. The army piles up into a growing mound
# BEHIND him while the full wave lane (context.hit_width wide, to
# context.target_position) lights up in front and fills toward the end
# point. A bugle "!" pops over his head. Attached to the actor.

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var lane_color: Color = Color(1.0, 0.8, 0.1, 0.22)
@export var lane_edge_color: Color = Color(1.0, 0.9, 0.3, 0.95)
@export var pile_bugs: int = 60
@export var bug_size: float = 24.0

var _target := Vector2.RIGHT * 800.0
var _width := 400.0
var _duration := 0.5
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	_target = context.get("target_position", global_position + Vector2.RIGHT * 800.0) - global_position
	_width = maxf(context.get("hit_width", _width), 40.0)
	_duration = maxf(context.get("duration", _duration), 0.05)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _duration, 0.0, 1.0)
	var dir := _target.normalized() if _target != Vector2.ZERO else Vector2.RIGHT
	var side := dir.orthogonal()
	var half := side * _width * 0.5
	# The lane: faint full area, a brighter fill racing to the end point,
	# hard edges that strobe near the launch.
	draw_colored_polygon(PackedVector2Array([half, _target + half, _target - half, -half]), lane_color)
	var filled := _target * k
	var fill := lane_color
	fill.a = minf(lane_color.a * 2.2, 1.0)
	draw_colored_polygon(PackedVector2Array([half, filled + half, filled - half, -half]), fill)
	var edge := lane_edge_color
	if k > 0.6 and int(_t * 24.0) % 2 == 0:
		edge = Color.WHITE
	draw_line(half, _target + half, edge, 6.0)
	draw_line(-half, _target - half, edge, 6.0)
	draw_line(_target + half, _target - half, edge, 8.0)
	# The pile behind him: bugs climb in, stacking higher and wider.
	var shown := int(pile_bugs * clampf(k * 1.3, 0.0, 1.0))
	for i in shown:
		var row := float(i % 12) / 11.0 - 0.5
		var depth := float(i / 12)
		var at := -dir * (70.0 + depth * 26.0) + side * row * _width * lerpf(0.4, 0.9, k)
		at += Vector2(0, -depth * 10.0 * k) + Vector2(sin(_t * 30.0 + i), cos(_t * 27.0 + i)) * 3.0
		Bug.draw_bug(self, at, dir, bug_size, 1.0, 0.5 + 0.5 * sin(_t * 60.0 + i))
	# Bugle call.
	var pop := 1.0 + 0.25 * sin(_t * 30.0)
	var font_size := int(64 * pop)
	draw_string(ThemeDB.fallback_font, Vector2(-font_size * 0.15, -110), "!", HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(1, 0.9, 0.2))
