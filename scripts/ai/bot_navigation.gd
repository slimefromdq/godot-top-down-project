extends RefCounted
class_name BotNavigation

## One obstacle graph per map, shared by every bot. Ordinary edges are
## walkable grid segments. Map jump pads and teleporters add directed edges.

class RouteGraph extends AStar2D:
	var special_costs: Dictionary = {}

	func _compute_cost(from_id: int, to_id: int) -> float:
		return special_costs.get(Vector2i(from_id, to_id), get_point_position(from_id).distance_to(get_point_position(to_id)))

	func _estimate_cost(_from_id: int, _end_id: int) -> float:
		# Zero keeps long teleports admissible: a Euclidean heuristic would
		# overestimate the remaining cost across a shortcut.
		return 0.0


static var _shared: Dictionary = {}

var map: GameMap
var graph := RouteGraph.new()
var cells: Dictionary = {}  # Vector2i -> graph point id
var teleport_entries: Dictionary = {}  # entrance position -> exit position
var origin: Vector2
var width: int
var height: int
var cell_size: float
var _next_id: int = 1
var _shape := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()


static func for_actor(actor: Hero) -> BotNavigation:
	if actor == null or not actor.is_inside_tree():
		return null
	var current_map := actor.get_tree().get_first_node_in_group(&"game_map") as GameMap
	if current_map == null:
		return null
	var id := current_map.get_instance_id()
	if not _shared.has(id):
		var navigation := BotNavigation.new()
		navigation.map = current_map
		navigation._build()
		_shared[id] = navigation
		current_map.tree_exiting.connect(func(): _shared.erase(id), CONNECT_ONE_SHOT)
	return _shared[id]


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := _nearest(from)
	var finish := _nearest(to)
	if start == 0 or finish == 0:
		return PackedVector2Array()
	var result := graph.get_point_path(start, finish)
	if not result.is_empty() and _edge_clear(result[result.size() - 1], to):
		result.append(to)
	return result


func _build() -> void:
	var rules := BotRules.current()
	cell_size = rules.navigation_cell_size
	_shape.radius = rules.navigation_actor_radius
	_query.shape = _shape
	_query.collision_mask = MapLayers.WORLD | MapLayers.LOW_COVER | MapLayers.LEDGES
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	origin = map.to_global(map.bounds.position)
	width = maxi(1, ceili(map.bounds.size.x / cell_size))
	height = maxi(1, ceili(map.bounds.size.y / cell_size))
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var point := _point(cell)
			if _clear(point):
				_add_point(point, cell)
	for cell in cells:
		var id: int = cells[cell]
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var next: int = cells.get(cell + offset, 0)
			if next != 0 and _edge_clear(graph.get_point_position(id), graph.get_point_position(next)):
				graph.connect_points(id, next)
	for node in map.get_tree().get_nodes_in_group(JumpPad.GROUP):
		if node is JumpPad and map.is_ancestor_of(node):
			var pad := node as JumpPad
			if pad.owner_actor == null:
				_add_link(pad.global_position, pad.get_landing_position())
	for node in map.find_children("*", "Area2D", true, false):
		if node is Teleporter:
			var portal := node as Teleporter
			if portal.can_send():
				_add_link(portal.global_position, portal.partner.global_position)
				teleport_entries[portal.global_position] = portal.partner.global_position


func _point(cell: Vector2i) -> Vector2:
	return origin + Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5


func _clear(point: Vector2) -> bool:
	_query.transform = Transform2D(0.0, point)
	return map.get_world_2d().direct_space_state.intersect_shape(_query, 1).is_empty()


func _edge_clear(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, _query.collision_mask)
	return map.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _add_point(point: Vector2, cell: Vector2i = Vector2i(-1, -1)) -> int:
	var id := _next_id
	_next_id += 1
	graph.add_point(id, point)
	if cell.x >= 0:
		cells[cell] = id
	return id


func _nearest(point: Vector2) -> int:
	var center := Vector2i(floori((point.x - origin.x) / cell_size), floori((point.y - origin.y) / cell_size))
	var best := 0
	var distance := INF
	for y in range(-2, 3):
		for x in range(-2, 3):
			var id: int = cells.get(center + Vector2i(x, y), 0)
			if id == 0:
				continue
			var d := graph.get_point_position(id).distance_squared_to(point)
			if d < distance:
				best = id
				distance = d
	return best


func _add_link(entry: Vector2, exit: Vector2) -> void:
	var start := _nearest(entry)
	var finish := _nearest(exit)
	if start == 0 or finish == 0:
		return
	var entry_id := _add_point(entry)
	var exit_id := _add_point(exit)
	graph.connect_points(start, entry_id)
	graph.connect_points(exit_id, finish)
	graph.connect_points(entry_id, exit_id, false)
	graph.special_costs[Vector2i(entry_id, exit_id)] = BotRules.current().navigation_link_cost
