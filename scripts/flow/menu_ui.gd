extends RefCounted
class_name MenuUI

# Small builders shared by the menu screens, so they look alike: the dark
# dreamy backdrop, titles, big buttons and panels.

const THEME := "res://resources/ui/aero_theme.tres"
const BACKDROP := Color("141827")
const PANEL := Color(0.09, 0.1, 0.16, 0.94)
const ACCENT := Color("fde68a")
## Debug autoloads whose overlays (map label, damage meter) are hidden
## while a menu screen is up.
const DEBUG_OVERLAYS := [^"/root/DebugTools", ^"/root/MapSwitcher"]
const ROLE_COLORS := {
	HeroDefinition.Role.TANK: Color("7dd3fc"),
	HeroDefinition.Role.CARRY: Color("fca5a5"),
	HeroDefinition.Role.TEMPO: Color("c4b5fd"),
	HeroDefinition.Role.FLEX: Color("86efac"),
}


## Full-screen root setup: theme and a backdrop behind everything.
static func setup_screen(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(THEME):
		root.theme = load(THEME)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	_set_debug_overlays(root, false)
	root.tree_exiting.connect(_set_debug_overlays.bind(root, true))


static func _set_debug_overlays(node: Node, shown: bool) -> void:
	for path in DEBUG_OVERLAYS:
		var overlay := node.get_node_or_null(path) as CanvasLayer
		if overlay != null:
			overlay.visible = shown


## A flat dark card style (hero cards), with an accent border when selected.
static func card_style(bg: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	if border.a > 0.0:
		style.set_border_width_all(3)
		style.border_color = border
	return style


static func label(text: String, size: int = 20, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 4 if size >= 28 else 0)
	return l


static func title(text: String) -> Label:
	var l := label(text, 56, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, on_pressed: Callable, min_width: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.add_theme_font_size_override(&"font_size", 24)
	b.pressed.connect(on_pressed)
	return b


static func panel(padding: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(14)
	style.set_content_margin_all(padding)
	p.add_theme_stylebox_override(&"panel", style)
	return p


## A labelled row: "Name      [control]".
static func row(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(text, 22)
	l.custom_minimum_size.x = 260
	h.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 320)
	h.add_child(control)
	return h


static func centered(content: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(content)
	return c


static func role_color(role: int) -> Color:
	return ROLE_COLORS.get(role, Color.WHITE)
