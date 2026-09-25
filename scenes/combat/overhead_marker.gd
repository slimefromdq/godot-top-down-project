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

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := Vector2(0, -height + sin(_time * bob_speed) * bob_amplitude)
	var points := PackedVector2Array([
		center + Vector2(0, -size), center + Vector2(size * 0.7, 0),
		center + Vector2(0, size), center + Vector2(-size * 0.7, 0)])
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(0, 0, 0, 0.8), 2.0)
