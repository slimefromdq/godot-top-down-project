extends Node2D
class_name IslandArea

# The Mote Island itself: a small walled room far off the map (at
# MapEventRules.island_origin, in the same world so physics, projectiles and
# the camera just work). It holds:
#
#   walls        StaticBody2Ds on the WORLD layer: nobody leaves except through
#                the exit, and shots stop at them
#   entry        where visitors land
#   exit portal  the one way home besides the stay timer (an interactable)
#   cache        cache_point(i): where the cache's Motes sit
#
# It is an open room: anyone who came through the portal is in it together and
# can fight. All the rules (who is inside, the stay timer, the cache) are the
# IslandDirector's; this node only owns the geometry and the drawing.

const GROUP := &"island_area"
const WALL_THICKNESS := 240.0

var rules: MapEventRules
var _size := Vector2(1500, 1000)
var _t := 0.0
var exit_portal: IslandExit


func _enter_tree() -> void:
	add_to_group(GROUP)


func setup(p_rules: MapEventRules) -> void:
	rules = p_rules
	_size = rules.island_size
	global_position = rules.island_origin
	_build_walls()
	exit_portal = IslandExit.new()
	exit_portal.name = "IslandExit"
	exit_portal.position = exit_position()
	add_child(exit_portal)


func entry_position() -> Vector2:
	return global_position + Vector2(0, _size.y * 0.32)


## Local to the area (the exit portal is its child).
func exit_position() -> Vector2:
	return Vector2(0, -_size.y * 0.34)


func contains(point: Vector2) -> bool:
	return Rect2(global_position - _size / 2.0 - Vector2(WALL_THICKNESS, WALL_THICKNESS),
		_size + Vector2(WALL_THICKNESS, WALL_THICKNESS) * 2.0).has_point(point)


## Where cache Mote `i` of `count` sits (a ring inside the room).
func cache_point(i: int, count: int) -> Vector2:
	var angle := TAU * (i + 0.5) / maxf(count, 1.0) - PI / 2.0
	var half := _size / 2.0 * rules.island_cache_spread
	return global_position + Vector2(cos(angle) * half.x, sin(angle) * half.y * 0.8)


## A spot near the entry for the n-th visitor (they don't stack).
func landing_point(n: int) -> Vector2:
	var offset := Vector2.from_angle(n * 2.4) * (40.0 * mini(n, 6))
	return entry_position() + offset


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = MapLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var half := _size / 2.0
	var t := WALL_THICKNESS
	for rect in [
		Rect2(-half.x - t, -half.y - t, _size.x + t * 2.0, t),    # top
		Rect2(-half.x - t, half.y, _size.x + t * 2.0, t),         # bottom
		Rect2(-half.x - t, -half.y, t, _size.y),                  # left
		Rect2(half.x, -half.y, t, _size.y),                       # right
	]:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.position + rect.size / 2.0
		body.add_child(shape)


func _process(delta: float) -> void:
	_t += delta
	if rules != null and ScreenCull.is_near(self, maxf(_size.x, _size.y)):
		queue_redraw()


func _draw() -> void:
	if rules == null:
		return
	var half := _size / 2.0
	var t := WALL_THICKNESS
	draw_rect(Rect2(-half - Vector2(t, t), _size + Vector2(t, t) * 2.0), Color("1a1033"))
	draw_rect(Rect2(-half, _size), Color("2b1d55"))
	draw_rect(Rect2(-half, _size), Color("a78bfa"), false, 8.0)
	# Soft drifting lights.
	for i in 14:
		var p := Vector2(sin(i * 12.9 + _t * 0.15) * half.x * 0.9, cos(i * 7.3 + _t * 0.12) * half.y * 0.9)
		draw_circle(p, 10.0 + 6.0 * sin(_t + i), Color(0.8, 0.7, 1.0, 0.12))
	draw_arc(Vector2.ZERO, minf(half.x, half.y) * 0.6, 0.0, TAU, 64, Color(0.8, 0.7, 1.0, 0.12), 6.0, true)
