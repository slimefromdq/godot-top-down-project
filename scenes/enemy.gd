extends Actor

@export var stopping_distance: float = 300.0
@export var shooting_distance: float = 700.0
@export_range(0.1, 1.0, 0.05) var enemy_size: float = 0.65

var player: CharacterBody2D


func _ready() -> void:
	super()
	scale = Vector2.ONE * enemy_size
	player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	var offset_to_player := player.global_position - global_position
	var distance_to_player := offset_to_player.length()
	var direction_to_player := offset_to_player.normalized()

	weapon_pivot.look_at(player.global_position)
	aim_direction = direction_to_player

	move_direction = direction_to_player if distance_to_player > stopping_distance else Vector2.ZERO
	if distance_to_player > stopping_distance:
		velocity = movement_component.get_velocity(
			velocity,
			direction_to_player,
			delta
		)
	else:
		velocity = movement_component.get_velocity(
			velocity,
			Vector2.ZERO,
			delta
		)

	move_and_slide()

	if distance_to_player <= shooting_distance:
		weapon_component.try_fire()

	if weapon_component.current_ammo <= 0:
		weapon_component.try_reload()

