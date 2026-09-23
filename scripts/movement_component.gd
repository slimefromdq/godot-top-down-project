extends Node
class_name MovementComponent

@export var move_speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 1600.0

func get_velocity(
	current_velocity: Vector2,
	input_direction: Vector2,
	delta: float
) -> Vector2:

	var target_velocity := input_direction * move_speed

	if input_direction != Vector2.ZERO:
		return current_velocity.move_toward(
			target_velocity,
			acceleration * delta
		)

	return current_velocity.move_toward(
		Vector2.ZERO,
		friction * delta
	)
