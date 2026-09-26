extends CanvasLayer

# The overlay for the local player's own minigame (MinigameHost opens it only
# for LocalView's viewer). The minigame draws itself into the centre panel
# (MinigameInstance.draw_view); a small live inset in the corner shows the
# real map around the actor, so they know where they are.

const PANEL_SIZE := Vector2(720, 420)
const INSET_SIZE := Vector2i(260, 170)

var host: MinigameHost
var _panel: Node2D
var _inset_camera: Camera2D


func _ready() -> void:
	layer = 45
	_panel = Node2D.new()
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size = INSET_SIZE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = INSET_SIZE
	viewport.world_2d = host.actor.get_world_2d()
	container.add_child(viewport)
	_inset_camera = Camera2D.new()
	_inset_camera.zoom = Vector2(0.25, 0.25)
	viewport.add_child(_inset_camera)
	_layout(container)
	get_viewport().size_changed.connect(_layout.bind(container))


func _layout(container: Control) -> void:
	var screen := get_viewport().get_visible_rect().size
	_panel.position = (screen - PANEL_SIZE) / 2.0
	container.position = _panel.position + Vector2(PANEL_SIZE.x - INSET_SIZE.x - 12, 12)


func _process(_delta: float) -> void:
	if is_instance_valid(host) and is_instance_valid(host.actor):
		_inset_camera.global_position = host.actor.global_position
	_panel.queue_redraw()


func _draw_panel() -> void:
	if not is_instance_valid(host) or not host.is_playing():
		return
	var rect := Rect2(Vector2.ZERO, PANEL_SIZE)
	_panel.draw_rect(rect.grow(6), Color(0.05, 0.02, 0.1, 0.9))
	host.current.draw_view(_panel, rect)
