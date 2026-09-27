extends RefCounted
class_name ShapeBatch

# Records flat-coloured 2D shapes into ONE triangle list, drawn with one draw
# call.
#
# Godot's canvas renderer batches rects and short lines, but every
# draw_circle() and draw_colored_polygon() is a draw call of its own. The
# glossy look (AeroDraw) stacks several circles per object, so a map full of
# bushes, cover and minimap shapes costs hundreds of draw calls a frame.
# ShapeBatch takes the same calls as a CanvasItem (the subset below), so
# existing _draw() code can draw into a batch unchanged:
#
#   var batch := ShapeBatch.new()
#   AeroDraw.gloss_circle(batch, Vector2.ZERO, 40.0, color)
#   batch.draw_colored_polygon(points, color)
#   batch.draw_on(self)        # in _draw(): one draw call
#
# Build it once for static drawings (keep the batch, call draw_on() in each
# _draw()), or every redraw for moving ones. Shapes keep their painting
# order. Lines and arcs are plain quads (no round joins or antialiasing).
#
# Supported: draw_set_transform, draw_circle, draw_colored_polygon,
# draw_polygon, draw_rect, draw_line, draw_dashed_line, draw_multiline,
# draw_polyline, draw_arc; plus draw_rounded_rect.

var _vertices := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _transform := Transform2D.IDENTITY


func is_empty() -> bool:
	return _vertices.is_empty()


func clear() -> void:
	_vertices.clear()
	_colors.clear()
	_indices.clear()
	_transform = Transform2D.IDENTITY


## One draw call. Call it from `canvas`'s _draw() (after any
## canvas.draw_set_transform(), which it follows like the other draw calls).
func draw_on(canvas: CanvasItem) -> void:
	if _vertices.is_empty():
		return
	if _indices.size() != _vertices.size():
		_indices.resize(_vertices.size())
		for i in _indices.size():
			_indices[i] = i
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _indices, _vertices, _colors)


func get_triangle_count() -> int:
	return _vertices.size() / 3


# --- The CanvasItem-style API ------------------------------------------------

func draw_set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_transform = Transform2D(rotation, scale, 0.0, position)


func draw_circle(position: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0,
		_antialiased: bool = false) -> void:
	if not filled:
		draw_arc(position, radius, 0.0, TAU, _segments(radius), color, width)
		return
	var count := _segments(radius)
	var center := _transform * position
	var previous := _transform * (position + Vector2(radius, 0.0))
	for i in range(1, count + 1):
		var next := _transform * (position + Vector2.from_angle(TAU * i / count) * radius)
		_triangle(center, previous, next, color)
		previous = next


func draw_colored_polygon(points: PackedVector2Array, color: Color, _uvs := PackedVector2Array(),
		_texture: Texture2D = null) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3):
		_triangle(_transform * points[indices[i]], _transform * points[indices[i + 1]],
			_transform * points[indices[i + 2]], color)


func draw_polygon(points: PackedVector2Array, colors: PackedColorArray, _uvs := PackedVector2Array(),
		_texture: Texture2D = null) -> void:
	if colors.size() < points.size():
		draw_colored_polygon(points, colors[0] if not colors.is_empty() else Color.WHITE)
		return
	var indices := Geometry2D.triangulate_polygon(points)
	for i in indices:
		_vertices.append(_transform * points[i])
		_colors.append(colors[i])


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, _antialiased: bool = false) -> void:
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])
	if filled:
		_quad(_transform * corners[0], _transform * corners[1], _transform * corners[2], _transform * corners[3], color)
		return
	corners.append(corners[0])
	draw_polyline(corners, color, width)


## Not a CanvasItem call: a rect with rounded corners (`bottom_radius` < 0 =
## same as the top).
func draw_rounded_rect(rect: Rect2, color: Color, radius: float, bottom_radius: float = -1.0) -> void:
	var top := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var bottom := top if bottom_radius < 0.0 else minf(bottom_radius, minf(rect.size.x, rect.size.y) * 0.5)
	if top <= 0.0 and bottom <= 0.0:
		draw_rect(rect, color)
		return
	var points := PackedVector2Array()
	var corners := [[rect.end - Vector2(bottom, bottom), 0.0, bottom],
		[Vector2(rect.position.x + bottom, rect.end.y - bottom), PI * 0.5, bottom],
		[rect.position + Vector2(top, top), PI, top],
		[Vector2(rect.end.x - top, rect.position.y + top), PI * 1.5, top]]
	for corner in corners:
		for i in 5:
			var point: Vector2 = corner[0] + Vector2.from_angle(corner[1] + PI * 0.5 * i / 4.0) * corner[2]
			# A full pill's corner arcs meet: repeated points break triangulation.
			if points.is_empty() or not point.is_equal_approx(points[points.size() - 1]):
				points.append(point)
	if points.size() > 3 and points[0].is_equal_approx(points[points.size() - 1]):
		points.remove_at(points.size() - 1)
	draw_colored_polygon(points, color)


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	var half := maxf(width, 1.0) * 0.5
	var side := (to - from).orthogonal().normalized() * half
	if side == Vector2.ZERO:
		return
	_quad(_transform * (from + side), _transform * (to + side), _transform * (to - side), _transform * (from - side), color)


func draw_multiline(points: PackedVector2Array, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	for i in range(0, points.size() - 1, 2):
		draw_line(points[i], points[i + 1], color, width)


func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, _antialiased: bool = false) -> void:
	for i in range(1, points.size()):
		draw_line(points[i - 1], points[i], color, width)
	# Round joins, so thick outlines don't show notches at their corners.
	if width >= 3.0:
		for i in range(1, points.size() - 1):
			draw_circle(points[i], width * 0.5, color)
		if points.size() > 2 and points[0] == points[points.size() - 1]:
			draw_circle(points[0], width * 0.5, color)


func draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, dash: float = 2.0,
		_aligned: bool = true, _antialiased: bool = false) -> void:
	var length := from.distance_to(to)
	if length <= 0.0 or dash <= 0.0:
		return
	var step := (to - from) / length
	var at := 0.0
	while at < length:
		draw_line(from + step * at, from + step * minf(at + dash, length), color, width)
		at += dash * 2.0


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, color: Color,
		width: float = -1.0, _antialiased: bool = false) -> void:
	var count := maxi(point_count, 2)
	var points := PackedVector2Array()
	for i in count:
		var angle := lerpf(start_angle, end_angle, float(i) / (count - 1))
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_polyline(points, color, width)


# --- Internals -----------------------------------------------------------------

static func _segments(radius: float) -> int:
	return clampi(int(radius * 0.5), 12, 48)


func _triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_vertices.append(a)
	_vertices.append(b)
	_vertices.append(c)
	_colors.append(color)
	_colors.append(color)
	_colors.append(color)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_triangle(a, b, c, color)
	_triangle(a, c, d, color)
