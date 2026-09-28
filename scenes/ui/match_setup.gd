extends Control

# Match setup: mode (Practice vs bots; the online lobby is a stub for later),
# team size, bot fill and difficulty, map. Writes GameState.config, then on to
# hero select.

var config: MatchConfig


func _ready() -> void:
	config = GameState.new_config()
	MenuUI.setup_screen(self)
	var panel := MenuUI.panel(36)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 16)
	panel.add_child(box)
	box.add_child(MenuUI.label("Match Setup", 44, MenuUI.ACCENT))

	var mode := OptionButton.new()
	mode.add_item("Practice vs bots", MatchConfig.Mode.PRACTICE_VS_BOTS)
	mode.add_item("Online lobby (coming soon)", MatchConfig.Mode.LOBBY)
	mode.set_item_disabled(1, true)
	mode.select(mode.get_item_index(config.mode))
	mode.item_selected.connect(func(i): config.mode = mode.get_item_id(i))
	box.add_child(MenuUI.row("Mode", mode))

	var size := SpinBox.new()
	size.min_value = 1
	size.max_value = 6
	size.value = config.team_size
	size.suffix = "v%d" % config.team_size
	size.value_changed.connect(func(v: float):
		config.team_size = int(v)
		size.suffix = "v%d" % config.team_size)
	box.add_child(MenuUI.row("Team size", size))

	var fill := CheckBox.new()
	fill.text = "Fill empty slots with bots"
	fill.button_pressed = config.bot_fill
	fill.toggled.connect(func(on: bool): config.bot_fill = on)
	box.add_child(MenuUI.row("Bots", fill))

	var difficulty := OptionButton.new()
	for d in ["Easy", "Normal", "Hard"]:
		difficulty.add_item(d)
	difficulty.select(config.bot_difficulty)
	difficulty.item_selected.connect(func(i): config.bot_difficulty = i)
	box.add_child(MenuUI.row("Bot difficulty", difficulty))

	var map := OptionButton.new()
	for map_name in config.map_names:
		map.add_item(map_name)
	map.select(config.map_index)
	map.item_selected.connect(func(i): config.map_index = i)
	box.add_child(MenuUI.row("Map", map))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 16)
	buttons.add_child(MenuUI.button("Back", GameState.goto_main_menu, 200))
	var go := MenuUI.button("Choose heroes", GameState.goto_hero_select, 280)
	buttons.add_child(go)
	box.add_child(Control.new())
	box.add_child(buttons)
	add_child(MenuUI.centered(panel))
	go.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		GameState.goto_main_menu()
