extends CanvasLayer
class_name GameOverScreen

# A CanvasLayer draws in screen space, on top of the world, and ignores the
# Camera2D. That keeps this overlay centered no matter where the player died.
#
# The scene root sets process_mode to Always. While the tree is paused,
# every other node stops, but this screen still gets input so the Restart
# button can be clicked.

@onready var restart_button: Button = %RestartButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel


func _ready() -> void:
	hide()
	restart_button.pressed.connect(_on_restart_button_pressed)


# The world calls this. The screen doesn't know or care why the game ended:
# the caller passes the title ("YOU DIED", "DAWN VICTORY" ...). Empty keeps
# the scene's own title.
func show_screen(title: String = "", color: Color = Color.WHITE) -> void:
	if title != "":
		title_label.text = title
	title_label.modulate = color
	show()
	# Focusing the button means Enter/Space activates it too, not just a click.
	restart_button.grab_focus()


func _on_restart_button_pressed() -> void:
	# Pausing belongs to the SceneTree, not the current scene, so it survives
	# a reload. Unpause first or the new scene starts frozen.
	get_tree().paused = false
	# Launched from the menus: relaunch with the same hero (a plain reload
	# would bring back the scene's default hero).
	if GameState.in_launched_game:
		GameState.launch()
		return
	get_tree().reload_current_scene()
