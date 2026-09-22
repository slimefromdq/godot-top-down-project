extends CharacterBody2D

@onready var movement_component: MovementComponent = $Components/MovementComponent
	
@onready var weapon_component: WeaponComponent = $WeaponPivot/WeaponComponent


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

	# CharacterBody2D movement belongs on the same physics tick that calculates
	# velocity so collision behavior remains consistent.
	move_and_slide()


func _process(_delta: float) -> void:
	# Holding the action supports automatic fire; WeaponComponent owns the
	# cooldown, so input cannot force shots faster than the configured rate.
	if Input.is_action_pressed("fire"):
		weapon_component.try_fire()

	if Input.is_action_just_pressed("reload"):
		weapon_component.try_reload()
