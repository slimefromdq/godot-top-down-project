@tool
extends Area2D
class_name JumpPad

# Step on it and you are launched in an arc to a fixed landing spot.
#
# The landing spot is `landing_offset`, in the pad's local space (rotate or move
# the pad and the landing spot follows). Every launch lands on exactly the same
# spot no matter where on the pad you stepped, so you can learn and predict it.
# Both ends are always drawn: the landing ring warns defenders where you'll be.
#
# The flight itself is Actor.launch(): a timed forced move that ignores low
# cover and ledges (that's how a pad can take you UP a cliff).

@export var landing_offset := Vector2(800, 0):
	set(value):
		landing_offset = value
		queue_redraw()
## Seconds in the air. Longer = floatier and easier to shoot out of the sky.
@export_range(0.2, 2.0, 0.05) var air_time: float = 0.7
## Visual peak height of the arc, in pixels.
@export var arc_height: float = 160.0
@export var radius: float = 80.0:
	set(value):
		radius = value
		_rebuild()
@export var color := Color("f59e0b")
@export var launch_effect: PackedScene = preload("res://effects/dash_puff.tscn")
@export var launch_sound: SoundCue = preload("res://resources/audio/sfx/dash.tres")

var _shape_node: CollisionShape2D
var _time: float = 0.0
var _bounce: float = 0.0


func _ready() -> void:
	z_index = -8
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func get_landing_position() -> Vector2:
	return to_global(landing_offset)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape_node.shape = circle
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_bounce = maxf(0.0, _bounce - delta * 3.0)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body is Actor:
		return
	var actor := body as Actor
	if actor.is_airborne() or actor.health_component.is_dead():
		return
	actor.launch(get_landing_position(), air_time, arc_height)
	_bounce = 1.0
	EffectSpawner.spawn(self, launch_effect, {
		"position": global_position,
		"direction": (get_landing_position() - global_position).normalized(),
	})
	AudioManager.play_sfx(launch_sound, global_position)


func _draw() -> void:
	# Flight path: a dotted arc bulging "up" (toward -Y on screen) to the landing ring.
	var end := landing_offset
	var lift := Vector2(0, -minf(end.length() * 0.25, 260.0))
	var dots := int(end.length() / 60.0)
	var dash_phase := fmod(_time * 1.5, 1.0)
	for i in dots:
		var t := (i + dash_phase) / dots
		var point := end * t + lift * 4.0 * t * (1.0 - t)
		draw_circle(point, 7.0, Color(color, 0.55))

	# Landing ring.
	draw_arc(end, radius * 0.9, 0, TAU, 40, Color(color, 0.8), 5.0)
	draw_arc(end, radius * 0.45, 0, TAU, 24, Color(color, 0.5), 3.0)

	# The pad: squashes when it fires, and a pulsing ring invites you on.
	var squash := 1.0 - 0.18 * _bounce
	draw_circle(Vector2.ZERO, radius * squash, color.darkened(0.45))
	draw_circle(Vector2.ZERO, radius * 0.82 * squash, color)
	var pulse := fmod(_time * 0.8, 1.0)
	draw_arc(Vector2.ZERO, radius * (0.5 + 0.7 * pulse), 0, TAU, 40, Color(color.lightened(0.4), 1.0 - pulse), 4.0)
	# Chevrons aim along the launch direction.
	var direction := end.normalized()
	var side := direction.orthogonal()
	for k in 2:
		var tip := direction * (radius * (0.1 + 0.35 * k))
		var back := tip - direction * radius * 0.3
		draw_polyline(PackedVector2Array([back + side * radius * 0.3, tip, back - side * radius * 0.3]),
			Color.WHITE, 6.0, true)
