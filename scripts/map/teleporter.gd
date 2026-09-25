@tool
extends Area2D
class_name Teleporter

# One end of a teleporter link. Place two and point each one's `partner` at
# the other.
#
# Using it: stand on a sending pad for `channel_time` seconds. While you
# channel, the destination pad glows and pulses. That is the exit telegraph:
# anyone near the far end sees someone is about to arrive. Step off to cancel.
#
# Modes:
#   TWO_WAY       both ends send and receive (set it on both ends).
#   SEND_ONLY     entrance of a one-way link (the spawn "Dawn Door").
#   RECEIVE_ONLY  exit of a one-way link; standing on it does nothing.
#
# After a teleport the link rests for `cooldown` seconds at BOTH ends, so a
# whole team can't pour through at once and the exit can be held. Someone who
# just arrived isn't sent back until they step off the pad.

enum Mode { TWO_WAY, SEND_ONLY, RECEIVE_ONLY }

@export var partner: Teleporter
@export var mode: Mode = Mode.TWO_WAY:
	set(value):
		mode = value
		queue_redraw()
@export_range(0.0, 3.0, 0.05) var channel_time: float = 0.75
## Rest time for the whole link after each use. 0 = no rest.
@export_range(0.0, 20.0, 0.5) var cooldown: float = 4.0
@export var radius: float = 95.0:
	set(value):
		radius = value
		_rebuild()
@export var color := Color("8b5cf6")
@export var depart_effect: PackedScene = preload("res://effects/spawn_puff.tscn")
@export var arrive_effect: PackedScene = preload("res://effects/spawn_puff.tscn")
@export var teleport_sound: SoundCue = preload("res://resources/audio/sfx/zap.tres")

var _shape_node: CollisionShape2D
var _on_pad: Array[Actor] = []
var _channel: Dictionary = {}          # Actor -> seconds channelled
var _just_arrived: Array[Actor] = []   # ignored until they step off
var _cooldown_left: float = 0.0
var _incoming: float = 0.0             # 0..1 telegraph strength, set by partner
var _time: float = 0.0


func _ready() -> void:
	z_index = -8
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


func can_send() -> bool:
	return mode != Mode.RECEIVE_ONLY and partner != null


func is_ready() -> bool:
	return _cooldown_left <= 0.0


func start_cooldown() -> void:
	_cooldown_left = cooldown


# Called by the sending partner every frame someone channels toward us.
func show_incoming(progress: float) -> void:
	_incoming = maxf(_incoming, progress)


func receive(actor: Actor) -> void:
	actor.global_position = global_position
	actor.velocity = Vector2.ZERO
	actor.reset_physics_interpolation()
	if actor not in _just_arrived:
		_just_arrived.append(actor)
	EffectSpawner.spawn(self, arrive_effect, {"position": global_position})
	AudioManager.play_sfx(teleport_sound, global_position)
	start_cooldown()


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


func _on_body_entered(body: Node2D) -> void:
	if body is Actor and body not in _on_pad:
		_on_pad.append(body)


func _on_body_exited(body: Node2D) -> void:
	_on_pad.erase(body)
	_channel.erase(body)
	_just_arrived.erase(body)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not can_send() or not is_ready():
		_channel.clear()
		return

	for actor in _on_pad.duplicate():
		if not is_instance_valid(actor) or actor.health_component.is_dead():
			_on_pad.erase(actor)
			_channel.erase(actor)
			continue
		if actor in _just_arrived or actor.is_airborne():
			continue
		var channelled: float = _channel.get(actor, 0.0) + delta
		_channel[actor] = channelled
		partner.show_incoming(clampf(channelled / maxf(channel_time, 0.01), 0.0, 1.0))
		if channelled >= channel_time:
			_send(actor)
			return


func _send(actor: Actor) -> void:
	_channel.clear()
	_on_pad.erase(actor)
	EffectSpawner.spawn(self, depart_effect, {"position": global_position})
	actor.trigger_cue(&"teleport", {"target_position": partner.global_position})
	partner.receive(actor)
	start_cooldown()


func _process(delta: float) -> void:
	_time += delta
	_incoming = maxf(0.0, _incoming - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var idle := Engine.is_editor_hint() or is_ready()
	var base := color if idle else color.lerp(Color(0.5, 0.5, 0.55), 0.7)

	# Incoming telegraph: bright rings collapsing inward, plus a column of light.
	if _incoming > 0.0:
		for k in 3:
			var t := fmod(_time * 1.6 + k / 3.0, 1.0)
			draw_arc(Vector2.ZERO, radius * (2.4 - 1.4 * t), 0, TAU, 48,
				Color(1, 1, 1, _incoming * t), 6.0)
		draw_circle(Vector2.ZERO, radius * 1.1, Color(color.lightened(0.5), 0.35 * _incoming))

	# Pad body.
	draw_circle(Vector2(8, 12), radius, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, radius, base.darkened(0.5))
	if mode == Mode.RECEIVE_ONLY:
		# Exit-only: hollow, with arrows pointing out. "You come out here."
		draw_circle(Vector2.ZERO, radius * 0.78, base.darkened(0.2))
		for k in 4:
			var direction := Vector2.RIGHT.rotated(k * TAU / 4.0 + PI / 4.0)
			var tip := direction * radius * 0.7
			draw_line(direction * radius * 0.25, tip, Color.WHITE, 5.0)
	else:
		draw_circle(Vector2.ZERO, radius * 0.78, base)
		# Swirl.
		for k in 3:
			var start := _time * 2.0 + k * TAU / 3.0
			draw_arc(Vector2.ZERO, radius * 0.5, start, start + 1.4, 16, Color(1, 1, 1, 0.8), 6.0)

	# Cooldown sweep.
	if not idle and cooldown > 0.0:
		var ratio := _cooldown_left / cooldown
		draw_arc(Vector2.ZERO, radius + 10, -PI / 2.0, -PI / 2.0 + TAU * ratio, 48, Color(1, 1, 1, 0.8), 6.0)

	# Channel progress for whoever is standing on the pad.
	var best := 0.0
	for value: float in _channel.values():
		best = maxf(best, value)
	if best > 0.0 and channel_time > 0.0:
		draw_arc(Vector2.ZERO, radius + 10, -PI / 2.0, -PI / 2.0 + TAU * best / channel_time, 48,
			color.lightened(0.6), 10.0)
