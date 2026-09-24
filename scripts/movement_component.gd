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


func _physics_process(delta: float) -> void:
	if _forced_time_left > 0.0:
		_forced_time_left -= delta
		if _forced_time_left <= 0.0:
			_just_finished_forced_move = true


func start_forced_move(velocity: Vector2, duration: float) -> void:
	_forced_velocity = velocity
	_forced_time_left = duration


func is_forced_moving() -> bool:
	return _forced_time_left > 0.0


func apply_knockback(impulse: Vector2) -> void:
	_pending_impulse += impulse


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

	if input_direction != Vector2.ZERO:
		return current_velocity.move_toward(
			target_velocity,
			acceleration * delta
		)

	return current_velocity.move_toward(
		Vector2.ZERO,
		friction * delta
	)
