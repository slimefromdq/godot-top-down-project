extends CanvasLayer
class_name ShopPanel

# The shop window (the MatchHud adds one). B (shop_toggle) opens and closes
# it, Escape closes it. One row per item family (ShopCatalog order), one
# column per tier; each button shows the item's price for you right now (a
# component you own comes off it). Hovering shows the item's real numbers
# (ItemData.describe()). Your items are listed underneath: click one to
# sell it. The active item has its own slot and key.
#
# Buying needs the shop: in your base, or anywhere while dead (see
# MatchManager.get_shop_block_reason). The window can be opened anywhere to
# browse; its buttons explain why they're off.
#
# Read-only apart from buy() / sell() on the player's ItemInventory.

const TOGGLE_ACTION := &"shop_toggle"
const REFRESH := 0.2

var match_manager: MatchManager
var inventory: ItemInventory
## Item buttons by item (for tests).
var buttons: Dictionary = {}

var _root: PanelContainer
var _gold_label: Label
var _status_label: Label
var _details: Label
var _grid: GridContainer
var _owned_row: HBoxContainer
var _active_row: HBoxContainer
var _refresh_left: float = 0.0
var _built_for: ShopCatalog


func _ready() -> void:
	layer = 8
	_build()
	close()


func bind(manager: MatchManager) -> void:
	match_manager = manager


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_refresh()


func close() -> void:
	_root.visible = false


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func _unhandled_input(event: InputEvent) -> void:
	if match_manager == null:
		return
	if InputMap.has_action(TOGGLE_ACTION) and event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh()


func _find_inventory() -> ItemInventory:
	var hero := get_player()
	return ItemInventory.find_on(hero) if hero != null else null


# --- Building --------------------------------------------------------------------

func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "Shop"
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.custom_minimum_size = Vector2(900, 0)
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	_root.add_child(box)

	var header := HBoxContainer.new()
	var title := _label("Shop", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = _label("", 24)
	_gold_label.modulate = Color("fbd34d")
	header.add_child(_gold_label)
	var close_button := Button.new()
	close_button.text = "Close (B)"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	_status_label = _label("", 16)
	box.add_child(_status_label)

	_grid = GridContainer.new()
	_grid.columns = 1 + ItemData.TIER_NAMES.size()
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	box.add_child(_grid)

	_details = _label("Hover an item for its numbers.", 15)
	_details.custom_minimum_size = Vector2(0, 92)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)

	box.add_child(_label("Your items (click to sell)", 16))
	_owned_row = HBoxContainer.new()
	_owned_row.add_theme_constant_override(&"separation", 6)
	_owned_row.custom_minimum_size = Vector2(0, 44)
	box.add_child(_owned_row)
	_active_row = HBoxContainer.new()
	_active_row.add_theme_constant_override(&"separation", 6)
	box.add_child(_active_row)


func _rebuild_grid(catalog: ShopCatalog) -> void:
	_built_for = catalog
	buttons.clear()
	for child in _grid.get_children():
		child.queue_free()
	if catalog == null:
		return
	_grid.add_child(_label("", 14))
	for tier_name in ItemData.TIER_NAMES:
		var head := _label(tier_name, 16)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(head)
	for family in catalog.get_family_order():
		var row_title := _label(catalog.get_family_title(family), 18)
		row_title.custom_minimum_size = Vector2(110, 0)
		_grid.add_child(row_title)
		for tier in ItemData.TIER_NAMES.size():
			var items := catalog.get_items(family, tier)
			var cell := VBoxContainer.new()
			for item in items:
				var button := Button.new()
				button.custom_minimum_size = Vector2(240, 64)
				button.pressed.connect(_on_buy.bind(item))
				button.mouse_entered.connect(_show_details.bind(item))
				var tint := StyleBoxFlat.new()
				tint.bg_color = Color(item.color, 0.35)
				tint.set_corner_radius_all(10)
				tint.border_color = item.color
				tint.set_border_width_all(2)
				button.add_theme_stylebox_override(&"normal", tint)
				cell.add_child(button)
				buttons[item] = button
			_grid.add_child(cell)


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_left = REFRESH
	inventory = _find_inventory()
	var catalog := match_manager.get_rules().shop_catalog if match_manager != null else null
	if catalog != _built_for:
		_rebuild_grid(catalog)
	if inventory == null:
		_status_label.text = "No shop here."
		return
	_gold_label.text = "● %d" % floori(inventory.get_gold())
	var reason := inventory.get_shop_block_reason()
	_status_label.text = "In base: buy and sell." if reason == "" else reason + " (you can still browse)."
	if inventory.hero.health_component.is_dead() and reason == "":
		_status_label.text = "Respawning: buy and sell from here."
	for item in buttons:
		var button: Button = buttons[item]
		var block := inventory.get_buy_block_reason(item)
		var price := inventory.price_of(item)
		button.text = "%s %s\n%d gold%s" % [item.glyph, item.display_name, price,
			"" if price == item.cost else "  (%d)" % item.cost]
		button.disabled = block != ""
		button.tooltip_text = item.describe() + ("" if block == "" else "\n\n" + block)
	for child in _owned_row.get_children() + _active_row.get_children():
		child.queue_free()
	for item in inventory.get_passive_items():
		_owned_row.add_child(_owned_button(item))
	for i in maxi(inventory.get_rules().item_slots - inventory.get_passive_items().size(), 0):
		_owned_row.add_child(_empty_slot("empty"))
	var active_title := _label("Active (%s):" % _key_text(), 16)
	_active_row.add_child(active_title)
	var active := inventory.get_active_item()
	_active_row.add_child(_owned_button(active) if active != null else _empty_slot("none"))


func _owned_button(item: ItemData) -> Button:
	var button := Button.new()
	button.text = "%s  +%d" % [item.display_name, inventory.sell_value_of(item)]
	button.tooltip_text = "Sell for %d gold\n\n%s" % [inventory.sell_value_of(item), item.describe()]
	button.disabled = inventory.get_sell_block_reason(item) != ""
	button.pressed.connect(_on_sell.bind(item))
	button.mouse_entered.connect(_show_details.bind(item))
	return button


func _empty_slot(text: String) -> Label:
	var label := _label("[ %s ]" % text, 14)
	label.modulate = Color(1, 1, 1, 0.5)
	return label


func _show_details(item: ItemData) -> void:
	var price := inventory.price_of(item) if inventory != null else item.cost
	_details.text = "%s  (%s, %d gold)\n%s" % [item.display_name, item.get_tier_name(), price, item.describe()]


func _on_buy(item: ItemData) -> void:
	if inventory != null:
		inventory.buy(item)
	_refresh()


func _on_sell(item: ItemData) -> void:
	if inventory != null:
		inventory.sell(item)
	_refresh()


func _key_text() -> String:
	var slot := GameRules.current().get_slot(match_manager.get_rules().active_item_slot) if match_manager != null else null
	if slot == null or not InputMap.has_action(slot.input_action):
		return "-"
	var events := InputMap.action_get_events(slot.input_action)
	return events[0].as_text().replace(" - Physical", "").replace(" (Physical)", "") if not events.is_empty() else "-"


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.16, 0.3, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	return label
