extends Node

const WINDOWED_SIZE := Vector2i(1280, 720)

@onready var player: Actor = $Player
@onready var game_over_screen: GameOverScreen = $GameOverScreen
var pause_menu: PauseMenu
var end_screen: EndMatchScreen


func _ready() -> void:
	# First child, so the shop and HUD see Esc before the pause menu does.
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	move_child(pause_menu, 0)
	end_screen = EndMatchScreen.new()
	add_child(end_screen)
	# The world owns both the player and the UI, so it connects them. The
	# player only reports that it died; it never reaches into the UI itself.
	player.health_component.died.connect(_on_player_died)
	add_to_group(&"player_listeners")
	var match_manager := MatchManager.find(get_tree())
	if match_manager != null:
		on_match_started(match_manager)


# Also called by the debug panel when it starts a match in a sandbox scene.
func on_match_started(match_manager: MatchManager) -> void:
	if not match_manager.match_ended.is_connected(_on_match_ended):
		match_manager.match_ended.connect(_on_match_ended)


# The debug panel can swap the player for another hero.
func on_player_replaced(new_player: Actor) -> void:
	player = new_player
	player.health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	# In a match the MatchManager respawns the player instead.
	if MatchManager.find(get_tree()) != null:
		return
	# Pausing stops every node whose process_mode is Inherit or Pausable:
	# enemies, bullets and timers freeze. GameOverScreen is set to Always.
	pause_menu.close()
	get_tree().paused = true
	game_over_screen.show_screen()


## Wake sequence timings (cosmetic): a slow-motion beat while the Dreamer's
## eyes open, one hit-stop frame, then the dream-shimmer into the victory
## screen.
@export var wake_slowmo_scale: float = 0.3
@export var wake_slowmo_time: float = 1.4
@export var wake_hitstop_time: float = 0.12
@export var wake_shimmer_time: float = 1.1


func _on_match_ended(winner_team: StringName) -> void:
	pause_menu.close()
	pause_menu.enabled = false
	var woken := false
	for node in get_tree().get_nodes_in_group(Dreamer.GROUP):
		woken = woken or (node as Dreamer).woken_by != &""
	if woken:
		await _play_wake_sequence()
	get_tree().paused = true
	# Any match with a manager: the end-of-match screen (MVP, scoreboard).
	var manager := MatchManager.find(get_tree())
	if manager != null:
		end_screen.show_result(GameState.finish_match(manager, winner_team))
		return
	var title := "%s VICTORY" % MatchManager.team_name(winner_team).to_upper()
	game_over_screen.show_screen(title, MatchManager.team_color(winner_team))


func _play_wake_sequence() -> void:
	var tree := get_tree()
	Engine.time_scale = wake_slowmo_scale
	await tree.create_timer(wake_slowmo_time, true, false, true).timeout
	var settings = GameFeel.settings
	if settings == null or settings.hitstop_enabled:
		Engine.time_scale = 0.0
		await tree.create_timer(wake_hitstop_time * (settings.hitstop_scale if settings != null else 1.0),
			true, false, true).timeout
	Engine.time_scale = wake_slowmo_scale
	var shimmer := DreamShimmer.new()
	add_child(shimmer)
	await shimmer.play(wake_shimmer_time)
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0


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
