@tool
extends StaticBody2D
class_name CoverBody

# One piece of map cover: a rock, tree, wall, hedge, crate...
#
# Its shape is the CollisionPolygon2D child. Edit that polygon with the editor's
# polygon tool and the drawing follows. Pick the height to decide what it blocks:
#
#   FULL  layer 1 (World):      blocks movement AND shots.
#   LOW   layer 6 (Low Cover):  blocks movement only; shots fly over it.
#
# Full cover draws a tall shadow and a solid outline, low cover a short
# shadow and a dashed outline, so the two read differently at a glance.

enum Height { FULL, LOW }

const SHADOW := Color(0, 0, 0, 0.22)

@export var height: Height = Height.FULL:
	set(value):
		height = value
		_apply_layers()
		queue_redraw()
@export var fill_color := Color("6b6560"):
	set(value):
		fill_color = value
		queue_redraw()

var _last_shapes: Array = []


func _ready() -> void:
	_apply_layers()
	# In the editor, watch the polygons so the drawing follows edits.
	set_process(Engine.is_editor_hint())
	queue_redraw()


func _process(_delta: float) -> void:
	var shapes := _polygons()
	if shapes != _last_shapes:
		_last_shapes = shapes
		queue_redraw()


func _apply_layers() -> void:
	collision_layer = MapLayers.WORLD if height == Height.FULL else MapLayers.LOW_COVER
	collision_mask = 0


func _polygons() -> Array:
	var result := []
	for child in get_children():
		if child is CollisionPolygon2D and child.polygon.size() >= 3:
			result.append(child.transform * child.polygon)
	return result


func _draw() -> void:
	var is_full := height == Height.FULL
	var shadow_offset := Vector2(10, 16) if is_full else Vector2(5, 7)
	var edge := fill_color.darkened(0.5)
	for polygon: PackedVector2Array in _polygons():
		var shadow := PackedVector2Array()
		for point in polygon:
			shadow.append(point + shadow_offset)
		draw_colored_polygon(shadow, SHADOW)
		draw_colored_polygon(polygon, fill_color)

		var outline := polygon.duplicate()
		outline.append(polygon[0])
		if is_full:
			draw_polyline(outline, edge, 5.0, true)
		else:
			for i in polygon.size():
				draw_dashed_line(outline[i], outline[i + 1], edge, 4.0, 14.0)
