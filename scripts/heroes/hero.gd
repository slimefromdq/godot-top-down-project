extends Actor
class_name Hero

# A hero is an Actor assembled from a HeroDefinition. The scene
# (scenes/heroes/hero_base.tscn) is the same for every hero; the definition
# supplies stats, abilities, feel, visuals and sound.
#
# A Hero never reads input. Something else drives it by writing
# move_direction / aim_direction / aim_point and calling request_slot()
# (press), release_slot() (let go of a hold-to-charge) and reload():
# PlayerHeroInput for the local player, an AI later, or a network client.
# That separation is what lets the same hero be played, botted or replicated.

signal definition_applied
## Back in play after a death (Hero.respawn).
signal respawned

@export var definition: HeroDefinition
## Adds a PlayerHeroInput and a camera, and joins the "player" group.
@export var player_controlled: bool = false
## Adds a BotHeroInput. Can be switched at runtime with set_bot_controlled().
@export var bot_controlled: bool = false
@export var bot_skill: BotSkill = preload("res://resources/ai/normal.tres")
@export var bot_seed: int = 1
@export_range(1, 20) var start_level: int = 1

## Stay in the tree when dead (hidden, not hittable) so something can call
## respawn() later. The MatchManager sets it on every hero in its roster.
## The local player always behaves this way.
var respawns: bool = false

## The feel presets abilities read (from the definition).
var feel_profile: FeelProfile

@onready var hitbox: Hitbox = $Hitbox

var _applied := false
var _layer_before_death: int = 0


# Runs BEFORE any child's _ready. Components like VisualsComponent and
# HealthComponent read their settings in their own _ready, so the definition
# has to be pushed into them here, not in Hero._ready (which runs last).
func _enter_tree() -> void:
	if _applied or definition == null:
		return
	_applied = true
	var stats := get_node(^"Components/StatsComponent") as StatsComponent
	# Private copies (like abilities' data): the debug panel can edit live
	# numbers without touching the .tres files, and reset_tuning() restores them.
	stats.stat_block = definition.stats.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stats.level = start_level
	var movement := get_node(^"Components/MovementComponent") as MovementComponent
	movement.move_speed = definition.move_speed
	movement.acceleration = definition.acceleration
	movement.friction = definition.friction
	if definition.visual_profile != null:
		(get_node(^"Visuals") as VisualsComponent).profile = definition.visual_profile
	if definition.audio_profile != null:
		(get_node(^"Components/AudioComponent") as AudioComponent).profile = definition.audio_profile
	if definition.feel_profile != null:
		feel_profile = definition.feel_profile.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)


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
	if bot_controlled:
		set_bot_controlled(true)
	definition_applied.emit()


func _physics_process(delta: float) -> void:
	velocity = movement_component.get_velocity(velocity, move_direction, delta)
	move_and_slide()


# The one entry point for "use the ability in this slot".
func request_slot(slot_id: StringName, target_position: Vector2) -> bool:
	return ability_controller.try_activate_slot(slot_id, target_position)


# Let go of a slot's hold-to-charge ability (key released / AI decides to
# fire). Harmless for abilities that don't charge.
func release_slot(slot_id: StringName, target_position: Vector2) -> bool:
	return ability_controller.release_slot(slot_id, target_position)


# Cancel a slot's charge without spending its cooldown.
func cancel_slot(slot_id: StringName) -> bool:
	return ability_controller.cancel(get_ability(slot_id))


func get_ability(slot_id: StringName) -> Ability:
	return ability_controller.get_ability_for_slot(slot_id)


# The gun in a slot, or null if that slot isn't a RangedAttackAbility. Pass
# &"" for the first gun in any slot. Other abilities use this to interact
# with the gun (a dash that reloads: get_ranged_ability().reload_instantly()).
func get_ranged_ability(slot_id: StringName = &"primary") -> RangedAttackAbility:
	if slot_id != &"":
		return get_ability(slot_id) as RangedAttackAbility
	for ability in ability_controller.abilities:
		if ability is RangedAttackAbility:
			return ability
	return null


# The gun the reload key acts on: the primary if it's a gun, else the first.
func get_reload_ability() -> RangedAttackAbility:
	var primary := get_ranged_ability(&"primary")
	return primary if primary != null else get_ranged_ability(&"")


# Reload request (the hero_reload key, or AI). Returns true if a reload began.
func reload() -> bool:
	var gun := get_reload_ability()
	return gun != null and gun.start_reload()


func get_level() -> int:
	return stats_component.level


# Debug: throw away live edits to stats and feel, back to the definition.
func reset_tuning() -> void:
	stats_component.stat_block = definition.stats.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stats_component.stats_changed.emit()
	if definition.feel_profile != null:
		feel_profile = definition.feel_profile.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)


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


func set_bot_controlled(enabled: bool) -> void:
	bot_controlled = enabled
	var player_input := get_node_or_null(^"PlayerHeroInput") as PlayerHeroInput
	if player_input != null:
		player_input.set_physics_process(not enabled)
		player_input.set_process_unhandled_input(not enabled)
	var existing := get_node_or_null(^"BotHeroInput") as BotHeroInput
	if enabled and existing == null:
		var bot := BotHeroInput.new()
		bot.name = "BotHeroInput"
		bot.skill = bot_skill
		bot.seed = bot_seed
		bot.process_physics_priority = -1
		add_child(bot)
	elif not enabled and existing != null:
		existing.stop()
		remove_child(existing)
		existing.queue_free()


# The local player and respawning heroes stay in the tree when dead (the
# camera is a child, and the world shows the game-over screen or the match
# respawns them). Other heroes use Actor's default.
func _on_died() -> void:
	ability_controller.interrupt()
	hitbox.end_all()
	if not player_controlled and not respawns:
		super()
		return
	hide()
	hurtbox.set_deferred("monitorable", false)
	_layer_before_death = collision_layer
	collision_layer = 0
	set_physics_process(false)
	_set_input_enabled(false)


# Back to full health at `at`, with statuses cleared and ammo refilled.
# Only for a hero that stayed in the tree (see `respawns`).
func respawn(at: Vector2) -> void:
	if not health_component.is_dead():
		return
	status_component.clear()
	health_component.reset()
	global_position = at
	velocity = Vector2.ZERO
	movement_component.stop_forced_move()
	reset_physics_interpolation()
	if _layer_before_death != 0:
		collision_layer = _layer_before_death
	hurtbox.set_deferred("monitorable", true)
	set_physics_process(true)
	_set_input_enabled(true)
	var gun := get_reload_ability()
	if gun != null:
		gun.reload_instantly()
	show()
	visuals.revive()
	respawned.emit()


func _set_input_enabled(enabled: bool) -> void:
	var input := get_node_or_null(^"PlayerHeroInput")
	if input != null:
		input.set_physics_process(enabled)
		input.set_process_unhandled_input(enabled)
	var bot := get_node_or_null(^"BotHeroInput")
	if bot != null:
		bot.set_physics_process(enabled)
