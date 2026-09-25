extends Actor
class_name Hero

# A hero is an Actor assembled from a HeroDefinition. The scene
# (scenes/heroes/hero_base.tscn) is the same for every hero; the definition
# supplies stats, abilities, feel, visuals and sound.
#
# A Hero never reads input. Something else drives it by writing
# move_direction / aim_direction / aim_point and calling request_slot():
# PlayerHeroInput for the local player, an AI later, or a network client.
# That separation is what lets the same hero be played, botted or replicated.

signal definition_applied

@export var definition: HeroDefinition
## Adds a PlayerHeroInput and a camera, and joins the "player" group.
@export var player_controlled: bool = false
@export_range(1, 20) var start_level: int = 1

## The feel presets abilities read (from the definition).
var feel_profile: FeelProfile

@onready var hitbox: Hitbox = $Hitbox

var _applied := false


# Runs BEFORE any child's _ready. Components like VisualsComponent and
# HealthComponent read their settings in their own _ready, so the definition
# has to be pushed into them here, not in Hero._ready (which runs last).
func _enter_tree() -> void:
	if _applied or definition == null:
		return
	_applied = true
	var stats := get_node(^"Components/StatsComponent") as StatsComponent
	stats.stat_block = definition.stats
	stats.level = start_level
	var movement := get_node(^"Components/MovementComponent") as MovementComponent
	movement.move_speed = definition.move_speed
	movement.acceleration = definition.acceleration
	movement.friction = definition.friction
	if definition.visual_profile != null:
		(get_node(^"Visuals") as VisualsComponent).profile = definition.visual_profile
	if definition.audio_profile != null:
		(get_node(^"Components/AudioComponent") as AudioComponent).profile = definition.audio_profile
	feel_profile = definition.feel_profile


func _ready() -> void:
	super()
	add_to_group(&"heroes")
	if definition == null:
		push_warning("%s has no HeroDefinition" % name)
		return
	var problems := definition.validate()
	if not problems.is_empty():
		push_warning("HeroDefinition '%s':\n- %s" % [definition.hero_id, "\n- ".join(problems)])
	_build_abilities()
	if player_controlled:
		_setup_player_control()
	definition_applied.emit()


func _physics_process(delta: float) -> void:
	velocity = movement_component.get_velocity(velocity, move_direction, delta)
	move_and_slide()


# The one entry point for "use the ability in this slot".
func request_slot(slot_id: StringName, target_position: Vector2) -> bool:
	return ability_controller.try_activate_slot(slot_id, target_position)


func get_ability(slot_id: StringName) -> Ability:
	return ability_controller.get_ability_for_slot(slot_id)


func get_level() -> int:
	return stats_component.level


# One node per filled slot, created from the slot's AbilityData.
func _build_abilities() -> void:
	var rules := GameRules.current()
	for slot in rules.slots:
		var ability_data := definition.get_ability(slot.id)
		if ability_data == null or ability_data.ability_script == null:
			continue
		var ability: Ability = ability_data.ability_script.new()
		if ability == null:
			push_warning("Slot %s: ability_script didn't create an Ability" % slot.id)
			continue
		ability.name = str(slot.id).to_pascal_case()
		ability.input_action = slot.input_action
		# set_data before add_child, so the ability's _ready sees its data.
		ability.set_data(ability_data)
		ability_controller.add_ability(ability, slot.id)


func _setup_player_control() -> void:
	add_to_group(&"player")
	var input := PlayerHeroInput.new()
	input.name = "PlayerHeroInput"
	# Read input BEFORE the hero moves this tick (lower priority runs first),
	# otherwise every key press would take effect one physics tick late.
	input.process_physics_priority = -1
	add_child(input)
	# The map debug view expects the camera to be a child of the player.
	if get_node_or_null(^"Camera2D") == null:
		var camera := ShakeCamera.new()
		camera.name = "Camera2D"
		add_child(camera)
		camera.make_current()


# The local player stays in the tree when dead (the camera is a child, and the
# world shows the game-over screen). Other heroes use Actor's default.
func _on_died() -> void:
	ability_controller.interrupt()
	hitbox.end_all()
	if not player_controlled:
		super()
		return
	hide()
	hurtbox.set_deferred("monitorable", false)
	set_physics_process(false)
	var input := get_node_or_null(^"PlayerHeroInput")
	if input != null:
		input.set_physics_process(false)
		input.set_process_unhandled_input(false)
