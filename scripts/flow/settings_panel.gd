extends Control
class_name SettingsPanel

# The settings screen as an overlay (main menu and pause menu): volumes and
# fullscreen, saved through UserSettings when closed.

signal closed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := MenuUI.panel(32)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	panel.add_child(box)
	box.add_child(MenuUI.label("Settings", 40, MenuUI.ACCENT))
	for key in [&"master", &"music", &"sfx"]:
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = UserSettings.volumes[key]
		slider.custom_minimum_size.y = 32
		slider.value_changed.connect(func(v: float): UserSettings.set_volume(key, v))
		box.add_child(MenuUI.row("%s volume" % str(key).capitalize() if key != &"sfx" else "Effects volume", slider))
	var full := CheckBox.new()
	full.button_pressed = UserSettings.fullscreen
	full.toggled.connect(UserSettings.set_fullscreen)
	box.add_child(MenuUI.row("Fullscreen", full))
	box.add_child(MenuUI.button("Back", close))
	add_child(MenuUI.centered(panel))


func close() -> void:
	UserSettings.save()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
