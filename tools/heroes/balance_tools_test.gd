extends Node

# Headless checks for the balance tools: CSV export, debug panel actions,
# damage meter, stat inspector, hero swap, validation.
#
#   godot --headless res://tools/heroes/balance_tools_test.tscn

const CSV_PATH := "user://balance_tools_test.csv"
const LEVELS := [1, 5, 10, 15, 20]
## If fewer checks than this ran, a script error cut the test short.
const MIN_CHECKS := 40

var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check("DebugTools autoload loaded", get_node_or_null(^"/root/DebugTools") != null \
		and get_node(^"/root/DebugTools").has_method(&"get_player"), "")
	_test_csv()
	# This node is the current scene; hand that role to a placeholder so
	# changing scenes doesn't free the test.
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	get_tree().change_scene_to_file("res://scenes/training_grounds_world.tscn")
	await _frames(5)
	await _test_levels()
	await _test_live_edit_and_reset()
	await _test_toggles()
	await _test_dummies()
	await _test_meter_and_inspector()
	_test_panel_and_validation()
	await _test_swap_to_second_hero()
	_check("all checks ran (no script errors)", checks >= MIN_CHECKS, "%d checks" % checks)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_csv() -> void:
	var error := BalanceExporter.export_all(CSV_PATH)
	_check("CSV export runs", error == "", error)
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header := file.get_csv_line()
	_check("tidy header", Array(header) == BalanceExporter.HEADER, ",".join(header))
	var rows := 0
	var bad := 0
	var keys := {}
	var dupes := 0
	var heroes := {}
	var levels := {}
	var rook_weapon := {}
	var avery_health := {}
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() == 1 and line[0] == "":
			continue
		rows += 1
		if line.size() != header.size() or not line[7].is_valid_float() or not line[2].is_valid_int():
			bad += 1
			continue
		var key := "|".join(line.slice(0, 7))
		if keys.has(key):
			dupes += 1
		keys[key] = true
		heroes[line[0]] = true
		levels[int(line[2])] = true
		if line[0] == "rook" and line[6] == "weapon":
			rook_weapon[int(line[2])] = float(line[7])
		if line[0] == "avery" and line[6] == "health":
			avery_health[int(line[2])] = float(line[7])
	_check("every row has 8 cells and a numeric value", bad == 0 and rows > 0, "%d rows, %d bad" % [rows, bad])
	_check("one row per hero x level x metric (no duplicates)", dupes == 0, "%d dupes" % dupes)
	_check("levels 1/5/10/15/20", levels.keys().size() == 5 and LEVELS.all(func(l): return levels.has(l)), str(levels.keys()))
	_check("both heroes exported, template skipped", heroes.has("avery") and heroes.has("rook") and not heroes.has("template"), str(heroes.keys()))
	_check("Avery grows linearly", is_equal_approx(avery_health[10] - avery_health[5], avery_health[20] - avery_health[15]), "")
	_check("Rook's weapon curve spikes late",
		rook_weapon[20] - rook_weapon[15] > 2.0 * (rook_weapon[10] - rook_weapon[5]),
		"5->10 +%.1f, 15->20 +%.1f" % [rook_weapon[10] - rook_weapon[5], rook_weapon[20] - rook_weapon[15]])


func _test_levels() -> void:
	var hero := DebugTools.get_player()
	var def := hero.definition
	var searing := hero.get_ability(&"ability_1")
	var heal_1: float = searing.data.heal_per_target.evaluate(hero.stats_component)
	DebugTools.set_player_level(10)
	await _frames(1)
	var s := hero.stats_component
	var all_match := true
	for stat in StatBlock.ALL:
		if not is_equal_approx(s.get_stat(stat), def.stats.value_at(stat, 10)):
			all_match = false
	_check("level 10 recomputes every stat", all_match and s.level == 10, "")
	_check("max HP follows", is_equal_approx(hero.health_component.max_health, def.stats.value_at(StatBlock.HEALTH, 10)), "")
	_check("ability numbers follow the level",
		searing.data.heal_per_target.evaluate(s) > heal_1 and searing.get_cooldown() < searing.data.cooldown, "")
	DebugTools.set_level_cap(20)
	DebugTools.set_player_level(20)
	_check("level cap can be raised for playtests", s.level == 20, str(s.level))
	DebugTools.set_level_cap(10)
	DebugTools.set_player_level(1)
	_check("back to level 1", s.level == 1 and is_equal_approx(hero.health_component.max_health, def.stats.health.base), "")


func _test_live_edit_and_reset() -> void:
	var hero := DebugTools.get_player()
	var primary := hero.get_ability(&"primary")
	var step: AttackStep = primary.data.combo_steps[0]
	var disk: MeleeAttackData = load("res://heroes/avery/abilities/sunblade_slash.tres")
	var original: float = disk.combo_steps[0].damage.base
	step.damage.base = 500.0
	_check("live edit changes the runtime copy", is_equal_approx(primary.data.combo_steps[0].damage.base, 500.0), "")
	_check("live edit leaves the .tres alone", is_equal_approx(disk.combo_steps[0].damage.base, original), "")
	primary.reset_data()
	_check("reset restores the .tres value", is_equal_approx(primary.data.combo_steps[0].damage.base, original), "")
	hero.stats_component.stat_block.health.base = 9999.0
	hero.stats_component.stats_changed.emit()
	hero.reset_tuning()
	_check("stat reset restores the definition", is_equal_approx(hero.health_component.max_health, hero.definition.stats.health.base), "")


func _test_toggles() -> void:
	var hero := DebugTools.get_player()
	var searing := hero.get_ability(&"ability_1")
	DebugTools.set_cooldowns_disabled(true)
	hero.request_slot(&"ability_1", hero.global_position + Vector2(200, 0))
	await _seconds(0.8)
	_check("cooldowns off: cast again immediately", searing.is_ready(), "")
	DebugTools.set_cooldowns_disabled(false)
	hero.request_slot(&"ability_1", hero.global_position + Vector2(200, 0))
	await _seconds(0.1)
	_check("cooldowns back on", not searing.is_ready(), "")
	searing.cooldown_remaining = 0.0

	DebugTools.set_god_mode(true)
	var hp := hero.health_component.current_health
	hero.health_component.apply_damage(DamageInfo.create(99999.0, null, DamageInfo.Type.TRUE))
	_check("god mode takes no damage", is_equal_approx(hero.health_component.current_health, hp), "")
	DebugTools.set_god_mode(false)
	await _seconds(0.6)


func _test_dummies() -> void:
	DebugTools.dummy_health = 1234.0
	DebugTools.dummy_armor = 75.0
	DebugTools.dummy_magic_resist = 40.0
	DebugTools.dummy_level = 4
	var dummy := DebugTools.spawn_dummy(Vector2(0, 900))
	await _frames(2)
	_check("spawned dummy uses the configured HP/resists/level",
		is_equal_approx(dummy.health_component.max_health, 1234.0)
		and is_equal_approx(dummy.stats_component.get_stat(StatBlock.ARMOR), 75.0)
		and is_equal_approx(dummy.stats_component.get_stat(StatBlock.MAGIC_RESIST), 40.0)
		and dummy.stats_component.level == 4, "")
	var physical := dummy.health_component.mitigate(100.0, DamageInfo.Type.PHYSICAL)
	_check("dummy armor reduces damage", is_equal_approx(physical, 100.0 * 100.0 / 175.0), "%.1f" % physical)
	DebugTools.set_all_dummies_fight_back(true)
	_check("dummies fight back on toggle", dummy.fight_back and dummy.team == dummy.fight_back_team, "")
	DebugTools.set_all_dummies_fight_back(false)
	_check("and stop", not dummy.fight_back and dummy.team == &"", "")
	DebugTools.clear_spawned_dummies()
	await _frames(2)
	_check("spawned dummies removed", get_tree().get_nodes_in_group(DebugTools.SPAWNED_GROUP).is_empty(), "")
	DebugTools.dummy_health = 2000.0
	DebugTools.dummy_armor = 0.0
	DebugTools.dummy_magic_resist = 0.0
	DebugTools.dummy_level = 1


func _test_meter_and_inspector() -> void:
	var hero := DebugTools.get_player()
	var plain := get_tree().current_scene.get_node("Dummies/Plain") as Node2D
	hero.global_position = plain.global_position + Vector2(-140, 0)
	hero.velocity = Vector2.ZERO
	await _frames(2)
	DebugTools.meter.reset()
	hero.health_component.current_health = 200.0
	# Searing Cut first: the finisher's knockback would push the dummy out
	# of its reach.
	hero.request_slot(&"ability_1", plain.global_position)
	await _seconds(0.8)
	for i in 3:
		hero.request_slot(&"primary", plain.global_position)
		await _seconds(0.5)
	await _seconds(1.5)
	var labels := DebugTools.meter.get_dealt_breakdown().map(func(r): return str(r.label))
	for expected in ["blade", "crescent", "burn", "searing_cut"]:
		_check("meter breaks out '%s'" % expected, expected in labels, str(labels))
	_check("meter DPS > 0", DebugTools.meter.get_dps() > 0.0, "%.1f" % DebugTools.meter.get_dps())
	var heals := DebugTools.meter.get_healing_breakdown().map(func(r): return str(r.label))
	_check("meter shows healing received by source", "searing_cut_heal" in heals, str(heals))
	var shares := 0.0
	for row in DebugTools.meter.get_dealt_breakdown():
		shares += row.share
	_check("breakdown shares add to 100%", is_equal_approx(shares, 1.0), "%.3f" % shares)
	var text := DebugTools.inspect_text()
	_check("inspector lists ability numbers", text.contains("Sunblade Slash") and text.contains("heal_per_target") and text.contains("EHP"), "")
	_check("meter text renders", DebugTools.meter_text().contains("blade"), "")


func _test_panel_and_validation() -> void:
	DebugTools.toggle_panel()
	var tabs: TabContainer = DebugTools._tabs
	_check("F1 panel builds its 5 tabs", tabs.get_child_count() == 5, str(tabs.get_child_count()))
	var editors := tabs.find_children("*", "PropertyEditor", true, false)
	var spins := tabs.find_children("*", "SpinBox", true, false)
	_check("ability/stat editors have live number fields", editors.size() >= 5 and spins.size() > 40, "%d editors, %d fields" % [editors.size(), spins.size()])
	DebugTools.toggle_panel()
	var report := DebugTools.validate_heroes()
	_check("Avery validates clean", report.contains("avery: OK"), report)
	_check("Rook reports its unfilled slots", report.contains("rook:") and report.contains("missing required slot"), "")


func _test_swap_to_second_hero() -> void:
	var rook_def: HeroDefinition = load("res://heroes/rook/rook_definition.tres")
	var rook := DebugTools.swap_player(rook_def)
	await _frames(3)
	_check("swapped to Rook", DebugTools.get_player() == rook and rook.definition.hero_id == &"rook", "")
	var world := get_tree().current_scene
	_check("world tracks the new player", world.get(&"player") == rook, "")
	var bar := world.get_node("AbilityBar") as AbilityBar
	_check("HUD rebuilt for Rook's single ability", bar.slots.get_child_count() == 1, str(bar.slots.get_child_count()))
	var plain := world.get_node("Dummies/Plain") as Node2D
	rook.global_position = plain.global_position + Vector2(-140, 0)
	rook.health_component.current_health = 100.0
	await _frames(2)
	rook.request_slot(&"primary", plain.global_position)
	await _seconds(0.6)
	_check("Rook's basic attack lands and lifesteals", rook.health_component.current_health > 100.0,
		"%.1f" % rook.health_component.current_health)


func _check(label: String, ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
