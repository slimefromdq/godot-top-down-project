@tool
extends Area2D
class_name Bush

# Tall grass / shrub. Blocks no movement or shots, but it hides whoever is
# inside: CombatQueries.has_line_of_sight() can't see into a bush from outside
# it, and enemies hidden that way aren't drawn for the local player (see
# VisualsComponent). From inside you see out. When the local player is inside,
# the bush turns see-through so you can still see yourself.

const GROUP := &"bushes"

@export var radius: float = 110.0:
	set(value):
		radius = value
		_rebuild()
@export var color := Color("5f9e4c")
@export_range(0.0, 1.0) var opacity: float = 0.85
@export_range(0.0, 1.0) var opacity_with_player_inside: float = 0.4

var _shape_node: CollisionShape2D
var _player_inside := 0
# Every character body currently inside.
var _occupants: Array[Node2D] = []


func _ready() -> void:
	z_index = 20
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	add_to_group(GROUP)
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body.bind(1))
		body_exited.connect(_on_body.bind(-1))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var circle := CircleShape2D.new()
	circle.radius = radius * 0.8
	_shape_node.shape = circle
	queue_redraw()


func has_occupant(node: Node) -> bool:
	return _occupants.has(node)


func get_occupants() -> Array[Node2D]:
	return _occupants.filter(func(n): return is_instance_valid(n))


# Every bush `node` is standing in (usually zero or one).
static func bushes_of(node: Node) -> Array[Bush]:
	var result: Array[Bush] = []
	if not is_instance_valid(node) or not node.is_inside_tree():
		return result
	for bush in node.get_tree().get_nodes_in_group(GROUP):
		if bush is Bush and bush.has_occupant(node):
			result.append(bush)
	return result


func _on_body(body: Node2D, change: int) -> void:
	if change > 0:
		if not _occupants.has(body):
			_occupants.append(body)
	else:
		_occupants.erase(body)
	if body.is_in_group("player"):
		_player_inside = maxi(0, _player_inside + change)
		queue_redraw()


func _draw() -> void:
	var alpha := opacity_with_player_inside if _player_inside > 0 else opacity
	var fill := Color(color, alpha)
	var dark := Color(color.darkened(0.35), alpha)
	# Three overlapping blobs read as a clump rather than a perfect circle.
	var lobes := [Vector2(-0.35, 0.1), Vector2(0.3, -0.2), Vector2(0.15, 0.35)]
	for lobe: Vector2 in lobes:
		draw_circle(lobe * radius, radius * 0.72, dark)
	for lobe: Vector2 in lobes:
		draw_circle(lobe * radius + Vector2(-6, -8), radius * 0.62, fill)
