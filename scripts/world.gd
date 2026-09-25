extends Node

const WINDOWED_SIZE := Vector2i(1280, 720)

@onready var player: Actor = $Player
@onready var game_over_screen: GameOverScreen = $GameOverScreen


func _ready() -> void:
	# The world owns both the player and the UI, so it connects them. The
	# player only reports that it died; it never reaches into the UI itself.
	player.health_component.died.connect(_on_player_died)
	add_to_group(&"player_listeners")


# The debug panel can swap the player for another hero.
func on_player_replaced(new_player: Actor) -> void:
	player = new_player
	player.health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	# Pausing stops every node whose process_mode is Inherit or Pausable:
	# enemies, bullets and timers freeze. GameOverScreen is set to Always.
	get_tree().paused = true
	game_over_screen.show_screen()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var toggled_with_f11 := key_event.keycode == KEY_F11
	var toggled_with_alt_enter := key_event.alt_pressed and key_event.keycode == KEY_ENTER
	if toggled_with_f11 or toggled_with_alt_enter:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	var is_fullscreen := current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(WINDOWED_SIZE)
		_center_window()
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var centered_position := usable_rect.position + (usable_rect.size - WINDOWED_SIZE) / 2
	DisplayServer.window_set_position(centered_position)
