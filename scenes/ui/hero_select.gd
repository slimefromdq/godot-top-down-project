extends Control

# Hero select: a grid of every playable hero (name, title, role), a details
# panel for the one you're looking at, Lock In, the countdown, and both
# teams' picks as the bots lock in. The rules are in HeroDraft; this only
# draws them. When everyone is locked in, GameState.launch() starts the match
# (or the training grounds for Practice).

var draft: HeroDraft
var _cards: Dictionary = {}    # hero_id -> Button
var _detail_name: Label
var _detail_title: Label
var _detail_role: Label
var _detail_text: Label
var _detail_abilities: Label
var _lock: Button
var _timer: Label
var _team_boxes: Dictionary = {}    # team -> VBoxContainer
var _launched := false


func _ready() -> void:
	var config := GameState.config
	draft = HeroDraft.new(config, BotDraft.playable_definitions())
	draft.changed.connect(_refresh)
	MenuUI.setup_screen(self)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 32
	root.offset_top = 24
	root.offset_right = -32
	root.offset_bottom = -24
	root.add_theme_constant_override(&"separation", 24)
	add_child(root)

	# Left: title, timer and the hero grid.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 12)
	root.add_child(left)
	var header := HBoxContainer.new()
	header.add_child(MenuUI.label("Practice: choose a hero" if config.practice else "Choose your hero", 40, MenuUI.ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_timer = MenuUI.label("", 36)
	header.add_child(_timer)
	left.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	for definition in draft.definitions:
		var card := _make_card(definition)
		_cards[definition.hero_id] = card
		grid.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	left.add_child(scroll)

	# Details under the grid.
	var details := MenuUI.panel(20)
	var dbox := VBoxContainer.new()
	details.add_child(dbox)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 16)
	_detail_name = MenuUI.label("", 34, Color.WHITE)
	_detail_title = MenuUI.label("", 24, Color(1, 1, 1, 0.7))
	_detail_role = MenuUI.label("", 24)
	name_row.add_child(_detail_name)
	name_row.add_child(_detail_title)
	name_row.add_child(_detail_role)
	dbox.add_child(name_row)
	_detail_text = MenuUI.label("", 18, Color(1, 1, 1, 0.85))
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size.x = 600
	dbox.add_child(_detail_text)
	_detail_abilities = MenuUI.label("", 17, Color(0.85, 0.9, 1.0))
	_detail_abilities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbox.add_child(_detail_abilities)
	left.add_child(details)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	buttons.add_child(MenuUI.button("Back", _back, 200))
	_lock = MenuUI.button("Lock In", _on_lock, 320)
	buttons.add_child(_lock)
	left.add_child(buttons)

	# Right: the teams.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 380
	right.add_theme_constant_override(&"separation", 16)
	root.add_child(right)
	for team in draft.teams:
		var panel := MenuUI.panel(16)
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", 6)
		panel.add_child(box)
		var heading := "%s  (your team)" % MatchManager.team_name(team) if team == config.player_team \
			else MatchManager.team_name(team)
		box.add_child(MenuUI.label(heading, 26, MatchManager.team_color(team)))
		var rows := VBoxContainer.new()
		box.add_child(rows)
		_team_boxes[team] = rows
		right.add_child(panel)
	_refresh()
	if _cards.has(draft.hovered):
		(_cards[draft.hovered] as Button).grab_focus.call_deferred()


func _make_card(definition: HeroDefinition) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(270, 110)
	card.toggle_mode = true
	card.clip_text = true
	card.add_theme_stylebox_override(&"normal", MenuUI.card_style(Color(0.13, 0.15, 0.24)))
	card.add_theme_stylebox_override(&"hover", MenuUI.card_style(Color(0.19, 0.22, 0.34)))
	card.add_theme_stylebox_override(&"pressed", MenuUI.card_style(Color(0.22, 0.25, 0.4), MenuUI.ACCENT))
	card.add_theme_stylebox_override(&"hover_pressed", MenuUI.card_style(Color(0.22, 0.25, 0.4), MenuUI.ACCENT))
	card.add_theme_stylebox_override(&"focus", MenuUI.card_style(Color.TRANSPARENT, Color(1, 1, 1, 0.5)))
	card.add_theme_stylebox_override(&"disabled", MenuUI.card_style(Color(0.1, 0.11, 0.16)))
	for state in [&"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		card.add_theme_color_override(state, MenuUI.role_color(definition.role))
	card.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.3))
	card.add_theme_color_override(&"font_outline_color", Color.BLACK)
	card.add_theme_constant_override(&"outline_size", 0)
	card.text = "%s\n%s\n%s" % [definition.display_name, definition.title, definition.get_role_name()]
	card.add_theme_font_size_override(&"font_size", 17)
	if definition.icon != null:
		card.icon = definition.icon
		card.expand_icon = true
	card.add_theme_color_override(&"font_color", MenuUI.role_color(definition.role))
	var id := definition.hero_id
	card.pressed.connect(func(): draft.hover(id))
	card.focus_entered.connect(func(): draft.hover(id))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.double_click:
			draft.lock_in(id))
	return card


func _process(delta: float) -> void:
	draft.tick(delta)
	if draft.start_left > 0.0:
		_timer.text = "Starting…"
	else:
		_timer.text = "%d" % ceili(draft.time_left)
		_timer.add_theme_color_override(&"font_color", Color("fca5a5") if draft.time_left <= 5.0 else Color.WHITE)
	if draft.is_done() and not _launched:
		_launched = true
		GameState.config.picks = draft.to_picks()
		GameState.launch()


func _refresh() -> void:
	var locked := draft.is_player_locked()
	for id in _cards:
		var card: Button = _cards[id]
		card.set_pressed_no_signal(id == draft.hovered)
		card.disabled = locked and id != draft.hovered
		card.tooltip_text = "An ally bot has this hero (they'll pick again)" if draft.is_taken_by_ally(id) else ""
	var definition := draft.find(draft.hovered)
	if definition != null:
		_detail_name.text = definition.display_name
		_detail_title.text = definition.title
		_detail_role.text = definition.get_role_name()
		_detail_role.add_theme_color_override(&"font_color", MenuUI.role_color(definition.role))
		_detail_text.text = definition.description
		var names := PackedStringArray()
		for slot in GameRules.current().slots:
			var ability := definition.get_ability(slot.id)
			if ability != null:
				names.append(ability.display_name)
		_detail_abilities.text = "Abilities: " + ", ".join(names)
	_lock.disabled = locked or definition == null
	_lock.text = "Locked In" if locked else "Lock In"
	for team in _team_boxes:
		var rows: VBoxContainer = _team_boxes[team]
		for child in rows.get_children():
			child.queue_free()
		for slot: HeroDraft.Slot in draft.teams[team]:
			rows.add_child(_slot_row(slot))


func _slot_row(slot: HeroDraft.Slot) -> Label:
	var who := "You" if slot.is_player else ("Bot %d" % (slot.index + 1) if slot.is_bot else "Empty")
	var what := ""
	var color := Color(1, 1, 1, 0.5)
	var definition := draft.find(slot.hero_id)
	if definition != null and (slot.locked or slot.is_player):
		what = "%s  (%s)" % [definition.display_name, definition.get_role_name()]
		color = MenuUI.role_color(definition.role) if slot.locked else Color(1, 1, 1, 0.75)
		if slot.is_player and not slot.locked:
			what += "  …"
	elif slot.is_bot:
		what = "picking…"
	var row := MenuUI.label("%-7s %s" % [who, what], 20, color)
	return row


func _on_lock() -> void:
	draft.lock_in()


func _back() -> void:
	if GameState.config.practice:
		GameState.goto_main_menu()
	else:
		GameState.goto_match_setup()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not draft.is_player_locked():
		get_viewport().set_input_as_handled()
		_back()
