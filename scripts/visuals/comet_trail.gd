extends Node2D
class_name CometTrail

# A cheap, shared projectile look: a glowing head, a soft halo and a tapering
# tail along -x (the projectile rotates this node to face its flight). Set the
# colours per scene; nothing here knows which hero uses it.

@export var length: float = 110.0
@export var width: float = 7.0
@export var head_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var glow_color: Color = Color(0.5, 0.8, 1.0, 0.35)
@export var tail_color: Color = Color(0.4, 0.6, 1.0, 0.0)
## Fraction of the halo size it swells and shrinks by.
@export_range(0.0, 0.5, 0.01) var pulse: float = 0.12
@export var pulse_speed: float = 18.0

var _time: float = 0.0
# One additive material shared by every trail (fewer allocations, and the
# renderer can batch them).
static var _additive: CanvasItemMaterial


func _ready() -> void:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _additive
	_time = randf() * TAU
	set_process(pulse > 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta * pulse_speed
	queue_redraw()


func _draw() -> void:
	var swell := 1.0 + sin(_time) * pulse
	var steps := 7
	for i in steps:
		var a := float(i) / steps
		var b := float(i + 1) / steps
		draw_line(Vector2(-length * a, 0), Vector2(-length * b, 0),
			head_color.lerp(tail_color, b), width * (1.0 - a * 0.75))
	draw_circle(Vector2.ZERO, width * 2.4 * swell, glow_color)
	draw_circle(Vector2.ZERO, width * 1.3 * swell, glow_color.lerp(head_color, 0.5))
	draw_circle(Vector2.ZERO, width * 0.7, head_color)
