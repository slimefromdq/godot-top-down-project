extends CharacterBody2D
class_name Actor

# Shared setup for every character built from actor.tscn. Player and enemy
# scripts extend this and only add their own control logic.
#
# The Actor is also the "cue hub": gameplay code calls trigger_cue() with a
# name such as "fire" or "phase_dash", and VisualsComponent / AudioComponent
# look that name up in their profiles to decide what to show and play.
# Gameplay never references a sprite, particle or sound directly.

signal cue_triggered(cue: StringName, context: Dictionary)

@onready var movement_component: MovementComponent = $Components/MovementComponent

@onready var weapon_component: WeaponComponent = $WeaponPivot/WeaponComponent

@onready var health_component: HealthComponent = $Components/HealthComponent

@onready var status_component: StatusEffectComponent = $Components/StatusComponent

@onready var ability_controller: AbilityController = $Components/AbilityController

@onready var weapon_pivot: Node2D = $WeaponPivot

@onready var hurtbox: HurtboxComponent = $Hurtbox

@onready var visuals: VisualsComponent = $Visuals

# Where the actor is aiming and trying to move. Control scripts (player input
# or enemy AI) write these; abilities and visuals read them.
var aim_direction := Vector2.RIGHT
var move_direction := Vector2.ZERO


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health_component.died.connect(_on_died)
	weapon_component.fired.connect(_on_weapon_fired)
	weapon_component.reload_started.connect(trigger_cue.bind(&"reload"))
	weapon_component.reload_finished.connect(trigger_cue.bind(&"reload_done"))
	weapon_component.dry_fired.connect(trigger_cue.bind(&"dry_fire"))


# Context keys every listener can rely on: position, direction, source.
# Callers add their own (target, target_position, text, ...).
func trigger_cue(cue: StringName, context: Dictionary = {}) -> void:
	context.merge({
		"position": global_position,
		"direction": aim_direction,
		"source": self,
	})
	cue_triggered.emit(cue, context)


func _on_weapon_fired(muzzle_position: Vector2, direction: Vector2) -> void:
	trigger_cue(&"fire", {"position": muzzle_position, "direction": direction})


# Override this to react to death differently, e.g. a game-over screen.
func _on_died() -> void:
	# Stop acting and stop being hittable, but stay in the tree long enough for
	# a death animation. Death effects themselves are spawned into the world by
	# VisualsComponent, so they outlive the actor.
	set_physics_process(false)
	set_process(false)
	hurtbox.set_deferred("monitorable", false)
	collision_layer = 0
	weapon_pivot.hide()

	var linger := visuals.get_death_duration()
	if linger > 0.0:
		await get_tree().create_timer(linger, false).timeout
	queue_free()
