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
## Something moved this actor against its will: a status push or pull
## (`distance` in px, after displacement_taken), a carry or an abduction
## (distance INF). Launches from jump pads are not displacements. MoteCarrier
## listens for Jostle.
signal displaced(source: Node, distance: float)

@onready var movement_component: MovementComponent = $Components/MovementComponent

# Optional: heroes like Avery have no gun. Anything that uses the weapon must
# check for null.
@onready var weapon_component: WeaponComponent = get_node_or_null(^"WeaponPivot/WeaponComponent")

@onready var health_component: HealthComponent = $Components/HealthComponent

@onready var status_component: StatusEffectComponent = $Components/StatusComponent

@onready var ability_controller: AbilityController = $Components/AbilityController

@onready var weapon_pivot: Node2D = get_node_or_null(^"WeaponPivot")

@onready var hurtbox: HurtboxComponent = $Hurtbox

@onready var visuals: VisualsComponent = $Visuals

# Optional components (heroes and dummies have them, the old rifle player and
# enemy don't).
@onready var stats_component: StatsComponent = get_node_or_null(^"Components/StatsComponent")
@onready var combat_hooks: CombatHooks = get_node_or_null(^"Components/CombatHooks")

## Team id (e.g. &"a", &"b"). Empty = neutral. Read by the minimap now, and
## meant for friendly-fire rules later.
@export var team: StringName = &""

# Where the actor is aiming and trying to move. Control scripts (player input
# or enemy AI) write these; abilities and visuals read them.
var aim_direction := Vector2.RIGHT
var move_direction := Vector2.ZERO
# The world point being aimed at (the cursor for a player). Buffered casts use
# it so they follow the latest aim.
var aim_point := Vector2.ZERO

# Airborne state for launches (jump pads, knock-ups). See launch().
var _airborne := false
var _air_progress: float = 0.0
var _arc_height: float = 0.0
var _mask_before_launch: int = 0
var _air_time: float = 0.0
var _launch_target := Vector2.ZERO
# The latest displacement (displaced signal): who, and when (msec).
var _last_displacer: Node
var _last_displaced_msec: int = -1


func _ready() -> void:
	add_to_group(&"minimap_units")
	# Ability walls (ContainmentRing) stop every character, launched or not.
	collision_mask |= MapLayers.BARRIERS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health_component.died.connect(_on_died)
	displaced.connect(_remember_displacer)
	if weapon_component != null:
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


# Move instantly to `point` (a blink, a map teleporter, a rescue pull).
# Refused (returns false, nothing moves) if it would cross a ContainmentRing:
# "nobody in or out" includes teleports.
func _remember_displacer(source: Node, _distance: float) -> void:
	_last_displacer = source
	_last_displaced_msec = Time.get_ticks_msec()


## Who last pushed, pulled or carried this actor, if it was within `seconds`
## and they're still around (else null). Map hazards use it for credit.
func get_last_displacer(seconds: float) -> Node:
	if _last_displaced_msec < 0 or not is_instance_valid(_last_displacer):
		return null
	if Time.get_ticks_msec() - _last_displaced_msec > seconds * 1000.0:
		return null
	return _last_displacer


func teleport_to(point: Vector2) -> bool:
	if ContainmentRing.crosses_any(get_tree(), global_position, point):
		return false
	global_position = point
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	return true


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
	_air_time = air_time
	_launch_target = target
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


# Where the current launch will land (valid while airborne).
func get_launch_target() -> Vector2:
	return _launch_target


# Steer a launch in flight: land on `target` instead, at the same moment. The
# ground track bends toward it (a steerable glide). No effect on the ground.
func retarget_launch(target: Vector2) -> void:
	if not _airborne:
		return
	_launch_target = target
	var remaining := _air_time * (1.0 - _air_progress)
	if remaining <= 0.001:
		return
	movement_component.start_forced_move((target - global_position) / remaining, remaining)


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
	if weapon_pivot != null:
		weapon_pivot.hide()

	var linger := visuals.get_death_duration()
	if linger > 0.0:
		await get_tree().create_timer(linger, false).timeout
	queue_free()
