extends Node2D
class_name RingBurstEffect

# An expanding ring out to context.radius: bursts, shockwaves, revives.

@export var color: Color = Color(1.0, 0.6, 0.2, 0.9)
@export var fill_color: Color = Color(1.0, 0.8, 0.4, 0.25)
@export var duration: float = 0.35
@export var thickness: float = 14.0

var radius: float = 200.0
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	radius = context.get("radius", radius)


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var r := radius * (1.0 - pow(1.0 - k, 3.0))    # fast out, slow settle
	var fade := 1.0 - k
	var fill := fill_color
	fill.a *= fade
	draw_circle(Vector2.ZERO, r, fill)
	var ring := color
	ring.a *= fade
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, ring, thickness * fade + 2.0, true)
