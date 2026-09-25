@tool
extends Node2D
class_name Stairwell

# Drawing of a stairway up to high ground. It has no collision: a stairwell is
# simply a gap left in the Ledges, and its rails are ordinary low cover.
# Local +X points up the stairs (from low ground to high ground).

@export var width: float = 400.0:
	set(value):
		width = value
		queue_redraw()
@export var depth: float = 320.0:
	set(value):
		depth = value
		queue_redraw()
@export var color := Color("e8d6a8")

const STEP := 40.0


func _draw() -> void:
	var half_w := width / 2.0
	var steps := maxi(2, int(depth / STEP))
	for i in steps:
		# Lighter toward the top so the slope direction reads without the arrow.
		var t := float(i) / (steps - 1)
		var x := -depth / 2.0 + depth * i / steps
		var step_color := color.darkened(0.3 * (1.0 - t))
		draw_rect(Rect2(x, -half_w, depth / steps, width), step_color)
		draw_line(Vector2(x, -half_w), Vector2(x, half_w), color.darkened(0.45), 3.0)
	var ink := color.darkened(0.55)
	draw_rect(Rect2(-depth / 2.0, -half_w, depth, width), ink, false, 4.0)
	var tail := Vector2(-depth * 0.3, 0)
	var tip := Vector2(depth * 0.35, 0)
	draw_line(tail, tip, ink, 8.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(20, 0), tip + Vector2(-22, -28), tip + Vector2(-22, 28)]), ink)
