extends Node2D

# Rally: the army swarms back around him as a spinning shield wall for the
# shield's duration. Thicker the more enemies were counted (context.enemies).

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var base_bugs: int = 14
@export var bugs_per_enemy: int = 5
@export var ring_radius: float = 92.0
@export var bug_size: float = 22.0

var _enemies := 0
var _duration := 2.0
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	_enemies = context.get("enemies", 0)
	_duration = maxf(context.get("duration", _duration), 0.1)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var gather := clampf(_t / 0.2, 0.0, 1.0)
	var fade := clampf((_duration - _t) / 0.3, 0.0, 1.0)
	var count := base_bugs + bugs_per_enemy * _enemies
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, Color(1, 0.9, 0.3, 0.35 * fade), 10.0, true)
	for i in count:
		var a := TAU * i / count + _t * 4.0
		var r := lerpf(ring_radius * 2.4, ring_radius + sin(i * 3.0 + _t * 9.0) * 6.0, gather)
		var at := Vector2.from_angle(a) * r
		Bug.draw_bug(self, at, Vector2.from_angle(a + PI / 2.0), bug_size, fade, 0.5 + 0.5 * sin(_t * 60.0 + i))
	if _enemies > 0:
		draw_string(ThemeDB.fallback_font, Vector2(-20, -ring_radius - 16), "x%d" % _enemies,
			HORIZONTAL_ALIGNMENT_CENTER, 40, 26, Color(1, 0.95, 0.4, fade))
