extends Node2D

# A ring of little four-point sparkles bursting outward and fading, with a
# soft flash in the middle: Mote spawn pops, pickups, deposits. Cosmetic.
# Context: radius (default 60), sparkles (how many), color.

@export var lifetime: float = 0.45
@export var count: int = 8
@export var radius: float = 60.0
@export var color := Color(1.0, 0.95, 0.6)

var _t := 0.0
var _spin := randf() * TAU


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	radius = context.get("radius", radius)
	count = context.get("sparkles", count)
	color = context.get("color", color)


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / lifetime, 0.0, 1.0)
	var out := 1.0 - pow(1.0 - k, 3.0)
	var fade := 1.0 - k
	draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - k), Color(1, 1, 1, 0.5 * fade))
	for i in count:
		var at := Vector2.from_angle(_spin + TAU * i / count) * radius * out
		var s := 7.0 * fade + 2.0
		var c := Color(color, fade)
		draw_line(at + Vector2(-s, 0), at + Vector2(s, 0), c, 2.5)
		draw_line(at + Vector2(0, -s), at + Vector2(0, s), c, 2.5)
		draw_circle(at, 2.5, Color(1, 1, 1, fade))
