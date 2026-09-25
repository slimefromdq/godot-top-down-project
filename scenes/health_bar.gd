extends ProgressBar
class_name HealthBar

# HP bar with a shield overlay: shields (StatusEffect.shield_amount) show
# as a pale segment after the current health. When health + shield would
# overflow max HP the bar rescales so the whole shield stays visible.

@export var health_component: HealthComponent
@export var shield_color: Color = Color(0.85, 0.95, 1.0, 0.95)

var _shield: float = 0.0
var _overlay: Control


func _ready() -> void:
	health_component.health_changed.connect(_on_health_changed)
	# A child draws after (over) the bar's own fill.
	_overlay = Control.new()
	_overlay.name = "ShieldOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_shield)
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


func _draw_shield() -> void:
	if _shield <= 0.0 or max_value <= 0.0:
		return
	var width := size.x
	var start := width * float(value / max_value)
	var length := width * _shield / float(max_value)
	_overlay.draw_rect(Rect2(start, 0.0, length, size.y), shield_color)


func get_shield() -> float:
	return _shield
