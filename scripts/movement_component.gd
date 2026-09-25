extends Node
class_name MovementComponent

# Turns "I want to go this way" into a velocity. Also owns every kind of
# involuntary or scripted motion: dashes, lunges, knockbacks, launches.
#
# Priority each tick:
#   1. forced move (dash, lunge, knockback/pull, launch): exact velocity
#   2. stunned or rooted: brake to a stop, ignore input
#   3. normal steering, times status multipliers and action multipliers

@export var move_speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 1600.0
## Optional. Reads the move_speed multiplier and root/stun from active statuses.
@export var status_component: StatusEffectComponent

# A forced move (dash, pull, launch) replaces steering for its duration.
var _forced_velocity := Vector2.ZERO
var _forced_time_left: float = 0.0
var _just_finished_forced_move := false
# Whether to leave the forced move at running speed (dash) or dead stop
# (knockback, lunge), so displacement distances are exact.
var _forced_carry := true
var _pending_stop := false
# Knockback is added once to the next velocity and then decays naturally
# through acceleration/friction.
var _pending_impulse := Vector2.ZERO
# Speed strips (or any node with boost_velocity(v) -> Vector2 and a
# `multiplier`) currently under the body.
var _speed_zones: Array[Node] = []
# "Commitment" slows while attacking. Keyed by whoever asked (an ability), so
# two overlapping requests can't clear each other: the slowest one wins, and
# each requester only removes its own.
var _action_multipliers: Dictionary = {}    # Object -> float


# `carry_momentum`: leave at running speed afterwards (dashes feel fluid) or
# stop dead (knockback, lunges: exact distances).
func start_forced_move(velocity: Vector2, duration: float, carry_momentum: bool = true) -> void:
	_forced_velocity = velocity
	_forced_time_left = duration
	_forced_carry = carry_momentum


# End a forced move early without the usual "leave at running speed" carry.
func stop_forced_move() -> void:
	_forced_time_left = 0.0
	_just_finished_forced_move = false
	_pending_stop = false


func is_forced_moving() -> bool:
	return _forced_time_left > 0.0


# Move exactly `distance` along `direction` over `duration` seconds. Used by
# dashes, attack lunges and CC displacement. Walls still stop it.
#
# The duration is rounded to whole physics ticks and the speed adjusted to
# match, so the distance comes out the same on every machine.
func displace(direction: Vector2, distance: float, duration: float, carry_momentum: bool = false) -> void:
	if distance <= 0.0 or direction == Vector2.ZERO:
		return
	var tick := 1.0 / Engine.physics_ticks_per_second
	var ticks := maxi(1, roundi(duration / tick))
	duration = ticks * tick
	# Half a tick of slack so float drift can't add or drop a tick.
	start_forced_move(direction.normalized() * distance / duration, duration - tick * 0.5, carry_momentum)


func apply_knockback(impulse: Vector2) -> void:
	_pending_impulse += impulse


func add_speed_zone(zone: Node) -> void:
	if zone not in _speed_zones:
		_speed_zones.append(zone)


func remove_speed_zone(zone: Node) -> void:
	_speed_zones.erase(zone)


# Slow (or speed up) walking while `requester` is doing something, e.g. 0.4
# while swinging a sword. Call clear_action_multiplier when it's done.
func set_action_multiplier(requester: Object, multiplier: float) -> void:
	_action_multipliers[requester] = multiplier


func clear_action_multiplier(requester: Object) -> void:
	_action_multipliers.erase(requester)


func get_action_multiplier() -> float:
	var result := 1.0
	for value in _action_multipliers.values():
		result = minf(result, value)
	return result


func can_walk() -> bool:
	return status_component == null or not status_component.is_rooted()


func get_move_speed() -> float:
	return move_speed \
		* StatusEffectComponent.multiplier_of(status_component, StatusEffect.MOVE_SPEED) \
		* get_action_multiplier()


func get_velocity(
	current_velocity: Vector2,
	input_direction: Vector2,
	delta: float
) -> Vector2:

	# The countdown happens here, in the same call that applies the forced
	# velocity, so an N-tick move moves exactly N times no matter which node
	# processes first.
	if is_forced_moving():
		_forced_time_left -= delta
		if _forced_time_left <= 0.0:
			_just_finished_forced_move = true
			if not _forced_carry:
				# Stop dead: this tick's motion is the last one.
				_just_finished_forced_move = false
				_pending_stop = true
		return _forced_velocity

	if _pending_stop:
		_pending_stop = false
		current_velocity = Vector2.ZERO

	if not can_walk():
		input_direction = Vector2.ZERO

	var speed := get_move_speed()
	if _just_finished_forced_move:
		# Leave a dash at normal running speed instead of sliding at dash speed.
		_just_finished_forced_move = false
		current_velocity = current_velocity.limit_length(speed)

	current_velocity += _pending_impulse
	_pending_impulse = Vector2.ZERO

	var target_velocity := input_direction * speed
	var accel := acceleration
	for zone in _speed_zones:
		if is_instance_valid(zone):
			target_velocity = zone.boost_velocity(target_velocity)
			accel *= zone.multiplier

	if input_direction != Vector2.ZERO:
		# Faster than we want to go (e.g. a swing just slowed us): brake with
		# friction rather than acceleration so the slow bites immediately.
		var rate := accel if current_velocity.length() <= target_velocity.length() else maxf(accel, friction)
		return current_velocity.move_toward(target_velocity, rate * delta)

	return current_velocity.move_toward(
		Vector2.ZERO,
		friction * delta
	)
