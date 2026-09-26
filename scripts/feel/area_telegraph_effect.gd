extends Node2D
class_name AreaTelegraphEffect

# A warning circle for an area attack that is about to land around its
# caster (a landing burst, a slam): a faint disc with a hard rim at the full
# radius, filling in from the centre over the windup, the rim pulsing faster
# as the hit gets closer. Opponents read "get out of the circle".
# Context: radius, duration. Attach the cue to the actor so it follows.
# Subclasses draw extra layers in _draw_extra(progress).

@export var color: Color = Color(1.0, 0.85, 0.15, 0.9)
@export var fill_color: Color = Color(1.0, 0.8, 0.1, 0.18)
@export var rim_width: float = 6.0
## Rim pulses per second at the start and at the moment of impact.
@export var pulse_start: float = 4.0
@export var pulse_end: float = 18.0

var radius: float = 200.0
var duration: float = 0.25
var _t: float = 0.0


func setup_cue(context: Dictionary) -> void:
	rotation = 0.0
	radius = context.get("radius", radius)
	duration = maxf(context.get("duration", duration), 0.05)


func get_progress() -> float:
	return clampf(_t / duration, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 0.05:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := get_progress()
	draw_circle(Vector2.ZERO, radius, fill_color)
	var inner := fill_color
	inner.a = minf(fill_color.a * 2.5, 1.0)
	draw_circle(Vector2.ZERO, radius * k, inner)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * lerpf(pulse_start, pulse_end, k))
	var rim := color
	rim.a *= lerpf(0.55, 1.0, pulse)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, rim, rim_width * lerpf(1.0, 1.6, k), true)
	_draw_extra(k)


func _draw_extra(_progress: float) -> void:
	pass
