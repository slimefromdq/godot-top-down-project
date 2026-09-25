extends Node
class_name Ability

# Base class for every ability. Input never lives here: the player's input node
# (or an AI) asks the AbilityController, the controller decides whether the
# hero is free to act (or buffers the press), and the ability decides whether
# it can fire.
#
# Two styles, both supported:
#
# 1. Instant (the original abilities: skillshot, dash, buff, zap). No
#    AbilityData, no timings. Override _activate() and do everything there.
#
# 2. Timed (new abilities). Give it an AbilityData. The cast runs through
#       WINDUP -> ACTIVE -> RECOVERY
#    with durations from the hero's FeelProfile (see AttackFeel). Override
#    _activate() to validate and aim, then the phase hooks to do the work:
#       _on_windup_start, _on_active_start, _on_active_tick, _on_active_end,
#       _on_recovery_start, _on_cast_end(interrupted)
#    The base class handles the commitment slow, the lunge, cancel windows
#    and interrupts, so ability scripts stay short.
#
# Presentation: a successful cast triggers a cue named after ability_id on the
# actor, and each phase triggers "<ability_id>_windup" / "_active" /
# "_recovery". A failed cast triggers "ability_failed" with context.text set
# to the reason. Map those in the actor's VisualProfile / AudioProfile.

signal activated
signal activation_failed(reason: String)
signal cooldown_finished
signal phase_changed(phase: Phase)
signal cast_finished(interrupted: bool)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

## Cue name and stable identifier. Keep it snake_case.
@export var ability_id: StringName = &"ability"
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Input action that requests this ability. Configure it in Project Settings > Input Map.
@export var input_action: StringName
@export var cooldown: float = 5.0
## Optional. When set, id/name/icon/cooldown come from here and the cast is
## timed (windup/active/recovery).
@export var data: AbilityData

## Debug: every ability is always off cooldown.
static var cooldowns_disabled := false

var actor: Actor
var controller: AbilityController
## Which hero slot this fills ("primary", "cc" ...). Empty for legacy abilities.
var slot_id: StringName
var cooldown_remaining: float = 0.0

var phase: Phase = Phase.IDLE
## Seconds spent in the current phase.
var phase_time: float = 0.0
var cast_target := Vector2.ZERO
var cast_direction := Vector2.RIGHT
## The timing of the current cast (set at cast start).
var current_feel: AttackFeel

# The .tres this ability's runtime copy came from; reset_data() restores it.
var _source_data: AbilityData


func _ready() -> void:
	if data != null and _source_data == null:
		set_data(data)


# Abilities work on a private COPY of their data, so the debug panel can edit
# numbers live without writing into the .tres on disk, and reset_data() can
# always restore the designer's values.
func set_data(new_data: AbilityData) -> void:
	_source_data = new_data
	data = new_data.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	ability_id = data.id
	display_name = data.display_name
	description = data.description
	if data.icon != null:
		icon = data.icon
	cooldown = data.cooldown


func reset_data() -> void:
	if _source_data != null:
		set_data(_source_data)


func get_source_data() -> AbilityData:
	return _source_data


func get_stats() -> StatsComponent:
	return StatsComponent.find_on(actor)


func get_level() -> int:
	var stats := get_stats()
	return stats.level if stats != null else 1


func get_cooldown() -> float:
	return data.get_cooldown(get_level()) if data != null else cooldown


func is_ready() -> bool:
	return cooldown_remaining <= 0.0


func is_casting() -> bool:
	return phase != Phase.IDLE


# 0 when ready, 1 right after casting. Handy for cooldown sweeps.
func get_cooldown_ratio() -> float:
	var total := get_cooldown()
	if total <= 0.0:
		return 0.0
	return clampf(cooldown_remaining / total, 0.0, 1.0)


# Movement abilities can cancel recovery earlier than other abilities
# (AttackFeel.movement_cancel_after). Tag the data with "movement".
func is_movement_ability() -> bool:
	return data != null and data.tags.has(&"movement")


# Public request. Goes through the controller so buffering and cancel windows
# apply; returns true if the cast started right now.
func try_activate(target_position: Vector2) -> bool:
	if controller != null:
		return controller.try_activate(self, target_position)
	return start_cast(target_position)


# Why this can't be cast right now, or "" if it can. Doesn't check whether the
# hero is busy with another cast; the controller does that.
func get_block_reason() -> String:
	if actor == null or actor.health_component.is_dead():
		return "Dead"
	if not is_ready():
		return "Cooldown"
	# Mid-air, a dash or pull would replace the launch arc.
	if actor.is_airborne():
		return "Airborne"
	var status := actor.status_component
	if status != null:
		if status.is_stunned():
			return "Stunned"
		if status.is_silenced():
			return "Silenced"
		if is_movement_ability() and status.is_rooted():
			return "Rooted"
	return ""


# Called by the controller once the hero is free. Returns true on success.
func start_cast(target_position: Vector2) -> bool:
	var blocked := get_block_reason()
	if blocked != "":
		# Cooldown/dead/airborne aren't worth a red flash (the original
		# abilities stayed silent there too); CC and costs are feedback.
		if blocked not in ["Cooldown", "Dead", "Airborne"]:
			_fail(blocked)
		return false
	if not _pay_cost():
		_fail("Not enough %s" % data.cost_type)
		return false

	cast_target = target_position
	cast_direction = (target_position - actor.global_position).normalized()
	if cast_direction == Vector2.ZERO:
		cast_direction = actor.aim_direction
	current_feel = _get_cast_feel()

	var failure := _activate(target_position)
	if failure != "":
		# Failed casts cost nothing, so a missed click-target can be retried.
		_fail(failure)
		return false

	cooldown_remaining = 0.0 if cooldowns_disabled else get_cooldown()
	activated.emit()
	if current_feel != null:
		_enter_phase(Phase.WINDUP)
		_advance(0.0)
	return true


# Stop the cast now (stun, death, cancel). Cooldown is NOT refunded.
func interrupt() -> void:
	_end_cast(true)


# Cut recovery short because the player chose to act (walk, dash, next
# attack). Unlike interrupt(), this counts as a completed cast.
func cancel_recovery() -> void:
	if phase == Phase.RECOVERY:
		_end_cast(false)


# May `other` start now, cutting this cast short?
func can_be_cancelled_by(other: Ability) -> bool:
	if phase == Phase.IDLE:
		return true
	if phase != Phase.RECOVERY or current_feel == null:
		return false
	var after := current_feel.movement_cancel_after if other != null and other.is_movement_ability() \
		else current_feel.ability_cancel_after
	return after >= 0.0 and phase_time >= after


# Override. Validate and set up; return "" on success or a short player-facing
# reason ("No target") on failure. Instant abilities do all their work here.
func _activate(_target_position: Vector2) -> String:
	return ""


# Override to spend mana/heat later. Nothing costs anything yet.
func _pay_cost() -> bool:
	return true


# Which AttackFeel times this cast. null = instant (legacy style).
# Override to pick a different preset per cast (combo steps do).
func _get_cast_feel() -> AttackFeel:
	if data == null:
		return null
	if data.feel_override != null:
		return data.feel_override
	return get_feel_preset(data.feel_preset)


func get_feel_preset(preset: StringName) -> AttackFeel:
	var profile: FeelProfile = actor.get(&"feel_profile") if actor != null else null
	var feel := profile.get_preset(preset) if profile != null else null
	return feel if feel != null else AttackFeel.new()


# Phase hooks for timed abilities. All optional.
func _on_windup_start() -> void: pass
func _on_active_start() -> void: pass
func _on_active_tick(_delta: float) -> void: pass
func _on_active_end() -> void: pass
func _on_recovery_start() -> void: pass
func _on_cast_end(_interrupted: bool) -> void: pass


# Simulation: cooldowns and cast phases tick on physics frames.
func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta
		if cooldowns_disabled or cooldown_remaining <= 0.0:
			cooldown_remaining = 0.0
			cooldown_finished.emit()
	if phase != Phase.IDLE:
		_advance(delta)


func _advance(delta: float) -> void:
	phase_time += delta
	if current_feel != null and not current_feel.lock_aim and phase != Phase.RECOVERY:
		cast_direction = actor.aim_direction
	if phase == Phase.ACTIVE:
		_on_active_tick(delta)

	# A loop, so zero-length phases pass through in the same tick.
	while phase != Phase.IDLE and phase_time >= _phase_duration(phase):
		var overflow := phase_time - _phase_duration(phase)
		match phase:
			Phase.WINDUP:
				_enter_phase(Phase.ACTIVE)
			Phase.ACTIVE:
				_enter_phase(Phase.RECOVERY)
				if phase == Phase.IDLE:
					return    # the ability ended its own cast in _on_active_end
			Phase.RECOVERY:
				_end_cast(false)
				return
		phase_time = overflow

	# Walking out of recovery: once the movement cancel window opens, moving
	# ends the follow-through so heavy never feels sluggish.
	if phase == Phase.RECOVERY and actor.move_direction != Vector2.ZERO \
			and current_feel.movement_cancel_after >= 0.0 \
			and phase_time >= current_feel.movement_cancel_after:
		_end_cast(false)


func _phase_duration(which: Phase) -> float:
	match which:
		Phase.WINDUP: return current_feel.windup
		Phase.ACTIVE: return current_feel.active
		Phase.RECOVERY: return current_feel.recovery
	return 0.0


func _enter_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0
	match new_phase:
		Phase.WINDUP:
			actor.movement_component.set_action_multiplier(self, current_feel.move_multiplier)
			actor.trigger_cue(StringName(str(ability_id) + "_windup"), _cue_context())
			_on_windup_start()
		Phase.ACTIVE:
			if current_feel.lunge_distance > 0.0 and actor.movement_component.can_walk():
				actor.movement_component.displace(cast_direction, current_feel.lunge_distance, current_feel.lunge_duration)
			actor.trigger_cue(StringName(str(ability_id) + "_active"), _cue_context())
			_on_active_start()
		Phase.RECOVERY:
			# Phase is already RECOVERY here, so if _on_active_end ends the
			# cast, _end_cast won't call _on_active_end a second time.
			_on_active_end()
			if phase != Phase.RECOVERY:
				return
			actor.trigger_cue(StringName(str(ability_id) + "_recovery"), _cue_context())
			_on_recovery_start()
	phase_changed.emit(new_phase)


func _end_cast(interrupted: bool) -> void:
	if phase == Phase.IDLE:
		return
	var was_active := phase == Phase.ACTIVE
	phase = Phase.IDLE
	phase_time = 0.0
	if is_instance_valid(actor):
		actor.movement_component.clear_action_multiplier(self)
	if was_active:
		_on_active_end()
	_on_cast_end(interrupted)
	phase_changed.emit(Phase.IDLE)
	cast_finished.emit(interrupted)


func _cue_context() -> Dictionary:
	return {
		"direction": cast_direction,
		"ability": ability_id,
		"weight": current_feel.weight if current_feel != null else 1.0,
		"duration": _phase_duration(phase) if current_feel != null else 0.0,
	}


func _fail(reason: String) -> void:
	activation_failed.emit(reason)
	if actor != null:
		actor.trigger_cue(&"ability_failed", {"text": reason, "ability": ability_id})
