extends CanvasLayer
class_name GameOverScreen

# A CanvasLayer draws in screen space, on top of the world, and ignores the
# Camera2D. That keeps this overlay centered no matter where the player died.
#
# The scene root sets process_mode to Always. While the tree is paused,
# every other node stops, but this screen still gets input so the Restart
# button can be clicked.

@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	hide()
	restart_button.pressed.connect(_on_restart_button_pressed)


# The world calls this. The screen doesn't know or care why the game ended,
# so the same screen can be reused later for a victory or timeout.
func show_screen() -> void:
	show()
	# Focusing the button means Enter/Space activates it too, not just a click.
	restart_button.grab_focus()


func _on_restart_button_pressed() -> void:
	# Pausing belongs to the SceneTree, not the current scene, so it survives
	# a reload. Unpause first or the new scene starts frozen.
	get_tree().paused = false
	get_tree().reload_current_scene()
