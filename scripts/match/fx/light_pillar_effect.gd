extends Node2D

# The Dream Mote is coming: a soft pillar of light over its spot that
# brightens as the moment nears, a ground ring filling in, and sparkles
# drifting up. Frees itself after the duration. Context: duration, radius.

@export var height: float = 1100.0
@export var color := Color(0.9, 0.82, 1.0)

var duration: float = 15.0
var radius: float = 180.0
var _t := 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	duration = maxf(context.get("duration", duration), 0.1)
	radius = context.get("radius", radius)
	z_index = 3


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 0.3:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var fade_in := minf(_t / 1.0, 1.0)
	var pulse := 0.8 + 0.2 * sin(_t * lerpf(2.0, 9.0, k))
	# Ground: a ring with a disc filling toward it.
	draw_circle(Vector2.ZERO, radius, Color(color, 0.12 * fade_in))
	draw_circle(Vector2.ZERO, radius * k, Color(color, 0.22 * fade_in))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.8 * fade_in * pulse), 5.0)
	# The pillar: layered columns, brighter toward the middle and the end.
	for i in 5:
		var w := radius * (1.1 - i * 0.2)
		var a := (0.04 + 0.1 * k) * (i + 1) * fade_in * pulse
		var c := Color.from_hsv(fmod(0.75 + _t * 0.03 + i * 0.04, 1.0), 0.25, 1.0, a)
		draw_rect(Rect2(-w / 2.0, -height, w, height), c)
	for i in 10:
		var up := fmod(_t * 0.25 + i / 10.0, 1.0)
		var x := sin(_t + i * 1.7) * radius * 0.4
		draw_circle(Vector2(x, -up * height), 5.0 * (1.0 - up) + 1.0, Color(1, 1, 1, 0.7 * (1.0 - up) * fade_in))
