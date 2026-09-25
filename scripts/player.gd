extends Actor

var mouse_global_position

# The click-cast ability (if any) and whatever it would hit right now. Used to
# highlight valid targets under the cursor.
var _targeted_ability: TargetedAbility
var _hovered_visuals: VisualsComponent


func _ready() -> void:
	super()
	for ability in ability_controller.abilities:
		if ability is TargetedAbility:
			_targeted_ability = ability
			break


# Actor's default is queue_free(), but the player's Camera2D is a child, so
# freeing the player would snap the view away. Hide it and stop its input
# instead; the world pauses the game and shows the game-over screen.
func _on_died() -> void:
	_set_hovered(null)
	hide()
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)


func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	move_direction = input_direction

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
	mouse_global_position = get_global_mouse_position()
	weapon_pivot.look_at(mouse_global_position)
	aim_direction = (mouse_global_position - global_position).normalized()
	aim_point = mouse_global_position

	if Input.is_action_pressed("fire"):
		weapon_component.try_fire()

	if Input.is_action_just_pressed("reload"):
		weapon_component.try_reload()

	if Input.is_action_just_pressed("ui_accept"):
		health_component.take_damage(20.0)

	_update_target_highlight()


# Abilities are requested here and validated by the ability itself, so an
# enemy AI can call the same try_activate() with its own target point.
func _unhandled_input(event: InputEvent) -> void:
	var ability := ability_controller.get_ability_for_event(event)
	if ability == null:
		return
	ability_controller.try_activate(ability, get_global_mouse_position())
	get_viewport().set_input_as_handled()


func _update_target_highlight() -> void:
	if _targeted_ability == null or not _targeted_ability.is_ready():
		_set_hovered(null)
		return
	var target := _targeted_ability.find_target(get_global_mouse_position())
	_set_hovered(VisualsComponent.find_on(target.owner) if target != null else null)


func _set_hovered(visuals_component: VisualsComponent) -> void:
	if visuals_component == _hovered_visuals:
		return
	if is_instance_valid(_hovered_visuals):
		_hovered_visuals.set_highlighted(false)
	_hovered_visuals = visuals_component
	if _hovered_visuals != null:
		_hovered_visuals.set_highlighted(true)
