extends SceneTree

# Builds resources/ui/aero_theme.tres, the project-wide UI theme (glossy aqua
# buttons, glass panels, bubbly bars). Edit the colours here and re-run:
#   godot --headless --script res://tools/visuals/build_aero_theme.gd

const OUT := "res://resources/ui/aero_theme.tres"

const AQUA := Color(0.16, 0.56, 0.86)
const GLASS := Color(0.08, 0.3, 0.5, 0.82)
const INK := Color(0.04, 0.16, 0.3)


func _init() -> void:
	var theme := Theme.new()
	theme.default_font_size = 18

	theme.set_stylebox(&"normal", &"Button", _gloss(AQUA))
	theme.set_stylebox(&"hover", &"Button", _gloss(AQUA.lightened(0.18)))
	theme.set_stylebox(&"pressed", &"Button", _gloss(AQUA.darkened(0.2), true))
	theme.set_stylebox(&"disabled", &"Button", _gloss(Color(0.55, 0.62, 0.68, 0.8)))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1, 1, 1, 0.9)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(16)
	focus.set_expand_margin_all(3)
	theme.set_stylebox(&"focus", &"Button", focus)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		theme.set_color(c, &"Button", Color.WHITE)
	theme.set_color(&"font_outline_color", &"Button", INK)
	theme.set_constant(&"outline_size", &"Button", 4)

	var panel := _gloss(GLASS)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(16)
	theme.set_stylebox(&"panel", &"Panel", panel)
	theme.set_stylebox(&"panel", &"PanelContainer", panel)
	theme.set_stylebox(&"panel", &"PopupPanel", panel)
	theme.set_stylebox(&"panel", &"TooltipPanel", panel)

	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color(0.05, 0.18, 0.32, 0.6)
	bar_back.border_color = Color(1, 1, 1, 0.55)
	bar_back.set_border_width_all(1)
	bar_back.set_corner_radius_all(7)
	theme.set_stylebox(&"background", &"ProgressBar", bar_back)
	var bar_fill := _gloss(Color(0.3, 0.85, 0.55))
	bar_fill.set_corner_radius_all(7)
	bar_fill.set_content_margin_all(0)
	theme.set_stylebox(&"fill", &"ProgressBar", bar_fill)

	theme.set_color(&"font_outline_color", &"Label", INK)

	var err := ResourceSaver.save(theme, OUT)
	print("Saved %s (%s)" % [OUT, error_string(err)])
	quit(err)


# A pill with a bright top rim, darker bottom edge and a soft drop shadow.
func _gloss(base: Color, pressed := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = base
	box.set_corner_radius_all(16)
	box.border_color = base.lightened(0.55) if not pressed else base.darkened(0.3)
	box.border_width_top = 3
	box.border_width_left = 1
	box.border_width_right = 1
	box.border_width_bottom = 2
	box.border_blend = true
	box.shadow_color = Color(0.02, 0.12, 0.25, 0.35)
	box.shadow_size = 0 if pressed else 5
	box.shadow_offset = Vector2(0, 3)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.anti_aliasing = true
	return box
