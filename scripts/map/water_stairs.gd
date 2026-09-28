extends Area2D
class_name WaterStairs

# A stepped water cascade (the Fountain Courts): shallow water running down a
# flight of wide steps along local +X. Going down it you're quicker
# (data.stairs_down_multiplier on the part of your movement along the
# cascade), climbing it you're slower (data.stairs_up_multiplier); crossing
# it sideways is unaffected. Standing still does nothing (no carry: that's a
# Travelator).
#
# It's a MovementComponent speed zone (boost_velocity), like SpeedStrip, so
# it works on heroes, bots and neutral monsters alike.

const GROUP := &"water_stairs"

@export var data: MapPieceData
@export var size := Vector2(560, 180)
@export var color := Color(0.55, 0.82, 0.95)

## Speed zone interface: no acceleration change.
var multiplier: float = 1.0
var _t := 0.0


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


func boost_velocity(velocity: Vector2) -> Vector2:
	var axis := global_transform.x.normalized()
	var along := velocity.dot(axis)
	var mult := data.stairs_down_multiplier if along > 0.0 else data.stairs_up_multiplier
	return velocity + axis * along * (mult - 1.0)


func _on_body_entered(body: Node2D) -> void:
	var movement := Travelator._movement_of(body)
	if movement != null:
		movement.add_speed_zone(self)


func _on_body_exited(body: Node2D) -> void:
	var movement := Travelator._movement_of(body)
	if movement != null:
		movement.remove_speed_zone(self)


func _process(delta: float) -> void:
	_t += delta
	if ScreenCull.is_near(self, size.length() * 0.5):
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	draw_rect(rect.grow(10), Color(0.85, 0.83, 0.9))    # stone kerb
	var steps := 6
	var step_w := size.x / steps
	for i in steps:
		# Each step a shade deeper going down, like water pooling lower.
		var x := rect.position.x + i * step_w
		var water := color.darkened(0.06 * i)
		draw_rect(Rect2(x, rect.position.y, step_w, size.y), water)
		# The lip of each step, with water spilling over it.
		draw_line(Vector2(x + step_w, rect.position.y), Vector2(x + step_w, rect.end.y), Color(1, 1, 1, 0.75), 3.0)
		var spill := fmod(_t * 1.4 + i * 0.37, 1.0)
		for j in 3:
			var y := rect.position.y + size.y * (j + 0.5) / 3.0
			draw_line(Vector2(x + step_w * spill, y - 6), Vector2(x + step_w * spill + 14, y - 6),
				Color(1, 1, 1, 0.5 * (1.0 - spill)), 2.0)
	# Pool at the bottom.
	draw_rect(Rect2(rect.end.x - 8, rect.position.y, 16, size.y), color.darkened(0.45))
