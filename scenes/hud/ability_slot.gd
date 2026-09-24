extends Control
class_name AbilitySlot

# One ability button on the HUD: icon (or name), key prompt, cooldown shade
# and a red flash when a cast fails.

const SIZE := Vector2(96, 96)

var ability: Ability
var _fail_flash: float = 0.0
var _ready_pulse: float = 0.0


func setup(for_ability: Ability) -> void:
	ability = for_ability
	custom_minimum_size = SIZE
	tooltip_text = "%s\n%s" % [ability.display_name, ability.description]
	ability.activation_failed.connect(func(_reason): _fail_flash = 1.0)
	ability.cooldown_finished.connect(func(): _ready_pulse = 1.0)


func _process(delta: float) -> void:
	_fail_flash = max(_fail_flash - delta * 4.0, 0.0)
	_ready_pulse = max(_ready_pulse - delta * 3.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if ability == null:
		return
	var rect := Rect2(Vector2.ZERO, SIZE)
	var center := SIZE / 2.0
	draw_rect(rect, Color(0.08, 0.09, 0.12, 0.85))

	if ability.icon != null:
		draw_texture_rect(ability.icon, rect.grow(-8), false)
	else:
		_draw_centered(ability.display_name, center + Vector2(0, 6), 13, Color.WHITE)

	var ratio := ability.get_cooldown_ratio()
	if ratio > 0.0:
		# Dark shade that drains downward as the ability comes back.
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE.x, SIZE.y * ratio)), Color(0, 0, 0, 0.6))
		_draw_centered("%.1f" % ability.cooldown_remaining, center + Vector2(0, -14), 22, Color(1, 1, 1, 0.95))

	var border := Color(0.5, 0.8, 1.0) if ratio <= 0.0 else Color(0.35, 0.35, 0.4)
	border = border.lerp(Color(1, 0.3, 0.3), _fail_flash).lerp(Color.WHITE, _ready_pulse)
	draw_rect(rect, border, false, 3.0 + 3.0 * (_fail_flash + _ready_pulse))

	_draw_centered(_key_text(), Vector2(center.x, SIZE.y - 8), 14, Color(1, 0.9, 0.5))


func _draw_centered(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(font, baseline_center - Vector2(width / 2.0, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, baseline_center - Vector2(width / 2.0, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _key_text() -> String:
	if ability.input_action == &"" or not InputMap.has_action(ability.input_action):
		return ""
	var events := InputMap.action_get_events(ability.input_action)
	if events.is_empty():
		return ""
	return events[0].as_text().replace(" - Physical", "").replace(" (Physical)", "")
