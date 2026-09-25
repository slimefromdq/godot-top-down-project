extends Node2D

# Avery's fiery crescent projectile: a moon-shaped blade of flame facing its
# flight direction (the Projectile rotates this node). Placeholder art drawn
# in code; swap for a sprite by replacing sun_crescent.tscn's contents.

@export var radius: float = 44.0
@export var thickness: float = 16.0
@export var core_color: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var flame_color: Color = Color(1.0, 0.5, 0.1, 0.85)
@export var arc_degrees: float = 150.0


func _draw() -> void:
	var half := deg_to_rad(arc_degrees) / 2.0
	var outer: PackedVector2Array = []
	var inner: PackedVector2Array = []
	for i in 21:
		var a := lerpf(-half, half, i / 20.0)
		# Thickest in the middle, tapering to points: a crescent.
		var t := sin(PI * i / 20.0)
		outer.append(Vector2.from_angle(a) * radius)
		inner.append(Vector2.from_angle(a) * (radius - thickness * t) + Vector2(-thickness * 0.6 * t, 0))
	inner.reverse()
	draw_colored_polygon(outer + inner, flame_color)
	draw_polyline(outer, core_color, 4.0, true)
