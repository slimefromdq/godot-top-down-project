extends CharacterBody2D

@onready var movement_component: MovementComponent = \
	$Components/MovementComponent


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = movement_component.get_velocity(
		velocity,
		input_direction,
		delta
	)

	move_and_slide()
