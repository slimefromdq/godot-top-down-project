extends RefCounted
class_name BotNavigation

## One obstacle graph per map, shared by every bot. Ordinary edges are
## walkable grid segments. Map jump pads and teleporters add directed edges
## that cost BotRules.navigation_link_cost.
##
## The search runs entirely in the engine (no script cost callbacks: those
## made every path ~15x slower). Costs are distance x the target point's
## weight_scale. Every point weighs `cost_scale`, and a link's exit point is
## weighted so crossing the link costs navigation_link_cost x cost_scale.
## cost_scale is large enough that the engine's straight-line heuristic
## never overestimates, even across the longest shortcut, so routes are
## still the cheapest ones.
##
## Toggle gates (ToggleGate) are left out of the obstacle scan, so the graph
## runs through their doorways; every path() call then switches off the
## points in each closed gate's doorway, so bots route around closed gates
## and through open ones.


static var _shared: Dictionary = {}

var map: GameMap
var graph := AStar2D.new()
## Multiplies every cost (see above).
var cost_scale: float = 1.0
var cells: Dictionary = {}  # Vector2i -> graph point id
var teleport_entries: Dictionary = {}  # entrance position -> exit position
var origin: Vector2
var width: int
var height: int
var cell_size: float
var _next_id: int = 1
var _gate_points: Dictionary = {}  # ToggleGate -> PackedInt32Array of point ids
var _excluded: Array[RID] = []
var _shape := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()


static func for_actor(actor: Hero) -> BotNavigation:
	return for_node(actor)


## The map's graph for any node in the tree (the Wanderer plans its escape on it).
static func for_node(actor: Node) -> BotNavigation:
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
	_sync_gates()
	var start := _nearest(from)
	var finish := _nearest(to)
	if start == 0 or finish == 0:
		return PackedVector2Array()
	var result := graph.get_point_path(start, finish)
	if not result.is_empty() and _edge_clear(result[result.size() - 1], to):
		result.append(to)
	return result


## How many graph points lie within `hops` steps of `point`: a dead end or a
## narrow pocket has few, an open lane or a plaza has many. 0 = off the graph.
func openness_at(point: Vector2, hops: int) -> int:
	var start := _nearest(point)
	if start == 0:
		return 0
	var seen := {start: true}
	var frontier: Array[int] = [start]
	for _hop in hops:
		var next: Array[int] = []
		for id in frontier:
			for neighbour in graph.get_point_connections(id):
				if not seen.has(neighbour) and not graph.is_point_disabled(neighbour):
					seen[neighbour] = true
					next.append(neighbour)
		frontier = next
	return seen.size()


## The graph point nearest to `point` (Vector2.INF if none is close).
func nearest_position(point: Vector2) -> Vector2:
	var id := _nearest(point)
	return graph.get_point_position(id) if id != 0 else Vector2.INF


func _build() -> void:
	var rules := BotRules.current()
	cell_size = rules.navigation_cell_size
	_shape.radius = rules.navigation_actor_radius
	_query.shape = _shape
	_query.collision_mask = MapLayers.WALK_BLOCKERS
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	for gate in map.get_tree().get_nodes_in_group(ToggleGate.GROUP):
		if map.is_ancestor_of(gate):
			_excluded.append(gate.get_rid())
	_query.exclude = _excluded
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
	_apply_weights()
	_find_gate_points()


func _find_gate_points() -> void:
	var margin := _shape.radius
	for gate in map.get_tree().get_nodes_in_group(ToggleGate.GROUP):
		if not map.is_ancestor_of(gate):
			continue
		var polygon: PackedVector2Array = gate.get_block_polygon()
		var grown := Geometry2D.offset_polygon(polygon, margin)
		var area: PackedVector2Array = grown[0] if not grown.is_empty() else polygon
		var ids := PackedInt32Array()
		for id in graph.get_point_ids():
			if Geometry2D.is_point_in_polygon(graph.get_point_position(id), area):
				ids.append(id)
		_gate_points[gate] = ids


func _sync_gates() -> void:
	for gate in _gate_points:
		if not is_instance_valid(gate):
			continue
		var closed_now: bool = gate.is_closed()
		for id in _gate_points[gate]:
			if graph.is_point_disabled(id) != closed_now:
				graph.set_point_disabled(id, closed_now)


## Point ids a gate switches off while closed (tests, the bot overlay).
func get_gate_points(gate: Node) -> PackedInt32Array:
	return _gate_points.get(gate, PackedInt32Array())


# [entry id, exit id] of every link, for _apply_weights.
var _links: Array[Vector2i] = []


func _apply_weights() -> void:
	var link_cost := maxf(BotRules.current().navigation_link_cost, 1.0)
	cost_scale = 1.0
	for link in _links:
		var span := graph.get_point_position(link.x).distance_to(graph.get_point_position(link.y))
		cost_scale = maxf(cost_scale, span / link_cost)
	for id in graph.get_point_ids():
		graph.set_point_weight_scale(id, cost_scale)
	for link in _links:
		var span := graph.get_point_position(link.x).distance_to(graph.get_point_position(link.y))
		if span > 0.0:
			graph.set_point_weight_scale(link.y, link_cost * cost_scale / span)


func _point(cell: Vector2i) -> Vector2:
	return origin + Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5


func _clear(point: Vector2) -> bool:
	_query.transform = Transform2D(0.0, point)
	return map.get_world_2d().direct_space_state.intersect_shape(_query, 1).is_empty()


func _edge_clear(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, _query.collision_mask, _excluded)
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
			if id == 0 or graph.is_point_disabled(id):
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
	# One way, so only the link itself pays the exit point's weight.
	graph.connect_points(exit_id, finish, false)
	graph.connect_points(entry_id, exit_id, false)
	_links.append(Vector2i(entry_id, exit_id))
