extends Node
class_name MovementComponent

@export var move_speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 1600.0
## Optional. Reads the move_speed multiplier from active status effects.
@export var status_component: StatusEffectComponent

# A forced move (dash, pull, launch) replaces steering for its duration.
var _forced_velocity := Vector2.ZERO
var _forced_time_left: float = 0.0
var _just_finished_forced_move := false
# Knockback is added once to the next velocity and then decays naturally
# through acceleration/friction.
var _pending_impulse := Vector2.ZERO
# Speed strips (or any node with boost_velocity(v) -> Vector2 and a
# `multiplier`) currently under the body.
var _speed_zones: Array[Node] = []


func _physics_process(delta: float) -> void:
	if _forced_time_left > 0.0:
		_forced_time_left -= delta
		if _forced_time_left <= 0.0:
			_just_finished_forced_move = true


func start_forced_move(velocity: Vector2, duration: float) -> void:
	_forced_velocity = velocity
	_forced_time_left = duration


# End a forced move early without the usual "leave at running speed" carry.
func stop_forced_move() -> void:
	_forced_time_left = 0.0
	_just_finished_forced_move = false


func is_forced_moving() -> bool:
	return _forced_time_left > 0.0


func apply_knockback(impulse: Vector2) -> void:
	_pending_impulse += impulse


func add_speed_zone(zone: Node) -> void:
	if zone not in _speed_zones:
		_speed_zones.append(zone)


func remove_speed_zone(zone: Node) -> void:
	_speed_zones.erase(zone)


func get_move_speed() -> float:
	return move_speed * StatusEffectComponent.multiplier_of(status_component, StatusEffect.MOVE_SPEED)


func get_velocity(
	current_velocity: Vector2,
	input_direction: Vector2,
	delta: float
) -> Vector2:

	if is_forced_moving():
		return _forced_velocity

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
		return current_velocity.move_toward(
			target_velocity,
			accel * delta
		)

	return current_velocity.move_toward(
		Vector2.ZERO,
		friction * delta
	)
