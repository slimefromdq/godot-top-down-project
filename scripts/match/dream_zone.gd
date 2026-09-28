extends Area2D
class_name DreamZone

# One half of a mirrored dreaming-zone pair (both Glades, both Driftfields
# ...). The MoteDirector picks a pair and runs both halves together:
# warning (fading in), dreaming (Motes spawn fast at this zone's Marker2D
# children), then off again.
#
# The shape is the CollisionPolygon2D child; exported from the Dream Basin
# pipeline (tools/dream_basin/layout.py). Look: during the warning the tint
# fades in; while dreaming the ground is tinted, the edge shimmers through
# pastel hues and petals drift across; when it ends it fades back out.

enum ZoneState { OFF, WARNING, DREAMING }

const GROUP := &"dream_zone"

## Both halves of a pair share this id (e.g. &"glade").
@export var pair_id: StringName
@export var display_name: String = ""
@export var tint := Color(0.78, 0.6, 1.0, 0.3)

var zone_state: ZoneState = ZoneState.OFF
var _t := 0.0
var _polygon := PackedVector2Array()
var _bounds := Rect2()
# 0..1: how far the look has faded in (up during warning/dreaming, down off).
var _presence: float = 0.0
var _fade_in_time: float = 1.0
# Petals: [position (local), phase]
var _petals: Array = []

const PETALS := 26
const FADE_OUT := 1.5


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"minimap_areas")
	monitoring = false
	monitorable = false
	for child in get_children():
		if child is CollisionPolygon2D:
			_polygon = child.polygon
	z_index = -1
	if _polygon.size() >= 3:
		_bounds = Rect2(_polygon[0], Vector2.ZERO)
		for p in _polygon:
			_bounds = _bounds.expand(p)
	for i in PETALS:
		_petals.append([_bounds.position + Vector2(randf() * _bounds.size.x, randf() * _bounds.size.y), randf() * TAU])


func get_spawn_points() -> Array[Node2D]:
	var points: Array[Node2D] = []
	for child in get_children():
		if child is Marker2D:
			points.append(child)
	return points


## `fade_in`: seconds for the look to fade in (the warning's length).
func set_zone_state(value: ZoneState, fade_in: float = 1.0) -> void:
	zone_state = value
	if value == ZoneState.WARNING:
		_fade_in_time = maxf(fade_in, 0.1)
	queue_redraw()


func contains(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(point), _polygon)


func _process(delta: float) -> void:
	match zone_state:
		ZoneState.WARNING:
			_presence = minf(_presence + delta / _fade_in_time, 0.6)
		ZoneState.DREAMING:
			_presence = minf(_presence + delta / 0.5, 1.0)
		_:
			_presence = maxf(_presence - delta / FADE_OUT, 0.0)
	if _presence <= 0.0:
		return
	_t += delta
	if zone_state == ZoneState.DREAMING or _presence > 0.0:
		for petal in _petals:
			petal[0] += Vector2(38.0, 22.0 + 12.0 * sin(_t + petal[1])) * delta
			if not _bounds.has_point(petal[0]):
				petal[0] = Vector2(_bounds.position.x + randf() * _bounds.size.x * 0.5, _bounds.position.y + randf() * _bounds.size.y) \
					if randf() < 0.5 else Vector2(_bounds.position.x + randf() * _bounds.size.x, _bounds.position.y)
	if ScreenCull.is_near(self, _bounds.get_center().length() + _bounds.size.length()):
		queue_redraw()


## The minimap tints this area while it dreams (group "minimap_areas").
func get_minimap_polygon() -> PackedVector2Array:
	return global_transform * _polygon


func get_presence() -> float:
	return _presence


func _draw() -> void:
	if _presence <= 0.0 or _polygon.size() < 3:
		return
	var strength := _presence * (0.85 + 0.15 * sin(_t * 2.0))
	draw_colored_polygon(_polygon, Color(tint, tint.a * strength))
	# Shimmering edge: a pastel band drifting through hues, doubled soft.
	var closed := _polygon + PackedVector2Array([_polygon[0]])
	var edge := Color.from_hsv(fmod(0.75 + 0.12 * sin(_t * 0.7), 1.0), 0.35, 1.0, 0.6 * strength)
	draw_polyline(closed, Color(edge, edge.a * 0.35), 34.0 + 8.0 * sin(_t * 2.0))
	draw_polyline(closed, edge, 10.0 + 4.0 * sin(_t * 3.0))
	# Petals drifting across (only while dreaming; they fade with it).
	var petal_alpha := _presence if zone_state != ZoneState.WARNING else _presence * 0.4
	for petal in _petals if VisualToggles.is_on(&"zone_petals") else []:
		var at: Vector2 = petal[0]
		if not Geometry2D.is_point_in_polygon(at, _polygon):
			continue
		var spin: float = _t * 1.5 + petal[1]
		draw_set_transform(at, spin, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 11.0, Color(1.0, 0.82, 0.92, 0.75 * petal_alpha))
		draw_circle(Vector2(3, -2), 5.0, Color(1, 1, 1, 0.6 * petal_alpha))
	draw_set_transform(Vector2.ZERO)
