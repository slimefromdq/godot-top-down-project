extends Line2D

# A beam from the cue position to context.target_position that thins out and
# fades. Used by the click-cast zap; reusable for lasers, tethers, chains.

@export var lifetime: float = 0.2
## Pixels of random sideways jitter per segment. 0 = a straight beam.
@export var jaggedness: float = 14.0
@export var segments: int = 8


func setup_cue(context: Dictionary) -> void:
	global_position = Vector2.ZERO
	global_rotation = 0.0
	var start: Vector2 = context.get("position", Vector2.ZERO)
	var end: Vector2 = context.get("target_position", start)
	clear_points()
	var normal := (end - start).orthogonal().normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var jitter := 0.0 if i == 0 or i == segments else randf_range(-jaggedness, jaggedness)
		add_point(start.lerp(end, t) + normal * jitter)


func _ready() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "width", 0.0, lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.chain().tween_callback(queue_free)
