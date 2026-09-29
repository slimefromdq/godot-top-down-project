extends CanvasLayer
class_name MapEventsHud

# The HUD side of the three map events (the MatchHud adds one). Read-only apart
# from the requests it sends to the directors:
#
#   interact   the interact key (map_interact, X) acts on the nearest
#              interactable in reach: the Black Market opens its shop window,
#              the Island portal sends you through, the Island exit sends you
#              home. A prompt under the item row names it.
#   market     a pill under the clock while the stall is open: which flank and
#              a countdown to its despawn (all players see it).
#   buffs      your running Black Market buffs and their timers, above the
#              item slots.
#   island     while you are on it, the seconds left before you are sent home.
#   tell       when the portal relocates, a faint glow at the screen edges and a
#              soft chime: no place in it, only "it moved".
#
# The Announcer (banners, toasts) listens to the same director signals.

const TELL_TIME := 2.4

var manager: MatchManager
var events: MapEvents
var panel: BlackMarketPanel
## What the interact key would act on right now (null = nothing in reach).
var target: Node2D

var _root: Control
var _prompt: Label
var _market_pill: Label
var _island_label: Label
var _buffs: HBoxContainer
var _tell: Control
var _tell_left: float = 0.0
var _buff_signature := ""


func _ready() -> void:
	layer = 5
	_build()


func bind(p_manager: MatchManager) -> void:
	manager = p_manager
	events = manager.get_node_or_null(^"MapEvents") as MapEvents if manager != null else null
	if events == null:
		return
	panel = BlackMarketPanel.new()
	panel.name = "BlackMarketPanel"
	add_child(panel)
	panel.bind(manager, events.market)
	events.island.portal_relocated.connect(_on_portal_relocated)
	events.market.purchase_made.connect(_on_purchase)


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func _on_portal_relocated() -> void:
	_tell_left = TELL_TIME


func _on_purchase(hero: Hero, item: BlackMarketItem) -> void:
	if hero == get_player():
		var hud := get_tree().get_first_node_in_group(MatchHud.GROUP)
		if hud != null and hud.get("announcer") != null:
			hud.announcer.toast("%s  %s" % [item.glyph, item.display_name], item.color)


func _process(delta: float) -> void:
	if events == null:
		return
	var hero := get_player()
	_update_market_pill()
	if hero == null or not manager.has_hero(hero):
		_prompt.visible = false
		_island_label.visible = false
		return
	target = find_target(hero)
	_prompt.visible = target != null and not panel.is_open()
	if target != null:
		_prompt.text = "%s   %s" % [_key_text(), target.get_prompt(hero)]
	_update_island(hero)
	_update_buffs(hero)
	if _tell_left > 0.0:
		_tell_left = maxf(_tell_left - delta, 0.0)
		_tell.queue_redraw()


## The nearest interactable `hero` could use now.
func find_target(hero: Hero) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(MapEvents.INTERACTABLES):
		var candidate := node as Node2D
		if candidate == null or not candidate.is_visible_in_tree() or not candidate.has_method(&"can_interact"):
			continue
		if not candidate.can_interact(hero):
			continue
		# The Island exit only answers someone on the Island; the portal only
		# someone who isn't.
		if candidate is IslandExit and not events.island.is_on_island(hero):
			continue
		if candidate is IslandPortal and events.island.is_on_island(hero):
			continue
		var distance := hero.global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _unhandled_input(event: InputEvent) -> void:
	if events == null or not InputMap.has_action(&"map_interact") or not event.is_action_pressed(&"map_interact"):
		return
	if panel.is_open():
		panel.close()
		get_viewport().set_input_as_handled()
		return
	var hero := get_player()
	if hero == null or target == null:
		return
	interact(hero, target)
	get_viewport().set_input_as_handled()


## Act on `node` as `hero` (also for tests). Returns "" or the refusal.
func interact(hero: Hero, node: Node2D) -> String:
	var reason := ""
	if node is BlackMarket:
		if not panel.open():
			reason = "Can't shop right now"
	elif node is IslandPortal:
		reason = events.island.request_enter(hero)
	elif node is IslandExit:
		reason = events.island.request_leave(hero)
	if reason != "":
		var hud := get_tree().get_first_node_in_group(MatchHud.GROUP)
		if hud != null and hud.get("announcer") != null:
			hud.announcer.toast(reason, Color("fca5a5"))
	return reason


func _update_market_pill() -> void:
	var director := events.market
	if director.is_open():
		var left := ceili(director.get_time_left())
		_market_pill.text = "Black Market (%s flank)  closes in %d:%02d" % [str(director.market.side).capitalize(), left / 60, left % 60]
		_market_pill.modulate = Color("fb7185") if left <= 10 else Color("ddd6fe")
		_market_pill.visible = true
	else:
		_market_pill.visible = false


func _update_island(hero: Hero) -> void:
	var island := events.island
	if island.is_on_island(hero):
		var left := island.get_stay_left(hero)
		_island_label.text = "Mote Island   %s" % ("%d s left" % ceili(left) if left < 1e6 else "")
		_island_label.visible = true
	else:
		_island_label.visible = false


func _update_buffs(hero: Hero) -> void:
	var items := TempItems.find_on(hero)
	var rows: Array[Dictionary] = items.get_active() if items != null else ([] as Array[Dictionary])
	var signature := ""
	for row in rows:
		signature += "%s:%d;" % [row.item.id, ceili(row.left)]
	if signature == _buff_signature:
		return
	_buff_signature = signature
	for child in _buffs.get_children():
		child.queue_free()
	for row in rows:
		var label := _label("%s %s %ds" % [row.item.glyph, row.item.display_name, ceili(row.left)], 16)
		label.modulate = row.item.color
		_buffs.add_child(label)


func _key_text() -> String:
	if not InputMap.has_action(&"map_interact"):
		return "[X]"
	var list := InputMap.action_get_events(&"map_interact")
	return "[%s]" % (list[0].as_text().replace(" - Physical", "").replace(" (Physical)", "") if not list.is_empty() else "X")


# --- Building -------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_market_pill = _label("", 20)
	_market_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_market_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_market_pill.offset_top = 98
	_market_pill.visible = false
	_root.add_child(_market_pill)
	_island_label = _label("", 22)
	_island_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_island_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_island_label.offset_top = 126
	_island_label.modulate = Color("c4b5fd")
	_island_label.visible = false
	_root.add_child(_island_label)
	_prompt = _label("", 22)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -300
	_prompt.offset_bottom = -268
	_prompt.modulate = Color("fde68a")
	_prompt.visible = false
	_root.add_child(_prompt)
	_buffs = HBoxContainer.new()
	_buffs.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buffs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buffs.offset_top = -236
	_buffs.offset_bottom = -206
	_buffs.add_theme_constant_override(&"separation", 14)
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buffs)
	_tell = Control.new()
	_tell.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tell.draw.connect(_draw_tell)
	_root.add_child(_tell)


# A soft violet glow along the screen edges, fading out. No position in it.
func _draw_tell() -> void:
	if _tell_left <= 0.0:
		return
	var k := _tell_left / TELL_TIME
	var alpha := 0.22 * sin(k * PI)
	var size := _tell.size
	var band := 70.0
	var color := Color(0.75, 0.6, 1.0, alpha)
	var clear := Color(color, 0.0)
	_tell.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, band), Vector2(0, band)]),
		PackedColorArray([color, color, clear, clear]))
	_tell.draw_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x, size.y - band), Vector2(0, size.y - band)]),
		PackedColorArray([color, color, clear, clear]))
	_tell.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(0, size.y), Vector2(band, size.y), Vector2(band, 0)]),
		PackedColorArray([color, color, clear, clear]))
	_tell.draw_polygon(PackedVector2Array([Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - band, size.y), Vector2(size.x - band, 0)]),
		PackedColorArray([color, color, clear, clear]))


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.16, 0.3, 0.85))
	label.add_theme_constant_override(&"outline_size", maxi(size / 5, 3))
	return label
