extends CanvasLayer

# Autoload "MapSwitcher": press F3 (debug_next_map) to cycle through
# GameRules.test_maps. The local player's level carries over, so you can
# compare the same build on different maps.
#
# A corner label shows the current map and the key.

const LEVEL_KEY := &"level"

var _label: Label
var _carried: Dictionary = {}


func _ready() -> void:
	layer = 20
	# Keep working on the (paused) game-over screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_next_map"):
		next_map()
		get_viewport().set_input_as_handled()


func get_maps() -> PackedStringArray:
	return GameRules.current().test_maps


func next_map() -> void:
	var maps := get_maps()
	if maps.is_empty():
		return
	var current := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	var index := maps.find(current)
	go_to(maps[(index + 1) % maps.size()])


func go_to(path: String) -> void:
	_remember_player()
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	# The new scene is added at the end of this frame; restore after that.
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_player()
	_refresh_label()


func _remember_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	var stats := StatsComponent.find_on(player)
	if stats != null:
		_carried[LEVEL_KEY] = stats.level


func _restore_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	var stats := StatsComponent.find_on(player)
	if stats != null and _carried.has(LEVEL_KEY):
		stats.set_level(_carried[LEVEL_KEY])
		var health := (player as Actor).health_component
		health.reset()


func _refresh_label() -> void:
	var scene := get_tree().current_scene
	var map_name := scene.scene_file_path.get_file().get_basename().replace("_world", "").capitalize() \
		if scene != null else ""
	_label.text = "%s   [F3: next map]" % map_name if get_maps().size() > 1 else ""
