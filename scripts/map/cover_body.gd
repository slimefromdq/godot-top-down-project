@tool
extends StaticBody2D
class_name CoverBody

# One piece of map cover: a rock, tree, wall, hedge, crate, pit, crystal...
#
# Its shape is the CollisionPolygon2D child. Edit that polygon with the editor's
# polygon tool and the drawing follows. Pick the height (the obstacle type) to
# decide what it blocks:
#
#                          moving   shots   sight
#   FULL     layer 1  (World)       yes      yes     yes    hard wall: rock, hedge, building
#   LOW      layer 6  (Low Cover)   yes      no      no     prop: crate, bench, balustrade
#   PIT      layer 9  (Pits)        yes      no      no     pit / water: shoot across it
#   CRYSTAL  layer 10 (Crystal)     yes      yes     no     crystal / glass: see, can't shoot
#
# Grass (blocks sight only) is a Bush, not cover. Knockback into FULL or
# CRYSTAL is a wall slam (GameRules.wall_impact_mask); into LOW or PIT it
# just stops. A jump pad's arc flies over LOW and PIT (MapLayers.JUMPABLE).
#
# Each type reads differently from the top-down camera:
#   FULL     solid fill, tall shadow, thick dark outline
#   LOW      solid fill, short shadow, dashed outline
#   PIT      dark sunken fill, no shadow, a lit inner rim and ripple lines
#   CRYSTAL  translucent fill (you see what's behind), bright outline, glints

enum Height { FULL, LOW, PIT, CRYSTAL }

const SHADOW := Color(0.02, 0.15, 0.3, 0.22)

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


static func layer_for(kind: Height) -> int:
	match kind:
		Height.LOW:
			return MapLayers.LOW_COVER
		Height.PIT:
			return MapLayers.PITS
		Height.CRYSTAL:
			return MapLayers.CRYSTAL
	return MapLayers.WORLD


func _apply_layers() -> void:
	collision_layer = layer_for(height)
	collision_mask = 0


func _polygons() -> Array:
	var result := []
	for child in get_children():
		if child is CollisionPolygon2D and child.polygon.size() >= 3:
			result.append(child.transform * child.polygon)
	return result


func _draw() -> void:
	# Everything as one mesh: one draw call per piece of cover.
	var batch := ShapeBatch.new()
	for polygon: PackedVector2Array in _polygons():
		match height:
			Height.PIT:
				_draw_pit(batch, polygon)
			Height.CRYSTAL:
				_draw_crystal(batch, polygon)
			_:
				_draw_solid(batch, polygon, height == Height.FULL)
	batch.draw_on(self)


func _draw_solid(batch: ShapeBatch, polygon: PackedVector2Array, is_full: bool) -> void:
	var shadow_offset := Vector2(10, 16) if is_full else Vector2(5, 7)
	var edge := fill_color.darkened(0.5)
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + shadow_offset)
	batch.draw_colored_polygon(shadow, SHADOW)
	batch.draw_colored_polygon(polygon, fill_color)
	AeroDraw.gloss_polygon(batch, polygon, fill_color)
	var outline := _closed(polygon)
	if is_full:
		batch.draw_polyline(outline, edge, 5.0, true)
	else:
		for i in polygon.size():
			batch.draw_dashed_line(outline[i], outline[i + 1], edge, 4.0, 14.0)


# Sunken: no shadow (it's below the floor), darker toward the middle, a lit
# lip all round and a few ripple lines so it reads as "you'd fall in".
func _draw_pit(batch: ShapeBatch, polygon: PackedVector2Array) -> void:
	var base := fill_color
	batch.draw_colored_polygon(polygon, base.lightened(0.1))
	var inner := Geometry2D.offset_polygon(polygon, -18.0)
	for part: PackedVector2Array in inner:
		batch.draw_colored_polygon(part, base)
		for deeper: PackedVector2Array in Geometry2D.offset_polygon(part, -40.0):
			batch.draw_colored_polygon(deeper, base.darkened(0.25))
	batch.draw_polyline(_closed(polygon), base.lightened(0.55), 6.0, true)
	var bounds := _bounds(polygon)
	var ripple := Color(base.lightened(0.45), 0.55)
	var step := 70.0
	var y := bounds.position.y + step
	while y < bounds.end.y - step * 0.5:
		var x := bounds.position.x + fmod(y * 0.37, step)
		while x < bounds.end.x - 40.0:
			var a := Vector2(x, y)
			var b := Vector2(x + 34.0, y)
			if Geometry2D.is_point_in_polygon(a, polygon) and Geometry2D.is_point_in_polygon(b, polygon):
				batch.draw_line(a, b, ripple, 3.0)
			x += step * 1.6
		y += step


# See-through: a pale translucent fill (what's behind shows through), a
# bright double outline and diagonal glints, and a thin shadow (it's tall).
func _draw_crystal(batch: ShapeBatch, polygon: PackedVector2Array) -> void:
	var tint := fill_color
	var shadow := PackedVector2Array()
	for point in polygon:
		shadow.append(point + Vector2(6, 10))
	batch.draw_colored_polygon(shadow, Color(SHADOW, 0.12))
	batch.draw_colored_polygon(polygon, Color(tint, 0.28))
	var outline := _closed(polygon)
	batch.draw_polyline(outline, Color(tint.darkened(0.35), 0.9), 7.0, true)
	batch.draw_polyline(outline, Color(1, 1, 1, 0.95), 2.5, true)
	var bounds := _bounds(polygon)
	var glint := Color(1, 1, 1, 0.7)
	var step := 90.0
	var t := bounds.position.x - bounds.size.y
	while t < bounds.end.x:
		var a := Vector2(t, bounds.end.y)
		var b := Vector2(t + bounds.size.y, bounds.position.y)
		var mid := (a + b) / 2.0
		var dir := (b - a).normalized() * 22.0
		if Geometry2D.is_point_in_polygon(mid - dir, polygon) and Geometry2D.is_point_in_polygon(mid + dir, polygon):
			batch.draw_line(mid - dir, mid + dir, glint, 3.0)
		t += step


static func _closed(polygon: PackedVector2Array) -> PackedVector2Array:
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	return outline


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	return rect
