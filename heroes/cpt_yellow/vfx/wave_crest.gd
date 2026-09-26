extends Node2D

# CHARGE!'s wave while it surges: a wide front of bugs rolling ahead of him
# (context.hit_width wide), a trailing wake, him riding on top. Attached to
# the actor for the dash (context.duration).

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var bug_rows: int = 3
@export var bugs_per_row: int = 16
@export var bug_size: float = 26.0
@export var crest_depth: float = 150.0

var _dir := Vector2.RIGHT
var _width := 400.0
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	var dir: Vector2 = context.get("direction", Vector2.RIGHT)
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_width = maxf(context.get("hit_width", _width), 40.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var side := _dir.orthogonal()
	var half := _width * 0.5
	# Wake behind.
	draw_colored_polygon(PackedVector2Array([side * half, side * half * 0.6 - _dir * 260.0,
		-side * half * 0.6 - _dir * 260.0, -side * half]), Color(1, 0.85, 0.2, 0.18))
	for row in bug_rows:
		for i in bugs_per_row:
			var lateral := lerpf(-half, half, (i + 0.5) / bugs_per_row)
			# Curved front: the middle leads.
			var ahead := crest_depth * (1.0 - pow(lateral / half, 2.0) * 0.5) - row * 38.0
			var at := _dir * ahead + side * lateral
			at += Vector2(sin(_t * 40.0 + i + row), cos(_t * 35.0 + i * 2.0)) * 4.0
			Bug.draw_bug(self, at, _dir, bug_size, 1.0 - row * 0.2, 0.5 + 0.5 * sin(_t * 70.0 + i))
