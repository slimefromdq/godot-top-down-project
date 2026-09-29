extends Node2D

# Headless checks for the "feel" patch: guns have no ammo (fire continuously),
# the faster economy and the easier Island / richer Wanderer, the bots' Mote
# plans, the kill marker and sound, the MVP stats and end screen, and the
# reworked shop window.
#
#   godot --headless res://tools/match/feel_patch_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"

var failures := 0
var manager: MatchManager
var rules: MatchRules
var a1: Hero
var a2: Hero
var b1: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map := GameMap.new()
	add_child(map)
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.respawn_base = 0.3
	rules.respawn_per_level = 0.0
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	a1 = _hero(&"a", Vector2(-200, 0))
	a2 = _hero(&"a", Vector2(200, 0))
	b1 = _hero(&"b", Vector2(0, -300))
	a1.add_to_group(&"player")
	await _frames(3)
	manager.start_warmup()
	await _frames(3)

	_test_no_ammo()
	_test_economy_and_events()
	_test_bot_plans()
	await _test_kill_feedback()
	await _test_mvp()
	await _test_shop_panel()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_no_ammo() -> void:
	print("\n-- No ammo")
	var gun := a1.get_reload_ability()
	_check("guns have no magazine by default", not GameRules.current().ammo_enabled and gun != null
		and not gun.has_magazine() and gun.get_max_ammo() == 0, "")
	_check("so there is nothing to reload", not gun.start_reload() and not a1.reload(), "")
	GameRules.current().ammo_enabled = true
	var data_has_magazine := gun.get_ranged_data().magazine_size > 0
	_check("the ammo code still works when a mode turns it on", not data_has_magazine or gun.has_magazine(),
		str(gun.get_max_ammo()))
	GameRules.current().ammo_enabled = false
	_check("and off again", not gun.has_magazine(), "")


func _test_economy_and_events() -> void:
	print("\n-- Economy and map events")
	_check("a kill pays at least 250 gold, an assist 100", rules.kill_gold >= 250.0 and rules.assist_gold >= 100.0,
		"%s / %s" % [rules.kill_gold, rules.assist_gold])
	var events := rules.map_events
	if events == null:
		events = load("res://resources/rules/map_events.tres")
	_check("the Island is easier to find and use", events.island_interact_tiles >= 2.5
		and events.island_visible_tiles >= 5.0 and events.island_shimmer_tiles > events.island_visible_tiles
		and events.island_stay_time >= 15.0, "")
	_check("the Wanderer drops more Motes", events.wanderer_motes_per_hit >= 2 and events.wanderer_max_motes >= 10, "")
	_check("the map event rules still validate", events.validate().is_empty(), str(events.validate()))


func _test_bot_plans() -> void:
	print("\n-- Bot Mote plans")
	var carry: BotRolePlan = BotRules.current().carry_plan
	var all_ok := true
	for plan in [BotRules.current().tank_plan, BotRules.current().carry_plan, BotRules.current().tempo_plan,
			BotRules.current().flex_plan]:
		all_ok = all_ok and plan.deposit_value <= 8
	_check("every role deposits a smaller stack", all_ok, "")
	_check("the carry plan delivers earlier (wake 25% / level 4)", carry.deliver_when_enemy_wake <= 0.3
		and carry.deliver_from_level <= 4, "%s / %s" % [carry.deliver_when_enemy_wake, carry.deliver_from_level])


func _test_kill_feedback() -> void:
	print("\n-- Kill marker and sound")
	var feedback := KillFeedback.new()
	add_child(feedback)
	feedback.bind(manager)
	_check("the kill sound exists and is flat (not positional)", KillFeedback.SOUND != null
		and not KillFeedback.SOUND.positional and KillFeedback.SOUND.pick_stream() != null, "")
	b1.health_component.apply_damage(DamageInfo.create(1e6, a1, DamageInfo.Type.TRUE))
	await _frames(2)
	_check("your kill shows ELIMINATED with the enemy's name and gold", feedback.kills_shown == 1
		and feedback.markers.size() == 1 and feedback.markers[0].text == "ELIMINATED"
		and feedback.markers[0].sub.contains(str(roundi(rules.kill_gold))), str(feedback.markers))
	await _wait_respawn(b1)
	b1.health_component.apply_damage(DamageInfo.create(1e6, a1, DamageInfo.Type.TRUE))
	await _frames(2)
	_check("a second kill in a row is a DOUBLE KILL", feedback.kills_shown == 2 and feedback.markers.back().text == "DOUBLE KILL",
		str(feedback.markers.back().text if not feedback.markers.is_empty() else "none"))
	await _wait_respawn(b1)
	var shown := feedback.kills_shown
	b1.health_component.apply_damage(DamageInfo.create(10.0, a1, DamageInfo.Type.TRUE))
	b1.health_component.apply_damage(DamageInfo.create(1e6, a2, DamageInfo.Type.TRUE))
	await _frames(2)
	_check("an assist gets its own small marker, not a kill", feedback.kills_shown == shown
		and feedback.markers.back().text == "ASSIST", str(feedback.markers.back().text))
	await _wait_respawn(b1)
	shown = feedback.kills_shown
	a2.health_component.apply_damage(DamageInfo.create(1e6, b1, DamageInfo.Type.TRUE))
	await _frames(2)
	_check("an ally's death shows nothing", feedback.kills_shown == shown and feedback.markers.back().text == "ASSIST", "")
	await get_tree().create_timer(feedback.KILL_TIME + 0.2, true, true).timeout
	_check("markers fade out", feedback.markers.is_empty(), str(feedback.markers.size()))
	feedback.queue_free()
	await _wait_respawn(a2)


func _test_mvp() -> void:
	print("\n-- MVP")
	var record_a1 := manager.get_record(a1)
	_check("damage dealt, damage taken and the best streak are tracked", record_a1.damage_dealt > 0.0
		and manager.get_record(b1).damage_taken > 0.0 and record_a1.best_streak >= 2, "%s / %s / %s" % [
			record_a1.damage_dealt, manager.get_record(b1).damage_taken, record_a1.best_streak])
	var healer_record := manager.get_record(a2)
	a1.health_component.current_health = 10.0
	a1.health_component.heal(50.0, a2)
	_check("healing an ally counts for the healer", healer_record.healing_done > 0.0, str(healer_record.healing_done))
	_check("the MVP score follows the rules' weights", is_equal_approx(rules.mvp_score(record_a1),
		record_a1.kills * rules.mvp_kill_weight + record_a1.assists * rules.mvp_assist_weight
		+ record_a1.deaths * rules.mvp_death_weight + record_a1.damage_dealt / 1000.0 * rules.mvp_damage_dealt_weight
		+ record_a1.damage_taken / 1000.0 * rules.mvp_damage_taken_weight
		+ record_a1.healing_done / 1000.0 * rules.mvp_healing_weight
		+ record_a1.motes_banked * rules.mvp_bank_weight + record_a1.motes_delivered * rules.mvp_deliver_weight
		+ record_a1.best_streak * rules.mvp_streak_weight), "")
	manager.end_match(&"a")
	var result: Dictionary = GameState.finish_match(manager, &"a")
	var mvps: Array = result.heroes.filter(func(r): return r.is_mvp)
	var aces: Array = result.heroes.filter(func(r): return r.is_ace)
	var top := -1e9
	for row in result.heroes:
		if row.team == &"a":
			top = maxf(top, row.mvp_score)
	_check("exactly one MVP, on the winning team, and it is the top scorer", mvps.size() == 1 and mvps[0].team == &"a"
		and is_equal_approx(mvps[0].mvp_score, top), str(mvps.size()))
	_check("exactly one ACE, on the losing team", aces.size() == 1 and aces[0].team == &"b", str(aces.size()))
	var complete := true
	for row in result.heroes:
		for key in ["damage_dealt", "damage_taken", "healing_done", "best_streak", "mvp_score"]:
			complete = complete and row.has(key)
	_check("the rows carry the new stats", complete, "")
	var screen := EndMatchScreen.new()
	add_child(screen)
	screen.show_result(result)
	await _frames(2)
	var labels := _labels(screen)
	_check("the end screen shows the MVP card and the scoreboard", screen.visible and _has_text(labels, "MVP")
		and _has_text(labels, "ACE") and labels.has("K / D / A") and labels.has("Damage"), str(labels.size()))
	_check("format_time reads m:ss", EndMatchScreen.format_time(125.0) == "2:05", EndMatchScreen.format_time(125.0))
	screen.queue_free()


func _test_shop_panel() -> void:
	print("\n-- Shop window")
	var panel := ShopPanel.new()
	add_child(panel)
	panel.bind(manager)
	panel.open()
	await _frames(2)
	var catalog := rules.shop_catalog
	var count := 0
	for family in catalog.get_family_order():
		count += catalog.get_items(family).size()
	_check("one card per catalog item", panel.buttons.size() == count and count > 0, "%d / %d" % [panel.buttons.size(), count])
	var first: Button = panel.buttons[panel.buttons.keys()[0]]
	var price := first.find_child("Price", true, false) as Label
	_check("each card shows a price", price != null and price.text.contains("gold"), price.text if price != null else "no label")
	var inventory := ItemInventory.find_on(a1)
	manager.grant_actor(a1, 5000.0, 0.0, &"test")
	panel._refresh()
	var item: ItemData = panel.buttons.keys()[0]
	panel._show_details(item)
	_check("hovering an item fills the details card", panel._detail_name.text.contains(item.display_name)
		and panel._detail_body.text == item.describe(), panel._detail_name.text)
	_check("buttons still report whether an item can be bought", inventory != null
		and panel.buttons[item].disabled == (inventory.get_buy_block_reason(item) != ""), "")
	panel.close()
	_check("closes", not panel.is_open(), "")
	panel.queue_free()


# --- Helpers ------------------------------------------------------------------

func _has_text(labels: PackedStringArray, part: String) -> bool:
	for text in labels:
		if text.contains(part):
			return true
	return false


func _labels(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _wait_respawn(hero: Hero) -> void:
	for i in 300:
		if not hero.health_component.is_dead():
			return
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
