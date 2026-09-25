@tool
extends Area2D
class_name SpeedStrip

# A strip of fast ground ("Lamplight Road"). While you stand on it, the part of
# your movement along the strip's axis (local X, either direction) is
# multiplied. Moving across it is unaffected, so it only speeds up travel
# along the road.
#
# The strip doesn't touch velocity itself. It registers with the actor's
# MovementComponent, which calls boost_velocity() on the target velocity every
# frame. Any node with boost_velocity() and `multiplier` can do the same, e.g.
# a slowing swamp with multiplier < 1.

@export var size := Vector2(900, 170):
	set(value):
		size = value
		_rebuild()
@export_range(0.25, 3.0, 0.05) var multiplier: float = 1.6
@export var color := Color("fcd34d")

var _shape_node: CollisionShape2D
var _time: float = 0.0


func _ready() -> void:
	z_index = -9
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


func boost_velocity(velocity: Vector2) -> Vector2:
	var axis := global_transform.x.normalized()
	return velocity + axis * velocity.dot(axis) * (multiplier - 1.0)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Actor:
		body.movement_component.add_speed_zone(self)


func _on_body_exited(body: Node2D) -> void:
	if body is Actor:
		body.movement_component.remove_speed_zone(self)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, Color(color, 0.55))
	draw_rect(rect, color.darkened(0.4), false, 5.0)
	# Chevrons stream outward in both directions: "fast both ways".
	var h := size.y * 0.3
	var spacing := 120.0
	var offset := fmod(_time * 240.0, spacing)
	var x := offset
	while x < size.x / 2.0 - 20.0:
		for sign_x in [-1.0, 1.0]:
			var tip := Vector2(x * sign_x, 0)
			var back := tip - Vector2(sign_x * h, 0)
			var alpha := 1.0 - x / (size.x / 2.0)
			draw_polyline(PackedVector2Array([back + Vector2(0, -h), tip, back + Vector2(0, h)]),
				Color(color.darkened(0.5), alpha), 6.0, true)
		x += spacing
