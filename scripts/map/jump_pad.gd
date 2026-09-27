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
# cover and ledges (that's how a pad can take you UP a cliff). Carried Motes
# add MatchRules.heavy_pockets_air_time each (MoteCarrier.extra_air_time).
#
# Placed pads (JumpPad.place(), e.g. a hero's trampoline) add a few runtime
# rules; a map pad leaves them at their defaults and behaves as always:
#   owner_actor      launches only the owner's allies (and the owner); enemies
#                    get enemy_status instead (e.g. bounced back the way they
#                    came). null = launches everyone.
#   lifetime         seconds before it disappears (0 = forever)
#   max_launches     launches before it disappears (0 = unlimited)
#   wait_for_footing a dashing/knocked-back actor isn't launched while it
#                    crosses the pad, only once it's standing on it
# Signals: actor_launched(actor), expired.

signal actor_launched(actor: Actor)
signal expired

const GROUP := &"jump_pads"

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

## Placed pads: whose pad this is (launches only their allies). null = everyone.
var owner_actor: Node2D
## Placed pads: status put on enemies of owner_actor who step on it.
var enemy_status: StatusEffect
## Seconds before the pad disappears. 0 = forever.
var lifetime: float = 0.0
## Launches before the pad disappears. 0 = unlimited.
var max_launches: int = 0
## Don't launch an actor mid-dash or mid-knockback, only once it stands on
## the pad (a dash that ENDS on it still launches).
var wait_for_footing: bool = false
var launches: int = 0

var _shape_node: CollisionShape2D
var _time: float = 0.0
var _bounce: float = 0.0
var _age: float = 0.0
var _inside: Array[Actor] = []
var _handled: Dictionary = {}    # actor instance id -> true once launched/bounced this visit
var _expired := false


# A pad placed at runtime (a trampoline). `landing` is a world point.
static func place(context: Node, at: Vector2, landing: Vector2, placed_by: Node2D, pad_radius: float,
		pad_air_time: float, pad_arc_height: float, pad_lifetime: float, pad_max_launches: int,
		pad_enemy_status: StatusEffect, pad_color: Color) -> JumpPad:
	var pad := JumpPad.new()
	pad.owner_actor = placed_by
	pad.radius = pad_radius
	pad.air_time = pad_air_time
	pad.arc_height = pad_arc_height
	pad.lifetime = pad_lifetime
	pad.max_launches = pad_max_launches
	pad.enemy_status = pad_enemy_status
	pad.color = pad_color
	pad.wait_for_footing = true
	pad.position = at
	pad.landing_offset = landing - at
	context.get_tree().current_scene.add_child(pad)
	pad.global_position = at
	return pad


func _ready() -> void:
	z_index = -8
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	add_to_group(GROUP)
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


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
	if ScreenCull.is_near(self, radius * 2.0):
		queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _expired:
		return
	_age += delta
	if lifetime > 0.0 and _age >= lifetime:
		expire()
		return
	# Placed pads: actors that crossed while dashing get their turn once they
	# stand here. (Map pads only ever react on entry, as they always have.)
	if not wait_for_footing:
		return
	for actor in _inside.duplicate():
		if is_instance_valid(actor) and not _handled.has(actor.get_instance_id()):
			_try(actor)


func get_owner_actor() -> Node2D:
	return owner_actor if is_instance_valid(owner_actor) else null


func has_actor_inside(actor: Node) -> bool:
	return _inside.has(actor)


# Remove the pad now.
func expire() -> void:
	if _expired:
		return
	_expired = true
	expired.emit()
	queue_free()


func _on_body_exited(body: Node2D) -> void:
	_inside.erase(body)
	_handled.erase(body.get_instance_id())


func _on_body_entered(body: Node2D) -> void:
	if not body is Actor:
		return
	var actor := body as Actor
	if not _inside.has(actor):
		_inside.append(actor)
	_try(actor)


func _try(actor: Actor) -> void:
	if _expired or actor.is_airborne() or actor.health_component.is_dead():
		return
	if wait_for_footing and actor.movement_component.is_forced_moving():
		return
	var pad_owner := get_owner_actor()
	if pad_owner != null and not _is_ally(actor, pad_owner):
		_handled[actor.get_instance_id()] = true
		if enemy_status != null:
			# Back the way they came (or straight out from the pad if standing).
			var back := -actor.velocity
			if back.length() < 1.0:
				back = actor.global_position - global_position
			actor.status_component.apply(enemy_status, pad_owner, back.normalized())
		return
	_handled[actor.get_instance_id()] = true
	# Heavy pockets: every carried Mote makes the flight a little longer.
	actor.launch(get_landing_position(), air_time + MoteCarrier.extra_air_time(actor), arc_height)
	launches += 1
	actor_launched.emit(actor)
	_bounce = 1.0
	EffectSpawner.spawn(self, launch_effect, {
		"position": global_position,
		"direction": (get_landing_position() - global_position).normalized(),
	})
	AudioManager.play_sfx(launch_sound, global_position)
	if max_launches > 0 and launches >= max_launches:
		expire.call_deferred()


static func _is_ally(actor: Node, pad_owner: Node) -> bool:
	if actor == pad_owner:
		return true
	var team := CombatQueries.team_of(pad_owner)
	return team != &"" and CombatQueries.team_of(actor) == team


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
