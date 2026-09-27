extends RefCounted
class_name ScreenCull

# Is a spot near what the local camera shows? Animated decorations (jump
# pads, camps, Motes...) ask before queue_redraw(): the renderer already skips
# drawing off-screen items, but a requested redraw still runs _draw() and
# rebuilds the item's geometry every frame. Presentation only.
#
# With no Camera2D (headless tests, tools) everything counts as on screen.

## Pixels around the visible area that still count as on screen.
const MARGIN := 300.0

static var _frame: int = -1
static var _view := Rect2()
static var _has_camera := false


static func is_near(item: CanvasItem, radius: float = 0.0) -> bool:
	if item == null or not item.is_inside_tree():
		return false
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		var viewport := item.get_viewport()
		_has_camera = viewport != null and viewport.get_camera_2d() != null
		if _has_camera:
			_view = viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	if not _has_camera:
		return true
	var at: Vector2 = item.global_position if item is Node2D else Vector2.ZERO
	return _view.grow(MARGIN + radius).has_point(at)
