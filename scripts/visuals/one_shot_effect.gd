extends Node2D
class_name OneShotEffect

# Drop-in root script for effect scenes. On spawn it restarts every particle
# system and plays every AnimatedSprite2D / AnimationPlayer below it, then
# frees itself after `lifetime`. Build the look however you like underneath.

## Seconds before the effect frees itself. 0 = never (attached effects that
## the VisualsComponent removes).
@export var lifetime: float = 1.0
## AnimationPlayer animation to play, if the scene has one.
@export var animation_name: StringName = &"default"


func _ready() -> void:
	for node in find_children("*", "", true, false):
		if node is GPUParticles2D or node is CPUParticles2D:
			node.emitting = true
			node.restart()
		elif node is AnimatedSprite2D:
			node.play()
		elif node is AnimationPlayer and node.has_animation(animation_name):
			node.play(animation_name)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


# Attached effects are stopped this way so particles fade out instead of
# vanishing mid-air.
func stop_and_free(fade_time: float = 0.5) -> void:
	for node in find_children("*", "", true, false):
		if node is GPUParticles2D or node is CPUParticles2D:
			node.emitting = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)
