extends Node2D
class_name TrailRecorder

# Breadcrumbs of where an actor has been, for formations (StatusEffect
# compel_follow_trail). Lives on the APPLIER; created when the first
# follower joins, freed when the last one leaves.
#
# Followers get slots in order of joining (0 = right behind); when one
# leaves, those behind move up, so the line closes. A follower's target is
# the point on the path `spacing x (slot + 1)` pixels behind the applier,
# so the line takes the applier's turns instead of bunching up.
#
# Draws the parade line (dots along the path up to the last follower).

const NODE_NAME := &"TrailRecorder"
## Pixels between breadcrumbs.
const SAMPLE_SPACING := 8.0
## Extra path kept beyond the last follower.
const EXTRA_LENGTH := 200.0

@export var dot_color := Color(1.0, 0.85, 0.45, 0.55)
@export var dot_spacing := 28.0

var followers: Array[Node] = []
# Newest first. points[0] is the applier's latest recorded position.
var points: PackedVector2Array = []
var _max_spacing: float = 100.0


static func find_on(applier: Node) -> TrailRecorder:
	if applier == null or not is_instance_valid(applier):
		return null
	return applier.get_node_or_null(NodePath(NODE_NAME)) as TrailRecorder


static func join(applier: Node, follower: Node) -> void:
	if not applier is Node2D or not is_instance_valid(applier):
		return
	var recorder := find_on(applier)
	if recorder == null:
		recorder = TrailRecorder.new()
		recorder.name = NODE_NAME
		recorder.top_level = true    # draws in world space
		recorder.z_index = -4
		applier.add_child(recorder)
		recorder.points = PackedVector2Array([(applier as Node2D).global_position])
	if not recorder.followers.has(follower):
		recorder.followers.append(follower)


static func leave(applier: Node, follower: Node) -> void:
	var recorder := find_on(applier)
	if recorder == null:
		return
	recorder.followers.erase(follower)
	if recorder.followers.is_empty():
		recorder.queue_free()


func get_slot(follower: Node) -> int:
	return followers.find(follower)


# Where `follower` should stand: spacing x (slot + 1) px back along the path.
func get_follow_point(follower: Node, spacing: float) -> Vector2:
	_max_spacing = maxf(_max_spacing, spacing)
	var slot := maxi(get_slot(follower), 0)
	return point_behind(spacing * (slot + 1))


# The point `distance` px back along the path from the applier. If the path
# is shorter than that (she just started), extend it straight back.
func point_behind(distance: float) -> Vector2:
	var here := _applier_position()
	var previous := here
	var travelled := 0.0
	for p in points:
		var step := previous.distance_to(p)
		if travelled + step >= distance and step > 0.0:
			return previous.lerp(p, (distance - travelled) / step)
		travelled += step
		previous = p
	var back := _fallback_direction(previous, here)
	return previous + back * (distance - travelled)


func _physics_process(_delta: float) -> void:
	var here := _applier_position()
	if points.is_empty() or points[0].distance_to(here) >= SAMPLE_SPACING:
		points.insert(0, here)
	# Keep only as much path as the last follower needs.
	var keep := _max_spacing * (followers.size() + 1) + EXTRA_LENGTH
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
		if total > keep:
			points.resize(i + 1)
			break
	queue_redraw()


func _draw() -> void:
	if followers.is_empty():
		return
	var length := _max_spacing * followers.size()
	var d := dot_spacing
	while d <= length:
		draw_circle(point_behind(d), 5.0, dot_color)
		d += dot_spacing


func _applier_position() -> Vector2:
	var applier := get_parent() as Node2D
	return applier.global_position if applier != null else global_position


func _fallback_direction(from: Vector2, here: Vector2) -> Vector2:
	if points.size() >= 2:
		var tail := points[points.size() - 2].direction_to(points[points.size() - 1])
		if tail != Vector2.ZERO:
			return tail
	var applier := get_parent()
	var aim = applier.get(&"aim_direction") if applier != null else null
	if aim is Vector2 and aim != Vector2.ZERO:
		return -aim
	return (from - here).normalized() if from != here else Vector2.DOWN
