extends Camera2D
class_name ShakeCamera

# Trauma-based screen shake. VisualCue.screen_shake calls add_trauma() on the
# active camera, if it has this script.

## Global multiplier; set to 0 for an accessibility "no shake" option.
@export_range(0.0, 2.0, 0.05) var shake_strength: float = 1.0
@export var max_offset: Vector2 = Vector2(24, 18)
@export var decay: float = 2.5

var _trauma: float = 0.0


func add_trauma(amount: float) -> void:
	_trauma = min(_trauma + amount, 1.0)


func _process(delta: float) -> void:
	_trauma = max(_trauma - decay * delta, 0.0)
	var power := _trauma * _trauma * shake_strength
	offset = Vector2(
		max_offset.x * power * randf_range(-1, 1),
		max_offset.y * power * randf_range(-1, 1)
	)
