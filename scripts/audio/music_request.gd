extends Node
class_name MusicRequest

# Drop this node into a level (or a boss arena, a shop, a menu) to request
# music for as long as the node is in the tree. Highest priority wins.

@export var stream: AudioStream
@export var priority: int = 0
@export var fade_time: float = 1.0


func _enter_tree() -> void:
	if stream != null:
		AudioManager.request_music(self, stream, priority, fade_time)


func _exit_tree() -> void:
	AudioManager.release_music(self, fade_time)
