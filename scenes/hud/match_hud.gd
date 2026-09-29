extends CanvasLayer
class_name MatchHud

# Match HUD: the clock at top centre (with empty slots either side for the
# two wake meters), the local player's gold, level and XP bar to the left of
# the ability bar, and a respawn countdown while they're dead.
#
# Wake meters: a WakeMeter for each Dreamer in the slots either side of the
# clock (Dawn left, Dusk right).
#
# Team bars (TeamBar) on the outside of the wake meters: every hero on each
# team; your own team's cards add health and ultimate charge.
#
# Off-screen arrows: every Node2D in the "offscreen_arrows" group (the Dream
# Mote, the Dreamers) gets an arrow at the screen edge pointing to it while
# it's off screen, in its `arrow_color`. A node with offscreen_arrow_for(
# viewer) decides per viewer instead: {} hides it, else {color, scale} (a
# Dreamer shows only while you carry Motes, bold for the enemy's).
#
# Shop: a ShopPanel (B) and a "B  Shop" hint under the gold while the player
# can buy (in base, or dead).
#
# Items: the player's item slots above the ability bar, one large
# square per slot with the item's icon (its colour and glyph) and the active
# item's key. Empty slots show as dim frames.
#
# K/D/A: the player's own kills / deaths / assists under the XP bar, and
# each team's total kills either side of the clock (every hero's own K/D/A
# is on its TeamBar card).
#
# Read-only: it listens to the MatchManager and polls the player each frame.
# Hides itself when the scene has no MatchManager.

## Width kept free on each side of the clock for the wake meters (M3).
@export var wake_slot_width: float = 320.0
@export var gold_color := Color("fbd34d")
@export var xp_color := Color("a78bfa")
## Arrows sit this far in from the left and right edges...
@export var arrow_margin: float = 46.0
## ...and this far from the top and bottom, clear of the wake meters, the
## announcer banners and the ability bar.
@export var arrow_margin_top: float = 205.0
@export var arrow_margin_bottom: float = 170.0

var match_manager: MatchManager
var announcer: Announcer
var kill_feedback: KillFeedback
var shop_panel: ShopPanel
var events_hud: MapEventsHud

var _clock_label: Label
var _state_label: Label
var _level_label: Label
var _gold_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _respawn_label: Label
var _arrows: Control
var _mote_label: Label
var _shop_hint: Label
var _kda_label: Label
var _score_a: Label
var _score_b: Label
var _items_row: HBoxContainer
## Item slot size on screen.
@export var item_slot_size := Vector2(56, 56)
## Left/right of the clock, empty until the wake meters arrive.
var wake_slot_a: Control
var wake_slot_b: Control
var team_bar_a: TeamBar
var team_bar_b: TeamBar


const GROUP := &"match_hud"


func _ready() -> void:
	add_to_group(GROUP)
	layer = 5
	_build()
	_bind.call_deferred()


func _bind() -> void:
	match_manager = MatchManager.find(get_tree())
	visible = match_manager != null
	announcer = Announcer.new()
	announcer.name = "Announcer"
	add_child(announcer)
	announcer.bind(match_manager)
	kill_feedback = KillFeedback.new()
	kill_feedback.name = "KillFeedback"
	add_child(kill_feedback)
	kill_feedback.bind(match_manager)
	shop_panel = ShopPanel.new()
	shop_panel.name = "ShopPanel"
	add_child(shop_panel)
	shop_panel.bind(match_manager)
	events_hud = MapEventsHud.new()
	events_hud.name = "MapEventsHud"
	add_child(events_hud)
	events_hud.bind(match_manager)
	for slot_team in [[wake_slot_a, &"a", true], [wake_slot_b, &"b", false]]:
		var meter := WakeMeter.new()
		meter.name = "WakeMeter"
		meter.team = slot_team[1]
		meter.icon_on_left = slot_team[2]
		meter.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot_team[0].add_child(meter)


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func _process(_delta: float) -> void:
	if match_manager == null or not is_instance_valid(match_manager):
		return
	_arrows.queue_redraw()
	_clock_label.text = clock_text()
	_score_a.text = str(match_manager.get_team_kills(&"a"))
	_score_b.text = str(match_manager.get_team_kills(&"b"))
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
	var kda := match_manager.get_kda(hero)
	_kda_label.text = "K / D / A   %d / %d / %d" % [kda.x, kda.y, kda.z]
	_refresh_items(hero)
	var carrier := MoteCarrier.find_on(hero)
	var count := carrier.get_mote_count() if carrier != null else 0
	_mote_label.visible = count > 0
	_mote_label.text = "Motes %d / %d  (value %d)" % [count, carrier.get_max(), carrier.get_mote_value()] if count > 0 else ""
	_shop_hint.visible = match_manager.can_shop(hero) and not shop_panel.is_open()
	var respawn := match_manager.get_respawn_left(hero)
	_respawn_label.visible = hero.health_component.is_dead() and respawn > 0.0
	_respawn_label.text = "Respawning in %d" % ceili(respawn)


## Screen positions of the off-screen arrows (for tests and captures).
func arrow_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var view := get_viewport().get_visible_rect().size
	var to_screen := get_viewport().get_canvas_transform()
	var inner := Rect2(Vector2(arrow_margin, arrow_margin_top),
		view - Vector2(arrow_margin * 2.0, arrow_margin_top + arrow_margin_bottom))
	var center := inner.get_center()
	var player := get_player()
	for node in get_tree().get_nodes_in_group(&"offscreen_arrows"):
		if not node is Node2D or not node.is_visible_in_tree():
			continue
		var style := {}
		if node.has_method(&"offscreen_arrow_for"):
			style = node.offscreen_arrow_for(player)
			if style.is_empty():
				continue
		var screen: Vector2 = to_screen * (node as Node2D).global_position
		if Rect2(Vector2.ZERO, view).has_point(screen):
			continue
		var dir := (screen - center).normalized()
		# Walk from the centre toward it and stop at the inner rect's edge.
		var tx := (inner.size.x / 2.0) / maxf(absf(dir.x), 0.0001)
		var ty := (inner.size.y / 2.0) / maxf(absf(dir.y), 0.0001)
		var color = style.get("color", node.get(&"arrow_color"))
		result.append({"position": center + dir * minf(tx, ty), "direction": dir,
			"color": color if color is Color else Color.WHITE, "scale": style.get("scale", 1.0), "node": node})
	return result


func _draw_arrows(canvas: Control) -> void:
	for arrow in arrow_points():
		var at: Vector2 = arrow.position
		var dir: Vector2 = arrow.direction
		var k: float = arrow.scale
		var side := dir.orthogonal()
		var tri := PackedVector2Array([at + dir * 22.0 * k, at - dir * 10.0 * k + side * 16.0 * k,
			at - dir * 10.0 * k - side * 16.0 * k])
		canvas.draw_colored_polygon(tri, arrow.color)
		canvas.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.8), 2.0 * k)
		canvas.draw_circle(at - dir * 26.0 * k, 9.0 * k, arrow.color)
		canvas.draw_arc(at - dir * 26.0 * k, 9.0 * k, 0.0, TAU, 16, Color(0, 0, 0, 0.8), 2.0)


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
	team_bar_a = TeamBar.new()
	team_bar_a.name = "TeamBarA"
	team_bar_a.team = &"a"
	team_bar_a.align_right = true
	top.add_child(team_bar_a)
	wake_slot_a = _slot("WakeSlotA")
	top.add_child(wake_slot_a)
	var clock_box := VBoxContainer.new()
	clock_box.custom_minimum_size.x = 140
	clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_row := HBoxContainer.new()
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_row.add_theme_constant_override(&"separation", 12)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_a = _label(26)
	_score_a.modulate = MatchManager.team_color(&"a")
	clock_row.add_child(_score_a)
	_clock_label = _label(34)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_row.add_child(_clock_label)
	_score_b = _label(26)
	_score_b.modulate = MatchManager.team_color(&"b")
	clock_row.add_child(_score_b)
	clock_box.add_child(clock_row)
	_state_label = _label(16)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_box.add_child(_state_label)
	top.add_child(clock_box)
	wake_slot_b = _slot("WakeSlotB")
	top.add_child(wake_slot_b)
	team_bar_b = TeamBar.new()
	team_bar_b.name = "TeamBarB"
	team_bar_b.team = &"b"
	team_bar_b.align_right = false
	top.add_child(team_bar_b)

	# Bottom, left of the ability bar (which spans -250..250 from centre).
	var economy := VBoxContainer.new()
	economy.name = "Economy"
	economy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	economy.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	economy.offset_left = -510
	economy.offset_right = -300
	economy.offset_top = -170
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
	fill.set_corner_radius_all(7)
	fill.border_color = xp_color.lightened(0.5)
	fill.border_width_top = 3
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.18, 0.32, 0.6)
	back.border_color = Color(1, 1, 1, 0.55)
	back.set_border_width_all(1)
	back.set_corner_radius_all(7)
	_xp_bar.add_theme_stylebox_override(&"fill", fill)
	_xp_bar.add_theme_stylebox_override(&"background", back)
	economy.add_child(_xp_bar)
	_xp_label = _label(12)
	economy.add_child(_xp_label)
	_kda_label = _label(16)
	economy.add_child(_kda_label)
	_shop_hint = _label(16)
	_shop_hint.text = "%s  Shop" % _action_key(ShopPanel.TOGGLE_ACTION)
	_shop_hint.modulate = gold_color
	_shop_hint.visible = false
	economy.add_child(_shop_hint)
	_mote_label = _label(16)
	_mote_label.modulate = Color("fde68a")
	_mote_label.visible = false
	economy.add_child(_mote_label)
	economy.move_child(_mote_label, 0)

	# Bottom centre, just above the ability bar: the item slots.
	_items_row = HBoxContainer.new()
	_items_row.name = "Items"
	_items_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_items_row.offset_top = -140 - item_slot_size.y
	_items_row.offset_bottom = -140
	_items_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_items_row.add_theme_constant_override(&"separation", 6)
	add_child(_items_row)

	_arrows = Control.new()
	_arrows.name = "OffscreenArrows"
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrows.draw.connect(_draw_arrows.bind(_arrows))
	add_child(_arrows)

	_respawn_label = _label(40)
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_respawn_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.visible = false
	add_child(_respawn_label)


## The items shown in the slots, passives first then the active item (null
## for an empty slot), for tests.
func get_item_slots(hero: Hero) -> Array:
	var inventory := ItemInventory.find_on(hero)
	if inventory == null:
		return []
	var slots: Array = []
	for item in inventory.get_passive_items():
		slots.append(item)
	for i in maxi(inventory.get_rules().item_slots - slots.size(), 0):
		slots.append(null)
	slots.append(inventory.get_active_item())
	return slots


var _items_key: String = ""


func _refresh_items(hero: Hero) -> void:
	var slots := get_item_slots(hero)
	# Rebuild only when the items change.
	var key := ",".join(slots.map(func(item): return str(item.id) if item != null else "-"))
	if key == _items_key:
		return
	_items_key = key
	for child in _items_row.get_children():
		child.queue_free()
	for i in slots.size():
		var active := i == slots.size() - 1
		if active:
			var gap := Control.new()
			gap.custom_minimum_size.x = 8
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_items_row.add_child(gap)
		_items_row.add_child(_item_slot(slots[i], active))


func _item_slot(item: ItemData, active: bool) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = item_slot_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	if item != null:
		style.bg_color = Color(item.color.darkened(0.45), 0.9)
		style.border_color = item.color.lightened(0.2)
		slot.tooltip_text = "%s\n%s" % [item.display_name, item.describe()]
	else:
		style.bg_color = Color(0.05, 0.1, 0.18, 0.55)
		style.border_color = Color(1, 1, 1, 0.3)
	if active:
		style.border_color = Color("fbd34d") if item != null else Color(0.98, 0.83, 0.3, 0.4)
	slot.add_theme_stylebox_override(&"panel", style)
	if item != null:
		var glyph := _label(26)
		glyph.text = item.glyph
		glyph.modulate = item.color.lightened(0.35)
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(glyph)
	if active:
		var key := _label(12)
		var rules := match_manager.get_rules() if match_manager != null else null
		var ability_slot := GameRules.current().get_slot(rules.active_item_slot) if rules != null else null
		key.text = _action_key(ability_slot.input_action) if ability_slot != null else ""
		key.position = Vector2(4, 1)
		slot.add_child(key)
	return slot


func _action_key(action: StringName) -> String:
	if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
		return "?"
	return InputMap.action_get_events(action)[0].as_text().replace(" - Physical", "").replace(" (Physical)", "")


func _slot(slot_name: String) -> Control:
	var slot := Control.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(wake_slot_width, 70)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.16, 0.3, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
