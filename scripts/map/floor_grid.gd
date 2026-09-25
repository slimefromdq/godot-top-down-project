@tool
extends Node2D
class_name FloorGrid

# Faint grid over the whole floor. On flat-colour floors this is what lets you
# feel your speed: without texture, moving and standing still look the same.

@export var bounds := Rect2(-4800, -4860, 9600, 9720)
@export var spacing: float = 160.0
@export var color := Color(0, 0, 0, 0.05)
## Every Nth line is drawn stronger (one "tile" of the grid).
@export var major_every: int = 6


func _draw() -> void:
	var major := Color(color, color.a * 2.0)
	var i := 0
	var x := bounds.position.x
	while x <= bounds.end.x:
		draw_line(Vector2(x, bounds.position.y), Vector2(x, bounds.end.y), major if i % major_every == 0 else color, 2.0)
		x += spacing
		i += 1
	i = 0
	var y := bounds.position.y
	while y <= bounds.end.y:
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), major if i % major_every == 0 else color, 2.0)
		y += spacing
		i += 1
