extends Node
class_name Ability

# Base class for every ability. Add an Ability node as a child of an actor's
# AbilityController. Input never lives here: the player script (or enemy AI)
# asks the controller to activate it, and the ability decides whether it can.
#
# Presentation: a successful cast triggers a cue named after ability_id on the
# actor (e.g. "phase_dash"). Map that name in the actor's VisualProfile and
# AudioProfile to give the ability its look and sound. A failed cast triggers
# "ability_failed" with context.text set to the reason.

signal activated
signal activation_failed(reason: String)
signal cooldown_finished

## Cue name and stable identifier. Keep it snake_case.
@export var ability_id: StringName = &"ability"
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Input action that requests this ability. Configure it in Project Settings > Input Map.
@export var input_action: StringName
@export var cooldown: float = 5.0

var actor: Actor
var cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	if cooldown_remaining <= 0.0:
		return
	cooldown_remaining -= delta
	if cooldown_remaining <= 0.0:
		cooldown_remaining = 0.0
		cooldown_finished.emit()


func is_ready() -> bool:
	return cooldown_remaining <= 0.0


# 0 when ready, 1 right after casting. Handy for cooldown sweeps.
func get_cooldown_ratio() -> float:
	if cooldown <= 0.0:
		return 0.0
	return cooldown_remaining / cooldown


# target_position is the cursor for the player, or the aim point for AI.
func try_activate(target_position: Vector2) -> bool:
	if not is_ready():
		return false
	if actor.health_component.is_dead():
		return false
	# Mid-air, a dash or pull would replace the launch arc. Shooting still works.
	if actor.is_airborne():
		return false

	var failure := _activate(target_position)
	if failure != "":
		# Failed casts cost nothing, so a missed click-target can be retried.
		activation_failed.emit(failure)
		actor.trigger_cue(&"ability_failed", {"text": failure, "ability": ability_id})
		return false

	cooldown_remaining = cooldown
	activated.emit()
	return true


# Override. Do the work and return "" on success, or a short player-facing
# reason ("No target") on failure. Subclasses trigger their own cue(s).
func _activate(_target_position: Vector2) -> String:
	return ""
