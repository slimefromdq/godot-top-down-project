extends CanvasLayer
class_name MatchHud

# Match HUD: the clock at top centre (with empty slots either side for the
# two wake meters), the local player's gold, level and XP bar to the left of
# the ability bar, and a respawn countdown while they're dead.
#
# Read-only: it listens to the MatchManager and polls the player each frame.
# Hides itself when the scene has no MatchManager.

## Width kept free on each side of the clock for the wake meters (M3).
@export var wake_slot_width: float = 320.0
@export var gold_color := Color("fbd34d")
@export var xp_color := Color("a78bfa")

var match_manager: MatchManager

var _clock_label: Label
var _state_label: Label
var _level_label: Label
var _gold_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _respawn_label: Label
## Left/right of the clock, empty until the wake meters arrive.
var wake_slot_a: Control
var wake_slot_b: Control


func _ready() -> void:
	layer = 5
	_build()
	_bind.call_deferred()


func _bind() -> void:
	match_manager = MatchManager.find(get_tree())
	visible = match_manager != null


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func _process(_delta: float) -> void:
	if match_manager == null or not is_instance_valid(match_manager):
		return
	_clock_label.text = clock_text()
	match match_manager.state:
		MatchManager.State.WARMUP:
			_state_label.text = "Starts in %d" % ceili(match_manager.warmup_left)
		MatchManager.State.ENDED:
			_state_label.text = "%s wins" % MatchManager.team_name(match_manager.winner)
		_:
			_state_label.text = ""
	var hero := get_player()
	if hero == null or not match_manager.has_hero(hero):
		return
	_level_label.text = "Lv %d" % hero.get_level()
	_level_label.modulate = MatchManager.team_color(hero.team)
	_gold_label.text = "%d" % floori(match_manager.get_gold(hero))
	if match_manager.is_max_level(hero):
		_xp_bar.value = 1.0
		_xp_label.text = "MAX"
	else:
		var need := match_manager.get_xp_to_next(hero)
		_xp_bar.value = match_manager.get_xp(hero) / need if need > 0.0 else 1.0
		_xp_label.text = "%d / %d" % [floori(match_manager.get_xp(hero)), roundi(need)]
	var respawn := match_manager.get_respawn_left(hero)
	_respawn_label.visible = hero.health_component.is_dead() and respawn > 0.0
	_respawn_label.text = "Respawning in %d" % ceili(respawn)


func clock_text() -> String:
	var seconds := floori(match_manager.clock)
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _build() -> void:
	# Top centre: [wake slot A] [clock] [wake slot B]
	var top := HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 12
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override(&"separation", 16)
	add_child(top)
	wake_slot_a = _slot("WakeSlotA")
	top.add_child(wake_slot_a)
	var clock_box := VBoxContainer.new()
	clock_box.custom_minimum_size.x = 140
	clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label = _label(34)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_box.add_child(_clock_label)
	_state_label = _label(16)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_box.add_child(_state_label)
	top.add_child(clock_box)
	wake_slot_b = _slot("WakeSlotB")
	top.add_child(wake_slot_b)

	# Bottom, left of the ability bar (which spans -250..250 from centre).
	var economy := VBoxContainer.new()
	economy.name = "Economy"
	economy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	economy.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	economy.offset_left = -510
	economy.offset_right = -300
	economy.offset_top = -110
	economy.offset_bottom = -24
	economy.alignment = BoxContainer.ALIGNMENT_END
	add_child(economy)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	_level_label = _label(22)
	row.add_child(_level_label)
	var coin := _label(22)
	coin.text = "●"
	coin.modulate = gold_color
	row.add_child(coin)
	_gold_label = _label(22)
	_gold_label.modulate = gold_color
	row.add_child(_gold_label)
	economy.add_child(row)
	_xp_bar = ProgressBar.new()
	_xp_bar.max_value = 1.0
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(210, 14)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = xp_color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(4)
	_xp_bar.add_theme_stylebox_override(&"fill", fill)
	_xp_bar.add_theme_stylebox_override(&"background", back)
	economy.add_child(_xp_bar)
	_xp_label = _label(12)
	economy.add_child(_xp_label)

	_respawn_label = _label(40)
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.visible = false
	add_child(_respawn_label)


func _slot(slot_name: String) -> Control:
	var slot := Control.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(wake_slot_width, 48)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
