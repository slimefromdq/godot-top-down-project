extends CanvasLayer
class_name DreamShimmer

# Full-screen dream-shimmer: soft pastel bands sweeping across the screen
# while a glow washes in, used as the transition into the victory screen
# after a Dreamer wakes. Runs while the tree is paused. Cosmetic only.
#
#   var shimmer := DreamShimmer.new(); add_child(shimmer)
#   await shimmer.play(1.2)

var _t := 0.0
var _duration := 1.2
var _canvas: Control


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_shimmer)
	add_child(_canvas)


func play(duration: float) -> void:
	_duration = maxf(duration, 0.05)
	_t = 0.0
	while _t < _duration:
		await get_tree().process_frame
	await get_tree().process_frame


func get_progress() -> float:
	return clampf(_t / _duration, 0.0, 1.0)


func _process(delta: float) -> void:
	# Real time: Engine.time_scale is slowed for the wake.
	_t += delta / maxf(Engine.time_scale, 0.001)
	_canvas.queue_redraw()


func _draw_shimmer() -> void:
	var size := _canvas.size
	var k := get_progress()
	for i in 7:
		var band := fmod(k * 1.6 + i / 7.0, 1.0)
		var x := lerpf(-size.x * 0.4, size.x * 1.2, band)
		var color := Color.from_hsv(fmod(0.72 + i * 0.07, 1.0), 0.35, 1.0, 0.18 * k)
		_canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + size.x * 0.25, 0),
			Vector2(x - size.x * 0.15, size.y), Vector2(x - size.x * 0.4, size.y)]), color)
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.97, 1.0, 0.75 * k * k))
