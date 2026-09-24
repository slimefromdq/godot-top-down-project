extends Node2D

# Floating text for damage numbers and "No target" style messages.
# Context keys: text, color.

@export var rise_distance: float = 60.0
@export var lifetime: float = 0.7


func setup_cue(context: Dictionary) -> void:
	# Text never rotates with the cue direction.
	rotation = 0.0
	position += Vector2(randf_range(-14, 14), -40)
	$Label.text = str(context.get("text", ""))
	$Label.modulate = context.get("color", Color.WHITE)

	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y - rise_distance, lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	tween.chain().tween_callback(queue_free)
