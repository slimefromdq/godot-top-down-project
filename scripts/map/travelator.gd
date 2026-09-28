extends Area2D
class_name Travelator

# A moving walkway: a belt along its local X that carries everyone standing
# on it at data.belt_speed. Walk with it to go fast, against it to crawl,
# stand still to ride. With data.belt_reverse_period it flips direction on
# MapClock (the match clock), easing through a stop over data.belt_flip_time,
# so its direction is part of the map's timing.
#
# It plugs into MovementComponent as a speed zone with a drift_velocity (no
# speed multiplier), so it works on anything with a MovementComponent: heroes,
# bots, neutral monsters. Airborne bodies (jump pads) aren't carried.

const GROUP := &"travelators"

@export var data: MapPieceData
@export var size := Vector2(900, 150)
@export var color := Color(0.45, 0.8, 0.95)
@export var cycle_offset: float = 0.0

## Speed zone interface: no speed change, just the carry.
var multiplier: float = 1.0
var drift_velocity := Vector2.ZERO
var _t := 0.0
var _belt := 0.0    # belt travel for drawing


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -9
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update()


func boost_velocity(velocity: Vector2) -> Vector2:
	return velocity


## -1..1: the belt's current direction and strength along local X.
func get_flow() -> float:
	if data.belt_reverse_period <= 0.0:
		return 1.0
	var t := MapClock.now(self) + cycle_offset
	var period := data.belt_reverse_period
	var p := fposmod(t, period * 2.0)
	var dir := 1.0 if p < period else -1.0
	# Ease through zero around each flip.
	var into := fposmod(t, period)
	var half := data.belt_flip_time * 0.5
	if half > 0.0:
		if into < half:
			return dir * (into / half)
		if into > period - half:
			return dir * ((period - into) / half)
	return dir


func _update() -> void:
	drift_velocity = global_transform.x.normalized() * data.belt_speed * get_flow()


func _physics_process(delta: float) -> void:
	_update()
	_t += delta
	_belt += data.belt_speed * get_flow() * delta
	if ScreenCull.is_near(self, size.length() * 0.5):
		queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	var movement := _movement_of(body)
	if movement != null:
		movement.add_speed_zone(self)


func _on_body_exited(body: Node2D) -> void:
	var movement := _movement_of(body)
	if movement != null:
		movement.remove_speed_zone(self)


static func _movement_of(body: Node) -> MovementComponent:
	if body is Actor:
		return body.movement_component
	var found := body.get_node_or_null(^"Components/MovementComponent")
	return found as MovementComponent


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect, color.darkened(0.55))
	var inner := rect.grow_individual(-8, -16, -8, -16)
	draw_rect(inner, color.darkened(0.2))
	# Moving slats.
	var spacing := 60.0
	var x := fposmod(_belt, spacing) - size.x / 2.0
	while x < size.x / 2.0:
		if x > inner.position.x:
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), color.darkened(0.4), 3.0)
		x += spacing
	# Direction arrows.
	var flow := get_flow()
	if absf(flow) > 0.05:
		var h := size.y * 0.22
		for i in 3:
			var cx := (i - 1) * size.x * 0.3
			var tip := Vector2(cx + signf(flow) * h, 0)
			var back := Vector2(cx - signf(flow) * h * 0.2, 0)
			draw_polyline(PackedVector2Array([back + Vector2(0, -h), tip, back + Vector2(0, h)]),
					Color(1, 1, 1, 0.35 + 0.5 * absf(flow)), 6.0, true)
	# Handrails.
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), color.lightened(0.3), 6.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, color.lightened(0.3), 6.0)
