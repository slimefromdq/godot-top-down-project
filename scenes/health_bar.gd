extends ProgressBar
class_name HealthBar

# HP bar with a shield overlay: shields (StatusEffect.shield_amount) show
# as a pale segment after the current health. When health + shield would
# overflow max HP the bar rescales so the whole shield stays visible.
#
# The exact HP ("412 / 600", plus "+80" shield) is written on the bar, and
# when the owner has a level (a Hero) a level badge sits at its left, so
# enemy levels can be read at a glance.

@export var health_component: HealthComponent
@export var shield_color: Color = Color(0.85, 0.95, 1.0, 0.95)
@export var show_numbers: bool = true
@export var show_level: bool = true
@export var number_font_size: int = 12
@export var level_font_size: int = 13

var _shield: float = 0.0
var _overlay: Control


func _ready() -> void:
	health_component.health_changed.connect(_on_health_changed)
	# A child draws after (over) the bar's own fill.
	_overlay = Control.new()
	_overlay.name = "ShieldOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	var status := health_component.status_component
	if status != null:
		status.shield_changed.connect(_on_shield_changed)
	_refresh()


func _on_health_changed(_current: float, _maximum: float) -> void:
	_refresh()


func _on_shield_changed(total: float) -> void:
	_shield = total
	_refresh()


func _refresh() -> void:
	var current := health_component.current_health
	max_value = maxf(health_component.max_health, current + _shield)
	value = current
	_overlay.queue_redraw()


var _shown_level: int = -1


func _process(_delta: float) -> void:
	# Levels change without a signal on the bar's side; redraw only on change.
	var level := get_owner_level()
	if level != _shown_level:
		_shown_level = level
		_overlay.queue_redraw()


## The owner's level, or -1 when it has none (dummies, monsters).
func get_owner_level() -> int:
	var owner_actor := get_parent()
	if not show_level or not owner_actor is Hero:
		return -1
	return (owner_actor as Hero).get_level()


## The text written on the bar ("412 / 600", "+80" with a shield).
func get_hp_text() -> String:
	var text := "%d / %d" % [ceili(health_component.current_health - 0.01), ceili(health_component.max_health - 0.01)]
	if _shield > 0.0:
		text += "  +%d" % roundi(_shield)
	return text


func _draw_overlay() -> void:
	if _shield > 0.0 and max_value > 0.0:
		var width := size.x
		var start := width * float(value / max_value)
		var length := width * _shield / float(max_value)
		_overlay.draw_rect(Rect2(start, 0.0, length, size.y), shield_color)
	var font := get_theme_default_font()
	if show_numbers:
		var text := get_hp_text()
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size)
		var at := Vector2((size.x - text_size.x) / 2.0, (size.y + font.get_ascent(number_font_size) - font.get_descent(number_font_size)) / 2.0)
		_overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, 4, Color(0, 0, 0, 0.9))
		_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, number_font_size, Color.WHITE)
	var level := get_owner_level()
	if level >= 0:
		var badge := Rect2(-size.y - 4.0, 0.0, size.y, size.y)
		_overlay.draw_rect(badge, Color(0.05, 0.08, 0.14, 0.9))
		_overlay.draw_rect(badge, Color(1, 1, 1, 0.8), false, 1.5)
		var text := str(level)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_font_size).x
		var at := Vector2(badge.get_center().x - w / 2.0, (size.y + font.get_ascent(level_font_size) - font.get_descent(level_font_size)) / 2.0)
		_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_font_size, Color("fde68a"))


func get_shield() -> float:
	return _shield
