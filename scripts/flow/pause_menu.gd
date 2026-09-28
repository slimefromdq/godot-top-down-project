extends CanvasLayer
class_name PauseMenu

# Esc in a match or practice: Resume, Settings, Leave match (back to the main
# menu). Pauses the tree while open. The world adds it as its first child so
# that the shop (and anything else later in the tree) sees Esc first.

var _panel: Control
var _resume: Button
var enabled := true


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(MenuUI.THEME):
		_panel.theme = load(MenuUI.THEME)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(shade)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	var panel := MenuUI.panel(32)
	panel.add_child(box)
	var title := MenuUI.label("Paused", 44, MenuUI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_resume = MenuUI.button("Resume", close)
	box.add_child(_resume)
	box.add_child(MenuUI.button("Settings", _open_settings))
	box.add_child(MenuUI.button("Leave match", GameState.leave_match))
	_panel.add_child(MenuUI.centered(panel))
	_panel.visible = false
	add_child(_panel)


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	if is_open() or not enabled:
		return
	_panel.visible = true
	get_tree().paused = true
	_resume.grab_focus()


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	get_tree().paused = false


func _open_settings() -> void:
	var settings := SettingsPanel.new()
	settings.closed.connect(_resume.grab_focus)
	_panel.add_child(settings)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if is_open():
		close()
		get_viewport().set_input_as_handled()
	elif enabled and not get_tree().paused:
		open()
		get_viewport().set_input_as_handled()
