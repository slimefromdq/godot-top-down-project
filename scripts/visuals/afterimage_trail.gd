extends Node2D

# Attach to an actor (VisualCue.attach_to_actor = true) to leave fading
# copies of its body behind, e.g. for a dash. Reads the body from
# context.visuals, so it works with any sprite a VisualProfile sets up.

@export var interval: float = 0.025
@export var fade_time: float = 0.25
@export var ghost_color: Color = Color(0.5, 0.9, 1.0, 0.7)

var _visuals: VisualsComponent
var _time_left_to_spawn: float = 0.0


func setup_cue(context: Dictionary) -> void:
	_visuals = context.get("visuals")
	rotation = 0.0


func _process(delta: float) -> void:
	_time_left_to_spawn -= delta
	if _time_left_to_spawn > 0.0 or _visuals == null or not is_instance_valid(_visuals):
		return
	_time_left_to_spawn = interval

	var ghost := _visuals.make_body_snapshot()
	if ghost == null:
		return
	ghost.modulate = ghost_color
	get_tree().current_scene.add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, fade_time)
	tween.tween_callback(ghost.queue_free)


func stop_and_free(_fade_time: float = 0.0) -> void:
	queue_free()
