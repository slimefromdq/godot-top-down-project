@tool
extends Area2D
class_name Bush

# Tall grass / shrub. Blocks nothing: it only draws over characters. When the
# local player is inside, it turns see-through so you can still see yourself.

@export var radius: float = 110.0:
	set(value):
		radius = value
		_rebuild()
@export var color := Color("5f9e4c")
@export_range(0.0, 1.0) var opacity: float = 0.85
@export_range(0.0, 1.0) var opacity_with_player_inside: float = 0.4

var _shape_node: CollisionShape2D
var _player_inside := 0


func _ready() -> void:
	z_index = 20
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
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


func _on_body(body: Node2D, change: int) -> void:
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
