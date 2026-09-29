extends Node

# Writes resources/rules/map_events.tres: the default numbers for the Black
# Market, the Mote Island and the Wanderer, with the market's stock and the
# Wanderer's body embedded. Run it to regenerate the file from scratch:
#
#   godot --headless res://tools/events/build_map_events.tscn
#
# After that, edit the .tres (or F1 > Match > Map events) to balance; there is
# no need to run this again unless you want the defaults back.

const OUT := "res://resources/rules/map_events.tres"


func _ready() -> void:
	var rules := MapEventRules.new()
	rules.blackmarket_items = [_overclock(), _glass_cannon(), _phase_cloak(), _mote_magnet(), _second_wind()]
	rules.wanderer_data = _wanderer()
	for problem in rules.validate():
		printerr("PROBLEM: ", problem)
	var err := ResourceSaver.save(rules, OUT)
	print("saved ", OUT, " (", error_string(err), ")")
	get_tree().quit(0 if err == OK else 1)


func _status(id: StringName, title: String) -> StatusEffect:
	var status := StatusEffect.new()
	status.id = id
	status.display_name = title
	status.duration = 60.0
	return status


func _overclock() -> BlackMarketItem:
	var status := _status(&"overclock", "Overclock")
	status.stat_multipliers = {&"fire_rate": 1.4, &"move_speed": 1.2}
	status.body_tint = Color(0.35, 0.85, 1.0, 0.18)
	var item := BlackMarketItem.new()
	item.id = &"overclock"
	item.display_name = "Overclock"
	item.description = "Guns fire and you run faster."
	item.glyph = ">>"
	item.color = Color("38bdf8")
	item.mote_cost = 3
	item.gold_cost = 350
	item.status = status
	item.bot_priority = 5
	return item


func _glass_cannon() -> BlackMarketItem:
	var status := _status(&"glass_cannon", "Glass Cannon")
	status.stat_multipliers = {&"damage": 1.5}
	status.stat_modifiers = [StatModifier.make(StatBlock.HEALTH, 0.0, -0.3, &"glass_cannon")]
	status.cleansable = false
	status.body_tint = Color(1.0, 0.35, 0.4, 0.16)
	var item := BlackMarketItem.new()
	item.id = &"glass_cannon"
	item.display_name = "Glass Cannon"
	item.description = "Weapon and magic hit harder; you have less health."
	item.glyph = "!"
	item.color = Color("fb7185")
	item.mote_cost = 4
	item.gold_cost = 400
	item.status = status
	item.bot_priority = 4
	return item


func _phase_cloak() -> BlackMarketItem:
	var status := _status(&"phase_cloak", "Phase Cloak")
	status.invisible = true
	status.body_alpha = 0.35
	var item := BlackMarketItem.new()
	item.id = &"phase_cloak"
	item.display_name = "Phase Cloak"
	item.description = "A short invulnerable dash, then unseen by enemies."
	item.glyph = "~"
	item.color = Color("a78bfa")
	item.mote_cost = 3
	item.gold_cost = 300
	# The invisibility lasts this long once the dash lands.
	item.duration = 5.0
	item.status = status
	item.effect = load("res://scripts/events/phase_cloak_effect.gd")
	item.values = {&"dash_distance": 450.0, &"dash_time": 0.25, &"invuln_grace": 0.1}
	item.bot_priority = 1
	return item


func _mote_magnet() -> BlackMarketItem:
	var status := _status(&"mote_magnet", "Mote Magnet")
	status.stat_multipliers = {&"mote_pickup_radius": 2.0}
	status.body_tint = Color(0.99, 0.88, 0.28, 0.14)
	var item := BlackMarketItem.new()
	item.id = &"mote_magnet"
	item.display_name = "Mote Magnet"
	item.description = "Loose Motes fly to you; you grab them from further away."
	item.glyph = "U"
	item.color = Color("fde047")
	item.mote_cost = 2
	item.gold_cost = 250
	item.status = status
	item.effect = load("res://scripts/events/mote_magnet_effect.gd")
	item.values = {&"pull_radius": 700.0, &"pull_speed": 900.0}
	item.bot_priority = 3
	return item


func _second_wind() -> BlackMarketItem:
	var item := BlackMarketItem.new()
	item.id = &"second_wind"
	item.display_name = "Second Wind"
	item.description = "Heal 60% of your max health and shake off every harmful effect."
	item.glyph = "+"
	item.color = Color("4ade80")
	item.mote_cost = 3
	item.gold_cost = 300
	item.effect = load("res://scripts/events/second_wind_effect.gd")
	item.values = {&"heal_pct": 0.6}
	item.bot_priority = 2
	return item


func _scaling(base: float, growth: float) -> StatScaling:
	return StatScaling.make(base, growth)


func _wanderer() -> NeutralData:
	var data := NeutralData.new()
	data.id = &"wanderer"
	data.display_name = "Wanderer"
	var block := StatBlock.new()
	# About 7 hits from a typical hero at any level (their damage per shot
	# runs ~25 at level 1 to ~50 at 13): balance against the CSV.
	block.health = _scaling(180.0, 15.0)
	block.weapon = _scaling(0.0, 0.0)
	block.magic = _scaling(0.0, 0.0)
	block.armor = _scaling(0.0, 0.0)
	block.magic_resist = _scaling(0.0, 0.0)
	data.stats = block
	data.look_scene = load("res://scenes/match/neutral_look.tscn")
	data.size = 64.0
	data.color = Color("fde047")
	data.icon_color = Color("fde047")
	return data
