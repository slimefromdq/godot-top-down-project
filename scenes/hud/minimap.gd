extends CanvasLayer
class_name Minimap

# Bottom-right minimap. Reads everything from the scene, so it works on any
# GameMap without extra setup:
#
#   static layer   (drawn once)  floors, cover, ledges, teleporters, jump pads,
#                                speed strips, taken from the map's own nodes.
#   dynamic layer  (every frame) units and objectives, plus the camera view.
#
# Units: any Node2D in group "minimap_units" (Actor and TrainingDummy join it
# themselves). Colour comes from its `team` compared with the local player's:
# you = white arrow, same team = ally, other team = enemy, no team = neutral.
#
# Objectives: add any Node2D to group "minimap_objectives" and it shows as a
# diamond. Give it a `team` property to colour it by owner.

@export var width: float = 280.0
@export var margin: float = 20.0
@export var background := Color(0.08, 0.08, 0.1, 0.85)
@export var frame_color := Color(1, 1, 1, 0.5)
@export var ally_color := Color("4fd1c5")
@export var enemy_color := Color("f05252")
@export var neutral_color := Color("c8c8c8")
@export var objective_color := Color("fbbf24")

var _map: GameMap
var _root: Control
var _static: Control
var _dynamic: Control
var _scale: float = 1.0


func _ready() -> void:
	layer = 5
	_setup.call_deferred()


func _setup() -> void:
	_map = get_tree().get_first_node_in_group(&"game_map") as GameMap
	if _map == null:
		return
	var bounds := _map.bounds
	_scale = width / bounds.size.x
	var height := bounds.size.y * _scale

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.clip_contents = true
	_root.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_root.offset_left = -width - margin
	_root.offset_top = -height - margin
	_root.offset_right = -margin
	_root.offset_bottom = -margin
	add_child(_root)

	_static = _make_layer(_draw_static)
	_dynamic = _make_layer(_draw_dynamic)


func _make_layer(draw_callback: Callable) -> Control:
	var control := Control.new()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.draw.connect(draw_callback.bind(control))
	_root.add_child(control)
	return control


func _process(_delta: float) -> void:
	if _dynamic != null:
		_dynamic.queue_redraw()


# Map-local position -> minimap pixel.
func _to_minimap(map_point: Vector2) -> Vector2:
	return (map_point - _map.bounds.position) * _scale


func _to_map(node: Node2D, local := Vector2.ZERO) -> Vector2:
	return _map.get_global_transform().affine_inverse() * node.get_global_transform() * local


# Every map node of a class. (find_children's type filter only knows built-in
# classes, not script class_names, so filter with `is`.)
func _descendants(type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	for node in _map.find_children("*", "", true, false):
		if is_instance_of(node, type):
			result.append(node)
	return result


func _draw_static(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), background)
	# From here on, draw in map coordinates.
	canvas.draw_set_transform(-_map.bounds.position * _scale, 0.0, Vector2.ONE * _scale)
	var to_map := _map.get_global_transform().affine_inverse()

	for node in _descendants(Polygon2D):
		var polygon := node as Polygon2D
		if polygon.is_visible_in_tree():
			canvas.draw_colored_polygon((to_map * polygon.get_global_transform()) * polygon.polygon, polygon.color)

	for node in _descendants(SpeedStrip):
		var strip := node as SpeedStrip
		var corners := PackedVector2Array([-strip.size / 2.0, Vector2(strip.size.x, -strip.size.y) / 2.0,
			strip.size / 2.0, Vector2(-strip.size.x, strip.size.y) / 2.0])
		canvas.draw_colored_polygon((to_map * strip.get_global_transform()) * corners, Color(strip.color, 0.8))

	for node in _descendants(CoverBody):
		var body := node as CoverBody
		var full := body.height == CoverBody.Height.FULL
		var color := body.fill_color.darkened(0.25) if full else Color(body.fill_color.lightened(0.1), 0.8)
		for child in body.get_children():
			if child is CollisionPolygon2D and child.polygon.size() >= 3:
				canvas.draw_colored_polygon((to_map * child.get_global_transform()) * child.polygon, color)

	for node in _descendants(Ledge):
		var ledge := node as Ledge
		canvas.draw_line(_to_map(ledge), _to_map(ledge, Vector2(ledge.length, 0)), ledge.face_color.darkened(0.3), 45.0)

	for node in _descendants(JumpPad):
		canvas.draw_circle(_to_map(node), 110.0, (node as JumpPad).color)
	for node in _descendants(Teleporter):
		canvas.draw_circle(_to_map(node), 120.0, (node as Teleporter).color)

	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), frame_color, false, 2.0)


func _draw_dynamic(canvas: Control) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	var my_team: StringName = player.get("team") if player != null and player.get("team") != null else &""

	# What the camera currently shows.
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		var view_size := get_viewport().get_visible_rect().size / camera.zoom
		var center := _map.get_global_transform().affine_inverse() * camera.get_screen_center_position()
		canvas.draw_rect(Rect2(_to_minimap(center - view_size / 2.0), view_size * _scale), Color(1, 1, 1, 0.35), false, 1.0)

	for node in get_tree().get_nodes_in_group(&"minimap_objectives"):
		if node is Node2D and node.is_visible_in_tree():
			var point := _to_minimap(_to_map(node))
			var owner_team = node.get("team")
			var color := objective_color if owner_team == null or owner_team == &"" \
				else (ally_color if owner_team == my_team else enemy_color)
			canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(0, -7), point + Vector2(7, 0),
				point + Vector2(0, 7), point + Vector2(-7, 0)]), color)

	for node in get_tree().get_nodes_in_group(&"minimap_units"):
		if not node is Node2D or node == player or not node.is_visible_in_tree():
			continue
		var unit_team = node.get("team")
		var color := neutral_color
		if unit_team != null and unit_team != &"":
			color = ally_color if unit_team == my_team else enemy_color
		var point := _to_minimap(_to_map(node))
		canvas.draw_circle(point, 4.5, Color.BLACK)
		canvas.draw_circle(point, 3.5, color)

	# You: an arrow pointing where you aim, drawn last so it's always on top.
	if player != null and player.is_visible_in_tree():
		var point := _to_minimap(_to_map(player))
		var aim: Vector2 = player.get("aim_direction") if player.get("aim_direction") != null else Vector2.UP
		var side := aim.orthogonal()
		var arrow := PackedVector2Array([point + aim * 8.0, point - aim * 5.0 + side * 5.0, point - aim * 5.0 - side * 5.0])
		canvas.draw_colored_polygon(arrow, Color.WHITE)
		canvas.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.5)
