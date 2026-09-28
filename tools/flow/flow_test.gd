extends Node

# Headless checks for the menus and match flow: the hero draft (bot picks,
# no duplicates on a team, role mix, lock conflicts, the timer's auto-lock,
# practice), the menu scenes loading, GameState launching Dream Basin with the
# picked hero and bots, the pause menu, and the end-of-match result.
#
#   godot --headless res://tools/flow/flow_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

var failures := 0


func _ready() -> void:
	# GameState changes scenes; keep this node out of the way of that by
	# making a stand-in the "current scene".
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in
	_run.call_deferred()


func _run() -> void:
	_test_draft()
	_test_lock_conflict()
	_test_timeout()
	_test_practice()
	await _test_menus()
	await _test_launch()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _config() -> MatchConfig:
	var config := GameState.new_config()
	config.hero_select_time = 30.0
	config.bot_pick_interval = 0.5
	config.start_delay = 1.0
	return config


func _run_draft(draft: HeroDraft, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not draft.is_done():
		draft.tick(0.1)
		t += 0.1


func _test_draft() -> void:
	print("\n-- Draft")
	var config := _config()
	var heroes := BotDraft.playable_definitions()
	_check("there are heroes to pick", heroes.size() >= 6, str(heroes.size()))
	var draft := HeroDraft.new(config, heroes)
	_check("6v6 by default: two teams of six", draft.teams.size() == 2
		and draft.teams[&"a"].size() == 6 and draft.teams[&"b"].size() == 6, "")
	_check("you're slot 1 of Dawn", draft.get_player_slot().is_player and draft.get_player_slot().team == &"a", "")
	draft.tick(0.6)
	var locked_bots := 0
	for team in draft.teams:
		for slot: HeroDraft.Slot in draft.teams[team]:
			locked_bots += 1 if slot.is_bot and slot.locked else 0
	_check("bots lock in one at a time", locked_bots == 1, str(locked_bots))
	draft.hover(heroes[2].hero_id)
	draft.lock_in()
	_check("lock in takes the hovered hero", draft.is_player_locked()
		and draft.get_player_slot().hero_id == heroes[2].hero_id, "")
	_run_draft(draft, 20.0)
	_check("every bot locks in, then the match starts", draft.all_locked() and draft.is_done(), "")
	var picks := draft.to_picks()
	_check("picks: six per team, you first", picks[&"a"].size() == 6 and picks[&"b"].size() == 6
		and picks[&"a"][0] == heroes[2].hero_id, str(picks))
	for team in picks:
		var unique := {}
		for id in picks[team]:
			unique[id] = true
		_check("no hero twice on %s" % MatchManager.team_name(team), unique.size() == picks[team].size(), str(picks[team]))
	var roles := {}
	for id in picks[&"b"]:
		roles[draft.find(id).role] = true
	_check("bots build a role mix", roles.size() >= 3, str(roles.keys()))

	config = _config()
	config.team_size = 3
	config.bot_fill = false
	draft = HeroDraft.new(config, heroes)
	draft.lock_in()
	_run_draft(draft, 5.0)
	picks = draft.to_picks()
	_check("no bot fill: only you", draft.is_done() and picks[&"a"].size() == 1 and picks[&"b"].is_empty(), str(picks))


func _test_lock_conflict() -> void:
	print("\n-- Lock conflicts")
	var heroes := BotDraft.playable_definitions()
	var draft := HeroDraft.new(_config(), heroes)
	_run_draft(draft, 10.0)
	var bot_pick: StringName = draft.teams[&"a"][1].hero_id
	_check("an ally bot avoids what you're hovering", bot_pick != draft.hovered and bot_pick != &"", str(bot_pick))
	_check("is_taken_by_ally", draft.is_taken_by_ally(bot_pick), "")
	draft.lock_in(bot_pick)
	var ids: Array = draft.to_picks()[&"a"]
	_check("you can take it; that bot picks again", ids[0] == bot_pick and ids.count(bot_pick) == 1
		and draft.teams[&"a"][1].hero_id != bot_pick, str(ids))


func _test_timeout() -> void:
	print("\n-- Timer")
	var config := _config()
	config.hero_select_time = 2.0
	var heroes := BotDraft.playable_definitions()
	var draft := HeroDraft.new(config, heroes)
	draft.hover(heroes[1].hero_id)
	_run_draft(draft, 2.05)
	_check("time out locks you into the hovered hero", draft.is_player_locked()
		and draft.get_player_slot().hero_id == heroes[1].hero_id, "")
	_check("...and every bot at once", draft.all_locked(), "")
	_run_draft(draft, 2.0)
	_check("then it starts", draft.is_done(), "")


func _test_practice() -> void:
	print("\n-- Practice")
	var config := _config()
	config.practice = true
	var draft := HeroDraft.new(config, BotDraft.playable_definitions())
	_check("practice: one team, one slot", draft.teams.size() == 1 and draft.teams[&"a"].size() == 1, "")
	draft.lock_in()
	_run_draft(draft, 2.0)
	_check("done after you lock in", draft.is_done(), "")


func _test_menus() -> void:
	print("\n-- Menu scenes")
	for path in [GameState.MAIN_MENU, GameState.MATCH_SETUP, GameState.HERO_SELECT]:
		get_tree().change_scene_to_file(path)
		await get_tree().scene_changed
		await get_tree().process_frame
		var scene := get_tree().current_scene
		_check("%s loads" % path.get_file(), scene != null and scene.scene_file_path == path
			and scene.get_child_count() > 1, "")
	_check("the main scene is the main menu",
		ProjectSettings.get_setting("application/run/main_scene") == GameState.MAIN_MENU, "")


func _test_launch() -> void:
	print("\n-- Launch")
	var config := _config()
	config.team_size = 3
	var heroes := BotDraft.playable_definitions()
	var draft := HeroDraft.new(config, heroes)
	draft.lock_in(heroes[3].hero_id)
	_run_draft(draft, 10.0)
	config.picks = draft.to_picks()
	GameState.config = config
	GameState.launch()
	await get_tree().scene_changed
	await get_tree().process_frame
	await get_tree().process_frame
	var manager := MatchManager.find(get_tree())
	var player := get_tree().get_first_node_in_group(&"player") as Hero
	_check("the match scene loads", manager != null and GameState.in_launched_game, "")
	_check("you play the hero you picked", player != null and player.definition != null
		and player.definition.hero_id == heroes[3].hero_id, str(player.definition.hero_id if player else ""))
	_check("rosters are 3v3 with the picked bots", manager.get_roster(&"a").size() == 3
		and manager.get_roster(&"b").size() == 3, "%d v %d" % [manager.get_roster(&"a").size(), manager.get_roster(&"b").size()])
	var bot_ids := manager.get_roster(&"b").map(func(h: Hero): return h.definition.hero_id)
	bot_ids.sort()
	var want: Array = config.picks[&"b"].duplicate()
	want.sort()
	_check("the enemy bots are the ones picked", bot_ids == want, str(bot_ids))

	var world := get_tree().current_scene
	var pause: PauseMenu = world.pause_menu
	pause.open()
	_check("the pause menu pauses", pause.is_open() and get_tree().paused, "")
	pause.close()
	_check("resume unpauses", not pause.is_open() and not get_tree().paused, "")

	# Credit the player a kill and a bank, then end the match.
	var record := manager.get_record(player)
	record.kills = 2
	record.deaths = 1
	manager._on_deposit_finished(player, 7, false)
	manager._on_deposit_finished(player, 3, true)
	var results: Array = []
	GameState.match_finished.connect(func(r): results.append(r), CONNECT_ONE_SHOT)
	manager.end_match(&"a")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("match_finished carries the result", results.size() == 1 and results[0].won and results[0].winner == &"a", "")
	var mine: Array = results[0].heroes.filter(func(r): return r.is_player) if not results.is_empty() else []
	_check("your K/D and Motes banked are in it", mine.size() == 1 and mine[0].kills == 2 and mine[0].deaths == 1
		and mine[0].motes_banked == 7 and mine[0].motes_delivered == 3, str(mine))
	_check("the end screen shows", world.end_screen.visible and get_tree().paused, "")
	_check("the pause menu is off after the end", not pause.enabled, "")
	GameState.leave_match()
	await get_tree().scene_changed
	await get_tree().process_frame
	_check("back to the menu (unpaused)", get_tree().current_scene.scene_file_path == GameState.MAIN_MENU
		and not get_tree().paused and not GameState.in_launched_game, "")


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
