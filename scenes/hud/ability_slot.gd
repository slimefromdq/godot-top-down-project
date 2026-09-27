extends Control
class_name AbilitySlot

# One ability button on the HUD: icon (or name), key prompt, cooldown shade
# and a red flash when a cast fails. A match ultimate (UltimateCharge) shows
# its charge instead: a gold fill rising from the bottom and a percentage,
# and a glowing border once full. Guns (RangedAttackAbility with a
# magazine) add an ammo count and a reload sweep; any ability that is
# charging shows a charge bar above the slot, flashing in its perfect window.

const SIZE := Vector2(96, 96)
const CHARGE_BAR_HEIGHT := 8.0
const CHARGE_BAR_GAP := 6.0

var ability: Ability
var _fail_flash: float = 0.0
var _ready_pulse: float = 0.0
var _ult_was_full := false


func setup(for_ability: Ability) -> void:
	ability = for_ability
	custom_minimum_size = SIZE
	tooltip_text = "%s\n%s" % [ability.display_name, ability.description]
	ability.activation_failed.connect(func(_reason): _fail_flash = 1.0)
	ability.cooldown_finished.connect(func(): _ready_pulse = 1.0)


func _process(delta: float) -> void:
	_fail_flash = max(_fail_flash - delta * 4.0, 0.0)
	_ready_pulse = max(_ready_pulse - delta * 3.0, 0.0)
	if ability != null:
		var full := ability.get_ultimate_charge() >= 1.0
		if full and not _ult_was_full:
			_ready_pulse = 1.0
		_ult_was_full = full
	queue_redraw()


func _draw() -> void:
	if ability == null:
		return
	var rect := Rect2(Vector2.ZERO, SIZE)
	var center := SIZE / 2.0
	AeroDraw.gloss_rect(self, rect, Color(0.12, 0.42, 0.66, 0.88), 14.0)

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
	var meter := ability.get_hud_meter()
	if meter >= 0.0:
		# A thin bar along the bottom edge (hunger, heat ...).
		draw_rect(Rect2(4, SIZE.y - 30, SIZE.x - 8, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(4, SIZE.y - 30, (SIZE.x - 8) * clampf(meter, 0.0, 1.0), 6), Color(0.85, 0.15, 0.25, 0.95))

	var ratio := ability.get_cooldown_ratio()
	var ult := ability.get_ultimate_charge()
	if ult >= 0.0 and ratio > 0.0:
		_draw_shade(ratio)
		var fill := SIZE.y * ult
		draw_rect(Rect2(0, SIZE.y - fill, SIZE.x, fill), Color(1.0, 0.8, 0.3, 0.3))
		_draw_centered("%d%%" % floori(ult * 100.0), center + Vector2(0, -14), 22, Color(1.0, 0.9, 0.6))
	elif ratio > 0.0:
		# Dark shade that drains downward as the ability comes back.
		_draw_shade(ratio)
		_draw_centered("%.1f" % ability.cooldown_remaining, center + Vector2(0, -14), 22, Color(1, 1, 1, 0.95))

	var border := Color(0.55, 0.9, 1.0) if ratio <= 0.0 else Color(0.62, 0.72, 0.8)
	if ult >= 1.0 or (ult >= 0.0 and ratio <= 0.0):
		var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		border = Color(1.0, 0.8, 0.3).lerp(Color.WHITE, glow * 0.5)
	border = border.lerp(Color(1, 0.3, 0.3), _fail_flash).lerp(Color.WHITE, _ready_pulse)
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = border
	edge.set_border_width_all(int(3.0 + 3.0 * (_fail_flash + _ready_pulse)))
	edge.set_corner_radius_all(14)
	edge.anti_aliasing = true
	draw_style_box(edge, rect)

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
	var radius := minf(6.0, spacing * 0.4)
	for i in maximum:
		var at := Vector2(SIZE.x / 2.0 + (i - (maximum - 1) / 2.0) * spacing, 14.0)
		if i < current:
			AeroDraw.gloss_circle(self, at, radius, Color(1.0, 0.85, 0.3))
		else:
			draw_arc(at, radius, 0.0, TAU, 16, Color(1, 1, 1, 0.5), 2.0)


# A bar just above the slot. It turns gold at full charge and flashes white
# while a release would be perfect.
func _draw_charge() -> void:
	var y := -CHARGE_BAR_GAP - CHARGE_BAR_HEIGHT
	var ratio := ability.get_charge_ratio()
	AeroDraw.gloss_rect(self, Rect2(0, y, SIZE.x, CHARGE_BAR_HEIGHT), Color(0.05, 0.15, 0.28, 0.8), 4.0)
	var color := Color(0.5, 0.8, 1.0) if ratio < 1.0 else Color(1.0, 0.8, 0.3)
	if ability.is_in_perfect_window():
		color = Color.WHITE if int(Time.get_ticks_msec() / 60) % 2 == 0 else Color(1.0, 0.95, 0.5)
		draw_rect(Rect2(-3, y - 3, SIZE.x + 6, CHARGE_BAR_HEIGHT + 6), Color(1, 1, 1, 0.8), false, 2.0)
	if ratio > 0.05:
		AeroDraw.gloss_rect(self, Rect2(0, y, SIZE.x * ratio, CHARGE_BAR_HEIGHT), color, 4.0)


# Cooldown shade: a smoky glass pane that drains downward.
func _draw_shade(ratio: float) -> void:
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0.03, 0.1, 0.2, 0.6)
	shade.set_corner_radius_all(14)
	shade.corner_radius_bottom_left = 14 if ratio >= 0.9 else 0
	shade.corner_radius_bottom_right = shade.corner_radius_bottom_left
	draw_style_box(shade, Rect2(Vector2.ZERO, Vector2(SIZE.x, SIZE.y * ratio)))


func _draw_centered(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(font, baseline_center - Vector2(width / 2.0, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.04, 0.16, 0.3))
	draw_string(font, baseline_center - Vector2(width / 2.0, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _key_text() -> String:
	if ability.input_action == &"" or not InputMap.has_action(ability.input_action):
		return ""
	var events := InputMap.action_get_events(ability.input_action)
	if events.is_empty():
		return ""
	return events[0].as_text().replace(" - Physical", "").replace(" (Physical)", "")
