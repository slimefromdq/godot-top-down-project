extends Ability
class_name DashAbility

# MOVEMENT: a short, fast burst in the direction you are moving (or toward the
# cursor when standing still), with brief invulnerability.
#
# Cues: <ability_id> at the start position, <ability_id>_end at the landing
# spot. A VisualCue with "attach" and a duration works well for trails.

@export var distance: float = 320.0
@export var duration: float = 0.16
## Invulnerability window. Slightly longer than the dash feels fair.
@export var invulnerability: float = 0.22


func _activate(target_position: Vector2) -> String:
	var direction := actor.move_direction
	if direction == Vector2.ZERO:
		direction = (target_position - actor.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = actor.aim_direction

	actor.movement_component.start_forced_move(direction * distance / duration, duration)
	actor.health_component.set_invulnerable_for(invulnerability)
	actor.trigger_cue(ability_id, {"direction": direction, "duration": duration})

	# Pausable timer, so pausing mid-dash doesn't fire the end cue early.
	actor.get_tree().create_timer(duration, false).timeout.connect(_on_dash_finished)
	return ""


func _on_dash_finished() -> void:
	if is_instance_valid(actor):
		actor.trigger_cue(StringName(str(ability_id) + "_end"))
