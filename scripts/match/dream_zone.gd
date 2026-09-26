extends Area2D
class_name DreamZone

# One half of a mirrored dreaming-zone pair (both Glades, both Driftfields
# ...). The MoteDirector picks a pair and runs both halves together:
# warning (fading in), dreaming (Motes spawn fast at this zone's Marker2D
# children), then off again.
#
# The shape is the CollisionPolygon2D child; exported from the Dream Basin
# pipeline (tools/dream_basin/layout.py). Placeholder look: a soft tint with
# a shimmering edge while warning or dreaming. M4 makes it pretty.

enum ZoneState { OFF, WARNING, DREAMING }

const GROUP := &"dream_zone"

## Both halves of a pair share this id (e.g. &"glade").
@export var pair_id: StringName
@export var display_name: String = ""
@export var tint := Color(0.78, 0.6, 1.0, 0.3)

var zone_state: ZoneState = ZoneState.OFF
var _t := 0.0
var _polygon := PackedVector2Array()


func _ready() -> void:
	add_to_group(GROUP)
	monitoring = false
	monitorable = false
	for child in get_children():
		if child is CollisionPolygon2D:
			_polygon = child.polygon
	z_index = -1


func get_spawn_points() -> Array[Node2D]:
	var points: Array[Node2D] = []
	for child in get_children():
		if child is Marker2D:
			points.append(child)
	return points


func set_zone_state(value: ZoneState) -> void:
	zone_state = value
	queue_redraw()


func contains(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(point), _polygon)


func _process(delta: float) -> void:
	if zone_state != ZoneState.OFF:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if zone_state == ZoneState.OFF or _polygon.size() < 3:
		return
	var strength := 0.45 + 0.15 * sin(_t * 2.0) if zone_state == ZoneState.WARNING else 1.0
	draw_colored_polygon(_polygon, Color(tint, tint.a * strength))
	var edge := Color.from_hsv(fmod(0.75 + 0.1 * sin(_t), 1.0), 0.35, 1.0, 0.6 * strength)
	draw_polyline(_polygon + PackedVector2Array([_polygon[0]]), edge, 10.0 + 4.0 * sin(_t * 3.0))
