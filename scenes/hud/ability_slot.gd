extends Control
class_name AbilitySlot

# One ability button on the HUD: icon (or name), key prompt, cooldown shade
# and a red flash when a cast fails. Guns (RangedAttackAbility with a
# magazine) add an ammo count and a reload sweep; any ability that is
# charging shows a charge bar above the slot, flashing in its perfect window.

const SIZE := Vector2(96, 96)
const CHARGE_BAR_HEIGHT := 8.0
const CHARGE_BAR_GAP := 6.0

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

	var gun := ability as RangedAttackAbility
	if gun != null and gun.has_magazine():
		_draw_ammo(gun)
	var pips := ability.get_hud_pips()
	if pips.y > 0:
		_draw_pips(pips.x, pips.y)

	var ratio := ability.get_cooldown_ratio()
	if ratio > 0.0:
		# Dark shade that drains downward as the ability comes back.
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE.x, SIZE.y * ratio)), Color(0, 0, 0, 0.6))
		_draw_centered("%.1f" % ability.cooldown_remaining, center + Vector2(0, -14), 22, Color(1, 1, 1, 0.95))

	var border := Color(0.5, 0.8, 1.0) if ratio <= 0.0 else Color(0.35, 0.35, 0.4)
	border = border.lerp(Color(1, 0.3, 0.3), _fail_flash).lerp(Color.WHITE, _ready_pulse)
	draw_rect(rect, border, false, 3.0 + 3.0 * (_fail_flash + _ready_pulse))

	_draw_centered(_key_text(), Vector2(center.x, SIZE.y - 8), 14, Color(1, 0.9, 0.5))

	if ability.is_charging():
		_draw_charge()


# Reload: a bright sweep filling up from the bottom, like the cooldown shade
# in reverse. Ammo: "current/max" in the top corner, red when empty.
func _draw_ammo(gun: RangedAttackAbility) -> void:
	if gun.is_reloading():
		var fill := SIZE.y * gun.get_reload_ratio()
		draw_rect(Rect2(0, SIZE.y - fill, SIZE.x, fill), Color(0.5, 0.8, 1.0, 0.25))
		_draw_centered("R", Vector2(SIZE.x / 2.0, SIZE.y / 2.0 - 10), 20, Color(0.6, 0.85, 1.0))
	if gun.is_regen() and gun.get_regen_ratio() > 0.0:
		# The next round coming back: a thin bar along the bottom edge.
		draw_rect(Rect2(4, SIZE.y - 26, (SIZE.x - 8) * gun.get_regen_ratio(), 4), Color(0.7, 0.85, 1.0, 0.9))
	var color := Color(1, 0.35, 0.3) if gun.get_ammo() == 0 else Color.WHITE
	_draw_centered("%d/%d" % [gun.get_ammo(), gun.get_max_ammo()], Vector2(SIZE.x / 2.0, 18), 15, color)


# A row of pips along the top: filled = current, hollow = empty.
func _draw_pips(current: int, maximum: int) -> void:
	var spacing := minf(18.0, (SIZE.x - 16.0) / maximum)
	for i in maximum:
		var at := Vector2(SIZE.x / 2.0 + (i - (maximum - 1) / 2.0) * spacing, 14.0)
		if i < current:
			draw_circle(at, 6.0, Color(1.0, 0.85, 0.3))
		else:
			draw_arc(at, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.5), 2.0)


# A bar just above the slot. It turns gold at full charge and flashes white
# while a release would be perfect.
func _draw_charge() -> void:
	var y := -CHARGE_BAR_GAP - CHARGE_BAR_HEIGHT
	var ratio := ability.get_charge_ratio()
	draw_rect(Rect2(0, y, SIZE.x, CHARGE_BAR_HEIGHT), Color(0, 0, 0, 0.7))
	var color := Color(0.5, 0.8, 1.0) if ratio < 1.0 else Color(1.0, 0.8, 0.3)
	if ability.is_in_perfect_window():
		color = Color.WHITE if int(Time.get_ticks_msec() / 60) % 2 == 0 else Color(1.0, 0.95, 0.5)
		draw_rect(Rect2(-3, y - 3, SIZE.x + 6, CHARGE_BAR_HEIGHT + 6), Color(1, 1, 1, 0.8), false, 2.0)
	draw_rect(Rect2(0, y, SIZE.x * ratio, CHARGE_BAR_HEIGHT), color)


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
