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
signal launched(target: Vector2)
signal landed

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

# Airborne state for launches (jump pads, knock-ups). See launch().
var _airborne := false
var _air_progress: float = 0.0
var _arc_height: float = 0.0
var _mask_before_launch: int = 0


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


func is_airborne() -> bool:
	return _airborne


# Fly in an arc to `target`, landing exactly there after `air_time` seconds.
#
# The body really travels along the ground in a straight line (a forced move);
# the arc is only visual (the Visuals node lifts and grows, a shadow stays on
# the ground). While airborne the body passes over low cover and ledges, which
# is what lets a jump pad carry you up a cliff. Walls still stop you.
func launch(target: Vector2, air_time: float, arc_height: float = 140.0) -> void:
	if _airborne or air_time <= 0.0:
		return
	_airborne = true
	_arc_height = arc_height
	_mask_before_launch = collision_mask
	collision_mask &= ~MapLayers.JUMPABLE
	movement_component.start_forced_move((target - global_position) / air_time, air_time)
	trigger_cue(&"launch", {"target_position": target})
	launched.emit(target)

	# Physics-process tween, so landing lines up with the forced move's ticks.
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_set_air_progress, 0.0, 1.0, air_time)
	tween.finished.connect(_land)


func _set_air_progress(t: float) -> void:
	_air_progress = t
	var height := 4.0 * t * (1.0 - t)    # 0 -> 1 -> 0
	visuals.position.y = -_arc_height * height
	visuals.scale = Vector2.ONE * (1.0 + 0.25 * height)
	queue_redraw()


func _land() -> void:
	_airborne = false
	# Stick the landing: no slide, so a pad always puts you on its ring.
	movement_component.stop_forced_move()
	velocity = Vector2.ZERO
	# Restore only the bits launch() removed, in case something else changed
	# the mask mid-flight.
	collision_mask |= _mask_before_launch & MapLayers.JUMPABLE
	_set_air_progress(0.0)
	trigger_cue(&"land")
	landed.emit()


func _draw() -> void:
	if not _airborne:
		return
	# Ground shadow: shrinks as the body rises, so height reads at a glance.
	var height := 4.0 * _air_progress * (1.0 - _air_progress)
	draw_set_transform(Vector2(0, 40), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 70.0 * (1.0 - 0.35 * height), Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)


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
