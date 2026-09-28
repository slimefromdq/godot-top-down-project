@tool
extends Area2D
class_name Bush

# Tall grass / shrub. Blocks no movement or shots, but it hides whoever is
# inside: CombatQueries.has_line_of_sight() can't see into a bush from outside
# it, and enemies hidden that way aren't drawn for the local player (see
# VisualsComponent). From inside you see out. When the local player is inside,
# the bush turns see-through so you can still see yourself.
#
# Grass patch: set `polygon` (3+ points, local) and it becomes a patch of tall
# grass of that shape instead of a round shrub; same rules. Hidden people
# still show to an enemy within GameRules.grass_reveal_radius, and to
# everyone for GameRules.grass_fire_reveal_time after they use an ability
# (shooting included: note_fired). See CombatQueries.

const GROUP := &"bushes"

@export var radius: float = 110.0:
	set(value):
		radius = value
		_rebuild()
## A grass patch's outline (local). Empty = a round shrub of `radius`.
@export var polygon := PackedVector2Array():
	set(value):
		polygon = value
		_rebuild()
@export var color := Color("5f9e4c")
@export_range(0.0, 1.0) var opacity: float = 0.85
@export_range(0.0, 1.0) var opacity_with_player_inside: float = 0.4
## Presentation: when a body walks in or out, the leaves part away from it
## this far (px) and spring back over rustle_time seconds.
@export var rustle_amount: float = 16.0
@export var rustle_time: float = 0.6

var _shape_node: CollisionShape2D
var _polygon_node: CollisionPolygon2D
var _player_inside := 0
# Every character body currently inside.
var _occupants: Array[Node2D] = []
# Rustle: seconds left, and where (local) the body that set it off stood.
var _rustle_left := 0.0
var _rustle_from := Vector2.ZERO
# Body instance id -> the bushes it's in, kept by _on_body so bushes_of()
# (asked for every sight check and every drawn actor, every frame) doesn't
# scan every bush on the map.
static var _by_body: Dictionary = {}
static var _none: Array[Bush] = []
# Body instance id -> msec it last fired (note_fired).
static var _fired_msec: Dictionary = {}


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
	set_process(false)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	if _polygon_node == null:
		_polygon_node = CollisionPolygon2D.new()
		add_child(_polygon_node)
	var patch := is_patch()
	_shape_node.disabled = patch
	_polygon_node.disabled = not patch
	_polygon_node.polygon = polygon if patch else PackedVector2Array()
	var circle := CircleShape2D.new()
	circle.radius = radius * 0.8
	_shape_node.shape = circle
	queue_redraw()


func is_patch() -> bool:
	return polygon.size() >= 3


## How far the drawing reaches from the origin (for culling).
func get_reach() -> float:
	if not is_patch():
		return radius
	var reach := 0.0
	for point in polygon:
		reach = maxf(reach, point.length())
	return reach


## `actor` just used an ability (shot, cast): anyone can see it in grass for
## GameRules.grass_fire_reveal_time.
static func note_fired(actor: Node) -> void:
	if is_instance_valid(actor):
		_fired_msec[actor.get_instance_id()] = Time.get_ticks_msec()


## Fired recently enough that grass doesn't hide it.
static func is_exposed(actor: Node) -> bool:
	if not is_instance_valid(actor):
		return false
	var at: int = _fired_msec.get(actor.get_instance_id(), -1)
	return at >= 0 and Time.get_ticks_msec() - at <= GameRules.current().grass_fire_reveal_time * 1000.0


func has_occupant(node: Node) -> bool:
	return _occupants.has(node)


func get_occupants() -> Array[Node2D]:
	return _occupants.filter(func(n): return is_instance_valid(n))


# Every bush `node` is standing in (usually zero or one). Read-only: don't
# change the array.
static func bushes_of(node: Node) -> Array[Bush]:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return _none
	return _by_body.get(node.get_instance_id(), _none)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	for body in _occupants:
		if is_instance_valid(body):
			_unindex(body)
	_occupants.clear()
	_player_inside = 0


func _unindex(body: Node) -> void:
	var id := body.get_instance_id()
	var list: Array = _by_body.get(id, [])
	list.erase(self)
	if list.is_empty():
		_by_body.erase(id)


func _on_body(body: Node2D, change: int) -> void:
	if change > 0:
		if not _occupants.has(body):
			_occupants.append(body)
			var id := body.get_instance_id()
			if not _by_body.has(id):
				var list: Array[Bush] = []
				_by_body[id] = list
			_by_body[id].append(self)
	else:
		_occupants.erase(body)
		_unindex(body)
	if body.is_in_group("player"):
		_player_inside = maxi(0, _player_inside + change)
		queue_redraw()
	if is_instance_valid(body) and body.is_inside_tree():
		rustle(to_local(body.global_position))


## Parts the leaves away from `from_local` (a point in this bush's space).
func rustle(from_local: Vector2) -> void:
	if rustle_time <= 0.0 or rustle_amount <= 0.0 or not VisualToggles.is_on(&"bush_rustle"):
		return
	_rustle_left = rustle_time
	_rustle_from = from_local
	set_process(true)


func is_rustling() -> bool:
	return _rustle_left > 0.0


func _process(delta: float) -> void:
	_rustle_left = maxf(0.0, _rustle_left - delta)
	if _rustle_left <= 0.0:
		set_process(false)
	if ScreenCull.is_near(self, get_reach()):
		queue_redraw()


# How far a lobe at `at` is pushed right now: away from the rustle, springing
# back with a small wobble.
func _rustle_offset(at: Vector2) -> Vector2:
	if _rustle_left <= 0.0:
		return Vector2.ZERO
	var k := _rustle_left / rustle_time
	var away := at - _rustle_from
	var dir := away.normalized() if away.length() > 1.0 else Vector2.UP
	return dir * rustle_amount * k * cos((1.0 - k) * TAU * 1.5)


func _draw() -> void:
	var alpha := opacity_with_player_inside if _player_inside > 0 else opacity
	var fill := Color(color, alpha)
	var dark := Color(color.darkened(0.35), alpha)
	if is_patch():
		_draw_patch(fill, dark)
		return
	# Three overlapping blobs read as a clump rather than a perfect circle.
	var lobes := [Vector2(-0.35, 0.1), Vector2(0.3, -0.2), Vector2(0.15, 0.35)]
	# Fifteen circles as one mesh: one draw call per bush.
	var batch := ShapeBatch.new()
	for lobe: Vector2 in lobes:
		var at := lobe * radius
		batch.draw_circle(at + _rustle_offset(at), radius * 0.72, dark)
	for lobe: Vector2 in lobes:
		var at := lobe * radius
		AeroDraw.gloss_circle(batch, at + _rustle_offset(at) + Vector2(-6, -8), radius * 0.62, fill)
	batch.draw_on(self)


# A grass patch: a soft green field, a ragged darker edge, and rows of blade
# tufts (they part around a rustle), so it reads as "tall grass you can
# walk into" and never as a wall.
func _draw_patch(fill: Color, dark: Color) -> void:
	var batch := ShapeBatch.new()
	batch.draw_colored_polygon(polygon, dark)
	for inner: PackedVector2Array in Geometry2D.offset_polygon(polygon, -14.0):
		batch.draw_colored_polygon(inner, fill)
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	var blade := Color(color.lightened(0.3), fill.a)
	var step := 46.0
	var row := 0
	var y := rect.position.y + step * 0.5
	while y < rect.end.y:
		var x := rect.position.x + step * (0.25 if row % 2 == 0 else 0.75)
		while x < rect.end.x:
			var at := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(at, polygon):
				var tip := at + _rustle_offset(at)
				batch.draw_line(at + Vector2(-9, 10), tip + Vector2(-3, -12), blade, 3.0)
				batch.draw_line(at + Vector2(0, 10), tip + Vector2(1, -16), dark, 3.0)
				batch.draw_line(at + Vector2(9, 10), tip + Vector2(5, -11), blade, 3.0)
			x += step
		y += step * 0.8
		row += 1
	batch.draw_on(self)
