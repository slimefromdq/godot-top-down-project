extends CanvasLayer
class_name BlackMarketPanel

# The Black Market's shop window (the MapEventsHud adds one). Opened with the
# interact key beside the stall. It lists the stock with each item's price in
# CARRIED Motes plus gold, what you are carrying, and why a button is off.
#
# Interruptible: the window closes by itself when you take damage (the
# director's shopping_interrupted), walk out of range, die, or the market
# closes. Buying goes through BlackMarketDirector.purchase(): the panel holds
# no rules of its own.

signal closed

const REFRESH := 0.15

var director: BlackMarketDirector
var manager: MatchManager
## Item buttons by item (for tests).
var buttons: Dictionary = {}

var _root: PanelContainer
var _title: Label
var _carry_label: Label
var _status_label: Label
var _details: Label
var _grid: VBoxContainer
var _refresh_left: float = 0.0
var _hero: Hero
var _notice: String = ""


func _ready() -> void:
	layer = 9
	_build()
	_root.visible = false


func bind(p_manager: MatchManager, p_director: BlackMarketDirector) -> void:
	manager = p_manager
	director = p_director
	director.shopping_interrupted.connect(_on_interrupted)
	director.market_closed.connect(func(_m): close())


func is_open() -> bool:
	return _root.visible


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func open() -> bool:
	var hero := get_player()
	if hero == null or director == null or not director.begin_shopping(hero):
		return false
	_hero = hero
	_notice = ""
	_root.visible = true
	_rebuild()
	_refresh()
	return true


func close() -> void:
	if _root != null and _root.visible:
		_root.visible = false
		if director != null and _hero != null:
			director.end_shopping(_hero)
		closed.emit()
	_hero = null


func _on_interrupted(hero: Hero) -> void:
	if hero == _hero and is_open():
		_root.visible = false
		_hero = null
		closed.emit()
		var announcer := get_tree().get_first_node_in_group(&"match_hud")
		if announcer != null and announcer.get("announcer") != null:
			announcer.announcer.toast("Shopping interrupted!", Color("fb7185"))


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	# Out of range or down: the window shuts (the director owns range too).
	if _hero == null or not is_instance_valid(_hero) or _hero.health_component.is_dead() \
			or not director.is_open() or not director.market.can_interact(_hero):
		close()
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh()


# --- Building -------------------------------------------------------------------

func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "BlackMarket"
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.custom_minimum_size = Vector2(640, 0)
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	_root.add_child(box)
	var header := HBoxContainer.new()
	_title = _label("Black Market", 28)
	_title.modulate = Color("c4b5fd")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)
	_carry_label = _label("", 20)
	box.add_child(_carry_label)
	_status_label = _label("", 15)
	_status_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_status_label)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override(&"separation", 8)
	box.add_child(_grid)
	_details = _label("Hover an item for its numbers.", 15)
	_details.custom_minimum_size = Vector2(0, 60)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)


func _rebuild() -> void:
	buttons.clear()
	for child in _grid.get_children():
		child.queue_free()
	for item in director.get_stock():
		var button := Button.new()
		button.custom_minimum_size = Vector2(600, 62)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_buy.bind(item))
		button.mouse_entered.connect(_show_details.bind(item))
		var tint := StyleBoxFlat.new()
		tint.bg_color = Color(item.color, 0.3)
		tint.set_corner_radius_all(10)
		tint.border_color = item.color
		tint.set_border_width_all(2)
		button.add_theme_stylebox_override(&"normal", tint)
		_grid.add_child(button)
		buttons[item] = button


func _refresh() -> void:
	_refresh_left = REFRESH
	if _hero == null or director == null:
		return
	var carrier := MoteCarrier.find_on(_hero)
	var carried := carrier.get_spendable_count() if carrier != null else 0
	_carry_label.text = "Carrying %d Motes    ● %d gold" % [carried, floori(manager.get_gold(_hero))]
	var left := director.get_time_left()
	_status_label.text = _notice if _notice != "" else \
		"Motes come out of your carried stack, so they will not be banked. Closes in %d s." % ceili(left)
	for item in buttons:
		var button: Button = buttons[item]
		var block := director.get_block_reason(_hero, item)
		var bought := director.bought_count(_hero, item) >= director.get_rules().blackmarket_max_per_item
		button.text = "%s  %s      %d Motes + %d gold%s" % [item.glyph, item.display_name, item.mote_cost, item.gold_cost,
			"      (bought)" if bought else ""]
		button.disabled = block != ""
		button.tooltip_text = item.describe() + ("" if block == "" else "\n\n" + block)


func _show_details(item: BlackMarketItem) -> void:
	var seconds := director.get_rules().item_duration(item)
	var lasts := "instant" if item.effect == SecondWindEffect else "%d s" % roundi(seconds)
	_details.text = "%s  (%d Motes + %d gold, %s)\n%s" % [item.display_name, item.mote_cost, item.gold_cost, lasts, item.describe()]


func _on_buy(item: BlackMarketItem) -> void:
	var reason := director.purchase(_hero, item)
	_notice = "Bought %s!" % item.display_name if reason == "" else reason
	_refresh()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.16, 0.3, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	return label
