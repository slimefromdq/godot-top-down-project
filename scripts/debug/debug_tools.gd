extends CanvasLayer

# Autoload "DebugTools": the balance workbench, on every map.
#
#   F1  Debug panel     level, live ability/stat/feel editing with reset,
#                       dummy spawning and settings, cooldowns off, god mode,
#                       hero swap, CSV export, validation, map switching
#   F2  Stat inspector  HP, effective HP, stats and every ability number at
#                       the current level
#   F4  Damage meter    total, rolling DPS, breakdown by source, healing
#                       received, damage taken
#
# Everything here edits RUNTIME copies (each hero and ability owns a private
# duplicate of its data), so nothing is written to .tres files and "Reset"
# always restores the designer's values. Built in code rather than a .tscn so
# it's one self-contained file that follows the data as heroes change.

const PANEL_WIDTH := 470.0
const INSPECT_INTERVAL := 0.25
const HERO_BASE := "res://scenes/heroes/hero_base.tscn"
const DUMMY_SCENE := "res://scenes/training_dummy.tscn"
const SPAWNED_GROUP := &"debug_spawned_dummies"
const PLAYER_LISTENERS := &"player_listeners"

var meter: DamageMeter

var _panel: PanelContainer
var _tabs: TabContainer
var _inspector: PanelContainer
var _inspector_label: Label
var _meter_panel: PanelContainer
var _meter_label: Label
var _inspect_timer: float = 0.0

# Dummy settings used by the Dummies tab.
var dummy_health: float = 2000.0
var dummy_armor: float = 0.0
var dummy_magic_resist: float = 0.0
var dummy_level: int = 1
var dummy_fight_back: bool = false
var dummy_can_die: bool = false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	meter = DamageMeter.new()
	meter.name = "DamageMeter"
	add_child(meter)
	meter.changed.connect(_refresh_meter)
	_build_inspector()
	_build_meter()
	_build_panel()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_panel"):
		toggle_panel()
	elif event.is_action_pressed(&"debug_inspector"):
		_inspector.visible = not _inspector.visible
	elif event.is_action_pressed(&"debug_meter"):
		_meter_panel.visible = not _meter_panel.visible
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_inspect_timer -= delta
	if _inspect_timer <= 0.0:
		_inspect_timer = INSPECT_INTERVAL
		if _inspector.visible:
			_inspector_label.text = inspect_text()
		if _meter_panel.visible:
			_refresh_meter()


func get_player() -> Hero:
	return get_tree().get_first_node_in_group(&"player") as Hero


func toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		rebuild_panel()
	# Both live in the top-right corner; slide the meter left of the panel.
	var shift := PANEL_WIDTH if _panel.visible else 0.0
	_meter_panel.offset_left = -380 - shift
	_meter_panel.offset_right = -20 - shift


# ---------------------------------------------------------------------------
# Actions (public so tests and other tools can drive them)
# ---------------------------------------------------------------------------

func set_player_level(level: int) -> void:
	var hero := get_player()
	if hero != null:
		hero.stats_component.set_level(level)


func set_level_cap(cap: int) -> void:
	GameRules.current().max_level = clampi(cap, 1, StatScaling.LEVEL_DOMAIN)


func set_cooldowns_disabled(disabled: bool) -> void:
	Ability.cooldowns_disabled = disabled
	if disabled:
		for node in get_tree().get_nodes_in_group(&"heroes"):
			for ability in (node as Hero).ability_controller.abilities:
				ability.cooldown_remaining = 0.0


func set_god_mode(enabled: bool) -> void:
	var hero := get_player()
	if hero != null:
		hero.health_component.god_mode = enabled


func spawn_dummy(at: Vector2) -> TrainingDummy:
	var dummy: TrainingDummy = load(DUMMY_SCENE).instantiate()
	dummy.max_health = dummy_health
	dummy.armor = dummy_armor
	dummy.magic_resist = dummy_magic_resist
	dummy.level = dummy_level
	dummy.fight_back = dummy_fight_back
	dummy.can_die = dummy_can_die
	dummy.position = at
	dummy.add_to_group(SPAWNED_GROUP)
	get_tree().current_scene.add_child(dummy)
	return dummy


# In front of the player, where they're aiming.
func spawn_point(distance: float = 260.0) -> Vector2:
	var hero := get_player()
	if hero == null:
		return Vector2.ZERO
	return hero.global_position + hero.aim_direction * distance


func spawn_pack(center: Vector2, count: int = 5, spacing: float = 90.0) -> void:
	for i in count:
		var offset := Vector2.from_angle(TAU * i / count) * spacing if i > 0 else Vector2.ZERO
		spawn_dummy(center + offset)


func apply_to_all_dummies() -> void:
	for node in get_tree().get_nodes_in_group(&"training_dummies"):
		var dummy := node as TrainingDummy
		dummy.configure(dummy_health, dummy_armor, dummy_magic_resist, dummy_level)
		dummy.set_fight_back(dummy_fight_back)
		dummy.can_die = dummy_can_die


func set_all_dummies_fight_back(enabled: bool) -> void:
	dummy_fight_back = enabled
	for node in get_tree().get_nodes_in_group(&"training_dummies"):
		(node as TrainingDummy).set_fight_back(enabled)


func clear_spawned_dummies() -> void:
	for node in get_tree().get_nodes_in_group(SPAWNED_GROUP):
		node.queue_free()


# Where the CSV goes: into the project when running from the editor (so it's
# next to your R scripts), user:// in an exported build.
func export_path() -> String:
	return "res://balance/balance_export.csv" if OS.has_feature("editor") else "user://balance_export.csv"


func export_balance() -> String:
	var path := export_path()
	var error := BalanceExporter.export_all(path)
	return error if error != "" else "Wrote %s" % ProjectSettings.globalize_path(path)


func validate_heroes() -> String:
	var lines := PackedStringArray()
	for definition in HeroScaffold.find_definitions():
		var problems := definition.validate()
		lines.append("%s: %s" % [definition.hero_id, "OK" if problems.is_empty() else "\n  - " + "\n  - ".join(problems)])
	return "\n".join(lines)


# Replace the local player with another hero, keeping position, team and level.
func swap_player(definition: HeroDefinition) -> Hero:
	var old := get_player()
	if old == null or definition == null:
		return null
	var scene: PackedScene = definition.scene_override if definition.scene_override != null else load(HERO_BASE)
	var hero: Hero = scene.instantiate()
	hero.definition = definition
	hero.player_controlled = true
	hero.team = old.team
	hero.start_level = old.get_level()
	var parent := old.get_parent()
	var index := old.get_index()
	var at := old.global_position
	old.remove_from_group(&"player")
	old.remove_from_group(&"heroes")
	parent.remove_child(old)
	old.queue_free()
	hero.name = "Player"
	parent.add_child(hero)
	parent.move_child(hero, index)
	hero.global_position = at
	get_tree().call_group(PLAYER_LISTENERS, &"on_player_replaced", hero)
	meter.reset()
	if _panel.visible:
		rebuild_panel.call_deferred()
	return hero


# ---------------------------------------------------------------------------
# Stat inspector (F2)
# ---------------------------------------------------------------------------

func inspect_text() -> String:
	var hero := get_player()
	if hero == null or hero.definition == null:
		return "No hero"
	var stats := hero.stats_component
	var health := hero.health_component
	var lines := PackedStringArray()
	lines.append("%s %s  (%s)   Lv %d / %d" % [hero.definition.display_name, hero.definition.title,
		hero.definition.get_role_name(), stats.level, stats.get_max_level()])
	lines.append("HP %d / %d    EHP phys %d  magic %d" % [health.current_health, health.max_health,
		health.get_effective_health(DamageInfo.Type.PHYSICAL), health.get_effective_health(DamageInfo.Type.MAGIC)])
	lines.append("Weapon %.0f   Magic %.0f   Armor %.0f   MR %.0f   Speed %.0f" % [stats.get_weapon(),
		stats.get_magic(), stats.get_stat(StatBlock.ARMOR), stats.get_stat(StatBlock.MAGIC_RESIST),
		hero.movement_component.get_move_speed()])
	if health.god_mode or Ability.cooldowns_disabled:
		lines.append("[%s%s]" % ["GOD MODE " if health.god_mode else "", "NO COOLDOWNS" if Ability.cooldowns_disabled else ""])
	for ability in hero.ability_controller.abilities:
		if ability.data == null:
			continue
		lines.append("")
		lines.append("%s  [%s]  cd %.1fs%s" % [ability.display_name, ability.slot_id, ability.get_cooldown(),
			"  (%.1f)" % ability.cooldown_remaining if ability.cooldown_remaining > 0.0 else ""])
		var values := ability.data.get_scaling_values()
		for path in values:
			var value: ScalingValue = values[path]
			if value != null:
				lines.append("   %-28s %6.1f   = %s" % [path, value.evaluate(stats), value.describe()])
	return "\n".join(lines)


func _build_inspector() -> void:
	_inspector = _make_panel(Color(0.05, 0.06, 0.08, 0.8))
	_inspector.position = Vector2(16, 48)
	_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspector_label = Label.new()
	_inspector_label.add_theme_font_size_override(&"font_size", 13)
	_inspector.add_child(_inspector_label)
	_inspector.visible = false
	add_child(_inspector)


# ---------------------------------------------------------------------------
# Damage meter (F4)
# ---------------------------------------------------------------------------

func meter_text() -> String:
	var lines := PackedStringArray()
	lines.append("DAMAGE METER   (DPS over %ds)" % meter.window)
	lines.append("Dealt %d   DPS %.0f   over %.0fs" % [meter.get_total_dealt(), meter.get_dps(), meter.get_elapsed()])
	for row in meter.get_dealt_breakdown():
		lines.append("  %-16s %7d  %3d%%  x%d" % [row.label, row.total, roundi(row.share * 100.0), row.hits])
	lines.append("Healing received %d" % meter.get_total_healed())
	for row in meter.get_healing_breakdown():
		lines.append("  %-16s %7d  %3d%%" % [row.label, row.total, roundi(row.share * 100.0)])
	lines.append("Damage taken %d" % meter.get_total_taken())
	return "\n".join(lines)


func _build_meter() -> void:
	_meter_panel = _make_panel(Color(0.05, 0.06, 0.08, 0.8))
	var box := VBoxContainer.new()
	_meter_label = Label.new()
	_meter_label.add_theme_font_size_override(&"font_size", 13)
	box.add_child(_meter_label)
	var reset := Button.new()
	reset.text = "Reset meter"
	reset.pressed.connect(meter.reset)
	box.add_child(reset)
	_meter_panel.add_child(box)
	add_child(_meter_panel)
	# Anchored to the top-right corner of the screen.
	_meter_panel.anchor_left = 1.0
	_meter_panel.anchor_right = 1.0
	_meter_panel.offset_left = -380
	_meter_panel.offset_right = -20
	_meter_panel.offset_top = 48
	_refresh_meter()


func _refresh_meter() -> void:
	if _meter_label != null and _meter_panel.visible:
		_meter_label.text = meter_text()


# ---------------------------------------------------------------------------
# Debug panel (F1)
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = _make_panel(Color(0.07, 0.08, 0.1, 0.94))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_top = 40
	_panel.offset_bottom = -150
	_tabs = TabContainer.new()
	_panel.add_child(_tabs)
	_panel.visible = false
	add_child(_panel)


func rebuild_panel() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var hero := get_player()
	_tabs.add_child(_scroll("Hero", _hero_tab(hero)))
	_tabs.add_child(_scroll("Abilities", _abilities_tab(hero)))
	_tabs.add_child(_scroll("Dummies", _dummies_tab()))
	_tabs.add_child(_scroll("Feel", _feel_tab(hero)))
	_tabs.add_child(_scroll("Tools", _tools_tab()))


func _hero_tab(hero: Hero) -> Control:
	var box := VBoxContainer.new()
	if hero == null:
		box.add_child(_label("No player hero in this scene."))
		return box
	box.add_child(_label("%s %s (%s)" % [hero.definition.display_name, hero.definition.title, hero.definition.get_role_name()], 18))

	var stats_label := _label("")
	var refresh := func(): stats_label.text = _stats_summary(hero)

	var level_row := HBoxContainer.new()
	level_row.add_child(_label("Level"))
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = GameRules.current().max_level
	slider.step = 1
	slider.value = hero.get_level()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var level_value := _label(str(hero.get_level()))
	slider.value_changed.connect(func(v: float):
		set_player_level(int(v))
		level_value.text = str(hero.get_level())
		refresh.call())
	level_row.add_child(slider)
	level_row.add_child(level_value)
	box.add_child(level_row)

	var cap_row := HBoxContainer.new()
	cap_row.add_child(_label("Level cap (playtest)"))
	var cap := _spin(GameRules.current().max_level, 1, StatScaling.LEVEL_DOMAIN, 1)
	cap.value_changed.connect(func(v: float):
		set_level_cap(int(v))
		slider.max_value = GameRules.current().max_level)
	cap_row.add_child(cap)
	box.add_child(cap_row)

	box.add_child(stats_label)
	refresh.call()
	# The panel is rebuilt often; drop this connection with its label.
	hero.stats_component.stats_changed.connect(refresh)
	# A weak reference: the hero may be freed first (hero swap, map change).
	var hero_ref: WeakRef = weakref(hero)
	stats_label.tree_exiting.connect(func():
		var h: Hero = hero_ref.get_ref()
		if h != null and h.stats_component.stats_changed.is_connected(refresh):
			h.stats_component.stats_changed.disconnect(refresh))

	box.add_child(_check("God mode", hero.health_component.god_mode, set_god_mode))
	box.add_child(_check("Cooldowns off", Ability.cooldowns_disabled, set_cooldowns_disabled))
	var buttons := HFlowContainer.new()
	buttons.add_child(_button("Full heal", func(): hero.health_component.heal(hero.health_component.max_health, null, &"debug")))
	buttons.add_child(_button("Take lethal hit", func():
		hero.health_component.apply_damage(DamageInfo.create(hero.health_component.current_health + 1.0, null, DamageInfo.Type.TRUE))))
	buttons.add_child(_button("Reset stats + feel", func():
		hero.reset_tuning()
		rebuild_panel()))
	box.add_child(buttons)

	var swap_row := HBoxContainer.new()
	var options := OptionButton.new()
	var definitions := HeroScaffold.find_definitions()
	for definition in definitions:
		options.add_item(definition.display_name)
	# Test-only heroes (tools/heroes/*) while developing; never in a roster.
	if OS.is_debug_build():
		for definition in HeroScaffold.find_dev_definitions():
			definitions.append(definition)
			options.add_item("%s (test)" % definition.display_name)
	swap_row.add_child(options)
	swap_row.add_child(_button("Play as", func():
		if options.selected >= 0:
			swap_player(definitions[options.selected])))
	box.add_child(swap_row)

	box.add_child(_label("Base stats (live, this hero only)", 15))
	var editor := PropertyEditor.new()
	editor.edit(hero.stats_component.stat_block)
	editor.value_changed.connect(func(_r, _p, _v): hero.stats_component.stats_changed.emit())
	box.add_child(editor)
	return box


func _stats_summary(hero: Hero) -> String:
	var s := hero.stats_component
	var h := hero.health_component
	return "Health %d   Weapon %.0f   Magic %.0f\nArmor %.0f   Magic resist %.0f\nEHP physical %d   EHP magic %d" % [
		h.max_health, s.get_weapon(), s.get_magic(), s.get_stat(StatBlock.ARMOR),
		s.get_stat(StatBlock.MAGIC_RESIST), h.get_effective_health(DamageInfo.Type.PHYSICAL),
		h.get_effective_health(DamageInfo.Type.MAGIC)]


func _abilities_tab(hero: Hero) -> Control:
	var box := VBoxContainer.new()
	if hero == null:
		return box
	box.add_child(_label("Edits apply on the next cast. Reset restores the .tres values."))
	for ability in hero.ability_controller.abilities:
		if ability.data == null:
			continue
		var header := HBoxContainer.new()
		header.add_child(_label("%s  [%s]" % [ability.display_name, ability.slot_id], 16))
		header.add_child(_button("Reset", func():
			ability.reset_data()
			rebuild_panel.call_deferred()
			_tabs.current_tab = 1))
		box.add_child(header)
		var editor := PropertyEditor.new()
		editor.edit(ability.data)
		box.add_child(editor)
		box.add_child(HSeparator.new())
	return box


func _dummies_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_label("Settings for new dummies (and 'Apply to all')"))
	box.add_child(_labeled_spin("Health", dummy_health, 1, 100000, 50, func(v): dummy_health = v))
	box.add_child(_labeled_spin("Armor", dummy_armor, -100, 1000, 5, func(v): dummy_armor = v))
	box.add_child(_labeled_spin("Magic resist", dummy_magic_resist, -100, 1000, 5, func(v): dummy_magic_resist = v))
	box.add_child(_labeled_spin("Level", dummy_level, 1, 20, 1, func(v): dummy_level = int(v)))
	box.add_child(_check("Fight back (new dummies)", dummy_fight_back, func(on): dummy_fight_back = on))
	box.add_child(_check("Can die", dummy_can_die, func(on): dummy_can_die = on))
	var buttons := HFlowContainer.new()
	buttons.add_child(_button("Spawn dummy", func(): spawn_dummy(spawn_point())))
	buttons.add_child(_button("Spawn pack of 5", func(): spawn_pack(spawn_point(320.0))))
	buttons.add_child(_button("Apply to all dummies", apply_to_all_dummies))
	buttons.add_child(_button("Remove spawned", clear_spawned_dummies))
	box.add_child(buttons)
	box.add_child(_check("ALL dummies fight back", dummy_fight_back, set_all_dummies_fight_back))
	return box


func _feel_tab(hero: Hero) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_label("Global comfort settings", 16))
	var settings_editor := PropertyEditor.new()
	settings_editor.edit(GameFeel.settings)
	box.add_child(settings_editor)
	if hero != null and hero.feel_profile != null:
		box.add_child(HSeparator.new())
		box.add_child(_label("%s's FeelProfile (live)" % hero.definition.display_name, 16))
		var feel_editor := PropertyEditor.new()
		feel_editor.edit(hero.feel_profile)
		box.add_child(feel_editor)
	return box


func _tools_tab() -> Control:
	var box := VBoxContainer.new()
	var result := _label("")
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_button("Export balance CSV", func(): result.text = export_balance()))
	box.add_child(_button("Validate heroes", func(): result.text = validate_heroes()))
	box.add_child(_button("Reset damage meter", meter.reset))
	box.add_child(_check("Stat inspector (F2)", _inspector.visible, func(on): _inspector.visible = on))
	box.add_child(_check("Damage meter (F4)", _meter_panel.visible, func(on): _meter_panel.visible = on))
	box.add_child(_label("Maps (F3 cycles)", 15))
	for path in GameRules.current().test_maps:
		box.add_child(_button(path.get_file().get_basename().capitalize(), func(): MapSwitcher.go_to(path)))
	box.add_child(result)
	return box


# ---------------------------------------------------------------------------
# Small UI helpers
# ---------------------------------------------------------------------------

func _make_panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(10)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	return panel


func _scroll(title: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _label(text: String, size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	return label


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	return button


func _check(text: String, value: bool, on_toggle: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(on_toggle)
	return box


func _spin(value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 110
	return spin


func _labeled_spin(text: String, value: float, min_value: float, max_value: float, step: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := _spin(value, min_value, max_value, step)
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return row
