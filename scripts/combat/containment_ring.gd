extends StaticBody2D
class_name ContainmentRing

# A ring-shaped wall (Pike's "Only Us"). For its duration nothing crosses its
# edge in either direction:
#   * walking, dashes, charges, carries: it's a static body on the BARRIERS
#     layer, which every character collides with (Actor/TrainingDummy add it
#     to their mask; launches only drop LOW_COVER/LEDGES, so they stop too)
#   * projectiles: BARRIERS is in GameRules.wall_mask
#   * teleports: Actor.teleport_to() asks crosses_any() and refuses
# Sight and bushes aren't affected. Area damage centred outside can still
# reach inside (area hits ignore walls in general).
#
# members are the actors it closes around; anyone else inside when it forms
# is pushed just outside. It ends early if a member dies or is removed.
# Signal: ended.

signal ended

const GROUP := &"containment_rings"
## How far outside the edge a pushed-out actor is put.
const PUSH_MARGIN := 60.0

var radius: float = 450.0
var duration: float = 4.0
var members: Array[Node2D] = []
var color := Color(1.0, 0.45, 0.7, 0.9)

var _age: float = 0.0
var _ended := false


static func spawn(context: Node, center: Vector2, ring_radius: float, ring_duration: float,
		ring_members: Array, ring_color: Color = Color(1.0, 0.45, 0.7, 0.9)) -> ContainmentRing:
	var ring := ContainmentRing.new()
	ring.radius = ring_radius
	ring.duration = ring_duration
	ring.color = ring_color
	for member in ring_members:
		if member is Node2D:
			ring.members.append(member)
	ring.position = center
	context.get_tree().current_scene.add_child(ring)
	ring.global_position = center
	return ring


# True if a straight move from -> to would cross any live ring's edge.
static func crosses_any(tree: SceneTree, from: Vector2, to: Vector2) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(GROUP):
		var ring := node as ContainmentRing
		if ring != null and not ring._ended and ring.is_inside(from) != ring.is_inside(to):
			return true
	return false


func is_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) < radius


func get_time_left() -> float:
	return maxf(duration - _age, 0.0)


func has_ended() -> bool:
	return _ended


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = MapLayers.BARRIERS
	collision_mask = 0
	z_index = 4
	var shape := CollisionShape2D.new()
	var segments := ConcavePolygonShape2D.new()
	var points := PackedVector2Array()
	var count := maxi(24, int(TAU * radius / 40.0))
	for i in count:
		points.append(Vector2.RIGHT.rotated(TAU * i / count) * radius)
		points.append(Vector2.RIGHT.rotated(TAU * (i + 1) / count) * radius)
	segments.segments = points
	shape.shape = segments
	add_child(shape)
	_push_out_strangers()


func end() -> void:
	if _ended:
		return
	_ended = true
	ended.emit()
	queue_free()


func _physics_process(delta: float) -> void:
	if _ended:
		return
	_age += delta
	for member in members:
		if StatusEffectComponent.is_actor_gone(member):
			end()
			return
	if _age >= duration:
		end()
		return
	queue_redraw()


# Anyone inside who isn't a member goes just outside the edge, straight out.
func _push_out_strangers() -> void:
	for node in get_tree().get_nodes_in_group(&"minimap_units"):
		var body := node as Node2D
		if body == null or members.has(body) or StatusEffectComponent.is_actor_gone(body):
			continue
		if not is_inside(body.global_position):
			continue
		var out := global_position.direction_to(body.global_position)
		if out == Vector2.ZERO:
			out = Vector2.RIGHT
		body.global_position = global_position + out * (radius + PUSH_MARGIN)
		if body is CharacterBody2D:
			body.velocity = Vector2.ZERO


func _draw() -> void:
	var fade := clampf(get_time_left() / 0.5, 0.0, 1.0) if duration > 0.0 else 1.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(color, color.a * fade), 8.0, true)
	draw_arc(Vector2.ZERO, radius - 14.0, 0.0, TAU, 96, Color(color, color.a * 0.35 * fade), 3.0, true)
