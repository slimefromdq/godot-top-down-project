extends Node2D

# Placeholder overhead marker for statuses that "mark" a target. Point a
# StatusEffect's attached_vfx at a scene with this script: the status
# presentation path attaches it to the target's Visuals for as long as the
# status lasts, and it draws itself above the head. Cosmetic only.

## Pixels above the actor's origin.
@export var height: float = 110.0
@export var color: Color = Color(1.0, 0.3, 0.35, 0.95)
@export var size: float = 14.0
## Gentle bob so it reads as a marker, not scenery.
@export var bob_amplitude: float = 4.0
@export var bob_speed: float = 4.0
## Draw a spinning coin instead of a diamond.
@export var coin: bool = false

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := Vector2(0, -height + sin(_time * bob_speed) * bob_amplitude)
	if coin:
		# A coin turning on its axis: squash the width with a cosine.
		var squash := maxf(absf(cos(_time * bob_speed * 0.8)), 0.15)
		draw_set_transform(center, 0.0, Vector2(squash, 1.0))
		draw_circle(Vector2.ZERO, size, color)
		draw_arc(Vector2.ZERO, size, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 2.0)
		draw_arc(Vector2.ZERO, size * 0.6, 0.0, TAU, 24, color.darkened(0.35), 2.0)
		draw_set_transform(Vector2.ZERO)
		return
	var points := PackedVector2Array([
		center + Vector2(0, -size), center + Vector2(size * 0.7, 0),
		center + Vector2(0, size), center + Vector2(-size * 0.7, 0)])
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(0, 0, 0, 0.8), 2.0)
