extends CanvasLayer
class_name ShopPanel

# The shop window (the MatchHud adds one). B (shop_toggle) opens and closes
# it, Escape closes it. Laid out as: a header (title, your gold, whether you
# can shop right now), the catalog on the left (one row per item family in
# ShopCatalog order, one card per item, cheapest first), a details card on
# the right (hover or focus an item for its real numbers, ItemData.describe()),
# and your item slots along the bottom (click one to sell it). Each card shows
# the item's price for you right now (a component you own comes off it), in
# green when you can buy it, red when you can't afford it and grey when the
# shop is closed to you. The active item has its own slot and key.
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
var _detail_name: Label
var _detail_meta: Label
var _detail_body: Label
var _detail_block: Label
var _catalog_box: VBoxContainer
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

const PANEL_BG := Color(0.07, 0.08, 0.13, 0.97)
const CARD_BG := Color(0.13, 0.15, 0.23, 1.0)
const GOLD := Color("fbd34d")
const GOOD := Color("86efac")
const BAD := Color("fca5a5")
const MUTED := Color(1, 1, 1, 0.55)
const CARD_SIZE := Vector2(208, 58)


func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "Shop"
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.custom_minimum_size = Vector2(1080, 0)
	var frame := StyleBoxFlat.new()
	frame.bg_color = PANEL_BG
	frame.set_corner_radius_all(16)
	frame.set_content_margin_all(18)
	frame.border_color = Color(1, 1, 1, 0.14)
	frame.set_border_width_all(2)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 14
	_root.add_theme_stylebox_override(&"panel", frame)
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	_root.add_child(box)

	# Header: title, status chip, gold, close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 14)
	header.add_child(_label("Shop", 30))
	_status_label = _label("", 16)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status_label)
	_gold_label = _label("", 26)
	_gold_label.modulate = GOLD
	header.add_child(_gold_label)
	var close_button := Button.new()
	close_button.text = "Close (B)"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	box.add_child(header)

	# Middle: the catalog and the details card.
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override(&"separation", 16)
	box.add_child(middle)
	_catalog_box = VBoxContainer.new()
	_catalog_box.add_theme_constant_override(&"separation", 10)
	_catalog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(_catalog_box)
	middle.add_child(_build_details())

	# Bottom: your items.
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override(&"panel", _card_style(Color(1, 1, 1, 0.05), Color.TRANSPARENT))
	var bottom_box := HBoxContainer.new()
	bottom_box.add_theme_constant_override(&"separation", 10)
	bottom.add_child(bottom_box)
	bottom_box.add_child(_label("Your items", 16))
	_owned_row = HBoxContainer.new()
	_owned_row.add_theme_constant_override(&"separation", 6)
	_owned_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_box.add_child(_owned_row)
	_active_row = HBoxContainer.new()
	_active_row.add_theme_constant_override(&"separation", 6)
	bottom_box.add_child(_active_row)
	box.add_child(bottom)


func _build_details() -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	card.add_theme_stylebox_override(&"panel", _card_style(CARD_BG, Color(1, 1, 1, 0.12)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	card.add_child(v)
	_detail_name = _label("Hover an item", 22)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail_name)
	_detail_meta = _label("", 15)
	_detail_meta.modulate = MUTED
	v.add_child(_detail_meta)
	_detail_body = _label("Its numbers show here. Click an item to buy it; click one of your items to sell it.", 15)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail_body)
	_detail_block = _label("", 14)
	_detail_block.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_block.modulate = BAD
	v.add_child(_detail_block)
	return card


func _rebuild_grid(catalog: ShopCatalog) -> void:
	_built_for = catalog
	buttons.clear()
	for child in _catalog_box.get_children():
		child.queue_free()
	if catalog == null:
		return
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override(&"separation", 8)
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(96, 0)
	tiers.add_child(gutter)
	for tier_name in ItemData.TIER_NAMES:
		var head := _label(tier_name, 15)
		head.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.modulate = MUTED
		tiers.add_child(head)
	_catalog_box.add_child(tiers)
	for family in catalog.get_family_order():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var row_title := _label(catalog.get_family_title(family), 17)
		row_title.custom_minimum_size = Vector2(96, 0)
		row_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(row_title)
		for tier in ItemData.TIER_NAMES.size():
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
			cell.add_theme_constant_override(&"separation", 4)
			for item in catalog.get_items(family, tier):
				cell.add_child(_item_card(item))
			row.add_child(cell)
		_catalog_box.add_child(row)


# One item: a coloured stripe and glyph, the name and the price. The Button is
# the click target; its labels are children that ignore the mouse.
func _item_card(item: ItemData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.clip_contents = true
	button.pressed.connect(_on_buy.bind(item))
	button.mouse_entered.connect(_show_details.bind(item))
	button.focus_entered.connect(_show_details.bind(item))
	for state in [&"normal", &"disabled"]:
		button.add_theme_stylebox_override(state, _card_style(CARD_BG if state == &"normal" else CARD_BG.darkened(0.25), item.color))
	button.add_theme_stylebox_override(&"hover", _card_style(CARD_BG.lightened(0.1), item.color.lightened(0.3)))
	button.add_theme_stylebox_override(&"pressed", _card_style(CARD_BG.lightened(0.2), item.color.lightened(0.3)))
	button.add_theme_stylebox_override(&"focus", _card_style(Color.TRANSPARENT, Color.WHITE))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 8)
	var glyph := _label(item.glyph, 22)
	glyph.name = "Glyph"
	glyph.custom_minimum_size = Vector2(34, 0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.modulate = item.color
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(glyph)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override(&"separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(item.display_name, 15)
	title.name = "Title"
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)
	var price := _label("", 15)
	price.name = "Price"
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(price)
	h.add_child(texts)
	button.add_child(h)
	buttons[item] = button
	return button


func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if border.a > 0.0:
		style.border_color = border
		style.set_border_width_all(2)
		style.border_width_left = 6
	return style


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_left = REFRESH
	inventory = _find_inventory()
	var catalog := match_manager.get_rules().shop_catalog if match_manager != null else null
	if catalog != _built_for:
		_rebuild_grid(catalog)
	if inventory == null:
		_set_status("No shop here.", BAD)
		return
	_gold_label.text = "● %d" % floori(inventory.get_gold())
	var reason := inventory.get_shop_block_reason()
	if inventory.hero.health_component.is_dead() and reason == "":
		_set_status("Respawning: buy and sell from here.", GOOD)
	elif reason == "":
		_set_status("In base: buy and sell.", GOOD)
	else:
		_set_status(reason + " (you can still browse).", BAD)
	for item in buttons:
		var button: Button = buttons[item]
		var block := inventory.get_buy_block_reason(item)
		var price := inventory.price_of(item)
		var price_label := button.find_child("Price", true, false) as Label
		if price_label != null:
			price_label.text = "%d gold%s" % [price, "" if price == item.cost else "  (was %d)" % item.cost]
			price_label.modulate = GOOD if block == "" else (BAD if inventory.get_gold() < price else MUTED)
		button.text = ""
		button.disabled = block != ""
		button.tooltip_text = "" if block == "" else block
	for child in _owned_row.get_children() + _active_row.get_children():
		child.queue_free()
	for item in inventory.get_passive_items():
		_owned_row.add_child(_owned_button(item))
	for i in maxi(inventory.get_rules().item_slots - inventory.get_passive_items().size(), 0):
		_owned_row.add_child(_empty_slot("empty"))
	var active_title := _label("Active (%s)" % _key_text(), 16)
	_active_row.add_child(active_title)
	var active := inventory.get_active_item()
	_active_row.add_child(_owned_button(active) if active != null else _empty_slot("none"))


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.modulate = color


func _owned_button(item: ItemData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.text = "%s %s  +%d" % [item.glyph, item.display_name, inventory.sell_value_of(item)]
	button.tooltip_text = "Sell for %d gold" % inventory.sell_value_of(item)
	button.disabled = inventory.get_sell_block_reason(item) != ""
	button.add_theme_stylebox_override(&"normal", _card_style(CARD_BG, item.color))
	button.add_theme_stylebox_override(&"hover", _card_style(CARD_BG.lightened(0.1), item.color.lightened(0.3)))
	button.add_theme_stylebox_override(&"disabled", _card_style(CARD_BG.darkened(0.25), item.color))
	button.pressed.connect(_on_sell.bind(item))
	button.mouse_entered.connect(_show_details.bind(item, true))
	return button


func _empty_slot(text: String) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(70, 40)
	slot.add_theme_stylebox_override(&"panel", _card_style(Color(1, 1, 1, 0.04), Color.TRANSPARENT))
	var label := _label(text, 13)
	label.modulate = Color(1, 1, 1, 0.4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


func _show_details(item: ItemData, owned: bool = false) -> void:
	var price := inventory.price_of(item) if inventory != null else item.cost
	_detail_name.text = "%s %s" % [item.glyph, item.display_name]
	_detail_name.modulate = item.color.lightened(0.35)
	if owned and inventory != null:
		_detail_meta.text = "%s  -  sells for %d gold" % [item.get_tier_name(), inventory.sell_value_of(item)]
	else:
		_detail_meta.text = "%s  -  %d gold%s" % [item.get_tier_name(), price,
			"" if price == item.cost else " (full price %d)" % item.cost]
	_detail_body.text = item.describe()
	var block := ""
	if inventory != null:
		block = inventory.get_sell_block_reason(item) if owned else inventory.get_buy_block_reason(item)
	_detail_block.text = block


func _on_buy(item: ItemData) -> void:
	if inventory != null:
		inventory.buy(item)
	_refresh()
	_show_details(item)


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
	label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.04, 0.1, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	return label
