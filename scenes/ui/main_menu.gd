extends Control

# Main menu: Play (match setup), Practice (pick a hero, then the training
# grounds), Settings, Quit.

var _first: Button


func _ready() -> void:
	MenuUI.setup_screen(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(MenuUI.title("MOTE GARDEN"))
	var sub := MenuUI.label("Wake the Dreamer", 24, Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())
	_first = MenuUI.button("Play", GameState.goto_match_setup)
	box.add_child(_first)
	box.add_child(MenuUI.button("Practice", GameState.goto_practice_select))
	box.add_child(MenuUI.button("Settings", _open_settings))
	box.add_child(MenuUI.button("Quit", get_tree().quit))
	add_child(MenuUI.centered(box))
	_first.grab_focus.call_deferred()


func _open_settings() -> void:
	var settings := SettingsPanel.new()
	settings.closed.connect(_first.grab_focus)
	add_child(settings)
