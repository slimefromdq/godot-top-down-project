extends Node
class_name MapDebugView

# Playtesting aid. Press M (the debug_map_view action) to zoom the camera
# out to the whole map, press it again to return to the player.
#
# While zoomed out:
#   * nodes in the "map_overview" group are shown (region names, sight lanes);
#   * right-click anywhere to move the player there, to test a spot quickly.
#
# The camera is the player's own Camera2D. For the overview it is detached
# (top_level) so it stops following, then re-attached on the way back.

@export var action: StringName = &"debug_map_view"
@export var transition_time: float = 0.35
## Extra space around the map bounds in overview.
@export var margin: float = 550.0

var _overview := false
var _camera: Camera2D
var _tween: Tween


func is_overview() -> bool:
	return _overview


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(action):
		toggle()
		get_viewport().set_input_as_handled()
	elif _overview and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_move_player_to(_camera.get_global_mouse_position())
		get_viewport().set_input_as_handled()


func toggle() -> void:
	var map := get_tree().get_first_node_in_group(&"game_map") as GameMap
	_camera = get_viewport().get_camera_2d()
	if map == null or _camera == null:
		return
	_overview = not _overview
	get_tree().call_group(&"map_overview", &"set_visible", _overview)

	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _overview:
		var rect := map.bounds.grow(margin)
		rect.position += map.global_position
		var view := get_viewport().get_visible_rect().size
		var fit := minf(view.x / rect.size.x, view.y / rect.size.y)
		var start := _camera.global_position
		_camera.top_level = true
		_camera.global_position = start
		_tween.tween_property(_camera, "global_position", rect.get_center(), transition_time)
		_tween.tween_property(_camera, "zoom", Vector2.ONE * fit, transition_time)
	else:
		var follow := _camera.get_parent() as Node2D
		_tween.tween_property(_camera, "zoom", Vector2.ONE, transition_time)
		if follow != null:
			_tween.tween_property(_camera, "global_position", follow.global_position, transition_time)
		_tween.chain().tween_callback(_reattach_camera)


func _reattach_camera() -> void:
	_camera.top_level = false
	_camera.position = Vector2.ZERO


func _move_player_to(point: Vector2) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	if player == null:
		return
	player.global_position = point
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
