extends Node2D

# Headless checks for the match layer: MatchManager states, the roster, team
# splits, leveling and its cap, passive income, kill and assist rewards,
# respawns, and the debug panel's Match actions.
#
#   godot --headless res://tools/match/match_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const OTHER_DEFINITION := "res://heroes/jose/jose_definition.tres"
const SPAWN_A := Vector2(0, 2000)
const SPAWN_B := Vector2(0, -2000)

var failures := 0
var manager: MatchManager
var rules: MatchRules
var a1: Hero
var a2: Hero
var b1: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.5
	rules.passive_gold_per_second = 10.0
	rules.passive_xp_per_second = 0.0
	rules.passive_tick_interval = 0.25
	rules.assist_window = 0.6
	rules.respawn_base = 0.4
	rules.respawn_per_level = 0.0
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	a1 = _hero(&"a", Vector2(-200, 0))
	a2 = _hero(&"a", Vector2(200, 0))
	b1 = _hero(&"b", Vector2(0, -300))
	await _physics_frames(3)

	_test_basics()
	await _test_states()
	_test_team_split()
	_test_leveling()
	await _test_passive()
	await _test_kill_and_assist()
	await _test_respawn()
	await _test_debug_actions()
	_test_end_match()
	await _test_sandbox_match()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_basics() -> void:
	print("\n-- Rules and roster")
	var def_rules := MatchRules.current()
	_check("match_rules.tres loads with cue profiles", def_rules.cue_visuals != null and def_rules.cue_audio != null
		and def_rules.cue_visuals.cues.has(&"level_up") and def_rules.cue_audio.cues.has(&"level_up"), "")
	_check("XP curve: 300 to reach L2, 6300 in total to reach L10",
		_near(def_rules.xp_to_next_level(1), 300.0) and _near(def_rules.total_xp_for_level(10), 6300.0),
		str(def_rules.total_xp_for_level(10)))
	_check("found through the match_manager group", MatchManager.find(get_tree()) == manager, "")
	_check("roster: 2 Dawn, 1 Dusk", manager.get_roster(&"a").size() == 2 and manager.get_roster(&"b").size() == 1,
		"%d / %d" % [manager.get_roster(&"a").size(), manager.get_roster(&"b").size()])
	_check("roster heroes respawn instead of freeing", a1.respawns and b1.respawns, "")


func _test_states() -> void:
	print("\n-- States")
	var seen: Array = []
	manager.state_changed.connect(func(s): seen.append(s))
	manager.start_warmup()
	_check("warmup first", manager.state == MatchManager.State.WARMUP, "")
	manager.grant_actor(a1, 0.0, 0.0, &"test")
	await _physics_frames(10)
	_check("no passive income during warmup", manager.get_gold(a1) == 0.0, str(manager.get_gold(a1)))
	await get_tree().create_timer(0.6, true, true).timeout
	_check("warmup -> playing after warmup_time", manager.state == MatchManager.State.PLAYING, str(manager.state))
	_check("state_changed for each step", seen == [MatchManager.State.WARMUP, MatchManager.State.PLAYING], str(seen))
	_check("clock runs while playing", manager.clock > 0.0, str(manager.clock))


func _test_team_split() -> void:
	print("\n-- Team split")
	_zero_gold()
	manager.grant_team(&"a", 100.0, 0.0, &"test")
	_check("100 gold split across 2 Dawn heroes", _near(manager.get_gold(a1), 50.0) and _near(manager.get_gold(a2), 50.0),
		"%.1f / %.1f" % [manager.get_gold(a1), manager.get_gold(a2)])
	_check("Dusk gets nothing", _near(manager.get_gold(b1), 0.0), str(manager.get_gold(b1)))
	var events: Array = []
	var on_gold := func(actor, amount, reason): events.append([actor, amount, reason])
	manager.gold_changed.connect(on_gold)
	manager.grant_actor(b1, 30.0, 0.0, &"bonus")
	manager.gold_changed.disconnect(on_gold)
	_check("grant_actor pays one hero and says why", _near(manager.get_gold(b1), 30.0)
		and events.size() == 1 and events[0][0] == b1 and events[0][2] == &"bonus", str(events))


func _test_leveling() -> void:
	print("\n-- Leveling")
	var levels: Array = []
	var on_level := func(actor, level): if actor == a2: levels.append(level)
	manager.level_up.connect(on_level)
	var start := a2.get_level()
	# L1->2 300, L2->3 400, L3->4 500: 1200 gets to L4, plus 50 spare.
	manager.add_xp(a2, 1250.0, &"test")
	_check("1250 XP from L1 reaches L4", start == 1 and a2.get_level() == 4, "L%d" % a2.get_level())
	_check("level-up signal per level", levels == [2, 3, 4], str(levels))
	_check("50 XP left toward L5", _near(manager.get_xp(a2), 50.0), str(manager.get_xp(a2)))
	_check("stats follow the level", _near(a2.stats_component.get_health(),
		a2.stats_component.stat_block.value_at(StatBlock.HEALTH, 4)), "")
	manager.add_xp(a2, 1000000.0, &"test")
	var cap := GameRules.current().max_level
	_check("capped at GameRules.max_level (%d)" % cap, a2.get_level() == cap and manager.is_max_level(a2), "L%d" % a2.get_level())
	_check("XP at the cap stays one bar full", manager.get_xp(a2) <= rules.xp_to_next_level(cap) + 0.01, str(manager.get_xp(a2)))
	manager.level_up.disconnect(on_level)


func _test_passive() -> void:
	print("\n-- Passive income")
	_zero_gold()
	await get_tree().create_timer(1.0, true, true).timeout
	# 10 gold/s in 0.25 s chunks: ~1 s is 3-5 chunks depending on frame alignment.
	var gold := manager.get_gold(b1)
	_check("~10 gold per second to every hero", gold >= 7.4 and gold <= 12.6, str(gold))
	_check("paid to both teams alike", _near(manager.get_gold(a1), gold) and _near(manager.get_gold(a2), gold),
		"%s %s" % [manager.get_gold(a1), manager.get_gold(a2)])
	rules.passive_gold_per_second = 0.0


func _test_kill_and_assist() -> void:
	print("\n-- Kills and assists")
	_zero_gold()
	var killed: Array = []
	var on_kill := func(victim, killer, assisters): killed.append([victim, killer, assisters])
	manager.hero_killed.connect(on_kill)
	# a2 chips b1, a1 kills: a1 kill, a2 assist.
	b1.health_component.apply_damage(DamageInfo.create(10.0, a2, DamageInfo.Type.TRUE))
	b1.health_component.apply_damage(DamageInfo.create(1e6, a1, DamageInfo.Type.TRUE))
	await _physics_frames(1)
	_check("killer paid kill gold", _near(manager.get_gold(a1), rules.kill_gold), str(manager.get_gold(a1)))
	_check("assister paid assist gold", _near(manager.get_gold(a2), rules.assist_gold), str(manager.get_gold(a2)))
	_check("victim paid nothing", _near(manager.get_gold(b1), 0.0), str(manager.get_gold(b1)))
	_check("hero_killed(victim, killer, [assister])", killed.size() == 1 and killed[0][0] == b1
		and killed[0][1] == a1 and killed[0][2] == [a2], str(killed))
	_check("kill/assist/death counted", manager.get_record(a1).kills == 1 and manager.get_record(a2).assists == 1
		and manager.get_record(b1).deaths == 1, "")
	_check("dead hero stays in the tree, hidden", is_instance_valid(b1) and b1.is_inside_tree() and not b1.visible, "")
	await _wait_respawn(b1)

	# Old damage falls out of the assist window.
	_zero_gold()
	b1.health_component.apply_damage(DamageInfo.create(10.0, a2, DamageInfo.Type.TRUE))
	await get_tree().create_timer(rules.assist_window + 0.2, true, true).timeout
	b1.health_component.apply_damage(DamageInfo.create(1e6, a1, DamageInfo.Type.TRUE))
	_check("damage older than assist_window earns no assist", _near(manager.get_gold(a2), 0.0), str(manager.get_gold(a2)))
	await _wait_respawn(b1)

	# A teammate's hit is never kill credit; a death with no enemy hero pays nobody.
	_zero_gold()
	b1.health_component.apply_damage(DamageInfo.create(1e6, null, DamageInfo.Type.TRUE))
	_check("no enemy hero behind the kill: nobody paid", _near(manager.get_gold(a1), 0.0)
		and _near(manager.get_gold(a2), 0.0) and killed.back()[1] == null, "")
	manager.hero_killed.disconnect(on_kill)
	await _wait_respawn(b1)


func _test_respawn() -> void:
	print("\n-- Respawn")
	b1.global_position = Vector2(500, 500)
	b1.status_component.apply(load("res://resources/status/shocked.tres"), a1)
	b1.health_component.kill(a1)
	_check("respawn timer set", manager.get_respawn_left(b1) > 0.0, str(manager.get_respawn_left(b1)))
	await get_tree().create_timer(rules.respawn_base * 0.5, true, true).timeout
	_check("still dead halfway", b1.health_component.is_dead(), "")
	await get_tree().create_timer(rules.respawn_base, true, true).timeout
	_check("alive after respawn time", not b1.health_component.is_dead() and b1.visible, "")
	_check("full health", _near(b1.health_component.current_health, b1.health_component.max_health), "")
	_check("at their team's spawn", b1.global_position.distance_to(SPAWN_B) < 1.0, str(b1.global_position))
	_check("statuses cleared", b1.status_component.get_active_effects().is_empty(), "")
	_check("hittable again", b1.collision_layer != 0, str(b1.collision_layer))

	manager.set_respawn_multiplier(&"b", 0.5)
	_check("respawn multiplier scales the time", _near(manager.get_respawn_time(b1), rules.respawn_time(b1.get_level()) * 0.5), "")
	manager.set_respawn_multiplier(&"b", 1.0)


func _test_debug_actions() -> void:
	print("\n-- Debug panel (F1 > Match)")
	var player: Hero = load(HERO).instantiate()
	player.team = &"a"
	player.player_controlled = true
	player.name = "Player"
	add_child(player)
	await _physics_frames(2)
	_check("player joins the roster", manager.has_hero(player), "")
	DebugTools.give_player(123.0, 0.0)
	_check("Give gold", _near(manager.get_gold(player), 123.0), str(manager.get_gold(player)))
	DebugTools.set_player_match_level(5)
	_check("Set level", player.get_level() == 5, str(player.get_level()))
	var swapped := DebugTools.swap_player(load(OTHER_DEFINITION))
	await _physics_frames(2)
	_check("Play as keeps gold and level", swapped != null and manager.has_hero(swapped)
		and _near(manager.get_gold(swapped), 123.0) and swapped.get_level() == 5,
		"%s L%d" % [manager.get_gold(swapped), swapped.get_level()] if swapped else "no hero")
	DebugTools.set_player_team(&"b")
	_check("Play as team: now Dusk", swapped.team == &"b" and manager.get_roster(&"b").has(swapped), "")
	_check("Play as team: moved to Dusk's spawn", swapped.global_position.distance_to(SPAWN_B) < 1.0, str(swapped.global_position))
	DebugTools.set_player_team(&"a")
	swapped.health_component.kill()
	await _physics_frames(1)
	_check("player waits to respawn (no game over)", swapped.is_inside_tree() and manager.get_respawn_left(swapped) > 0.0
		and not get_tree().paused, "")
	manager.respawn_now(swapped)
	_check("Respawn now", not swapped.health_component.is_dead(), "")


func _test_end_match() -> void:
	print("\n-- End")
	var winners: Array = []
	manager.match_ended.connect(func(team): winners.append(team))
	var gold := manager.get_gold(a1)
	manager.end_match(&"b")
	_check("ENDED with the winner", manager.state == MatchManager.State.ENDED and manager.winner == &"b", "")
	_check("match_ended(winner) once", winners == [&"b"], str(winners))
	manager.end_match(&"a")
	_check("a second end_match is ignored", manager.winner == &"b" and winners.size() == 1, "")
	manager.grant_actor(a1, 100.0, 100.0, &"test")
	_check("no rewards after the end", _near(manager.get_gold(a1), gold), "")
	_check("victory title names the team", MatchManager.team_name(&"b") == "Dusk" and MatchManager.team_name(&"a") == "Dawn", "")


func _test_sandbox_match() -> void:
	print("\n-- Start a match in a sandbox (Training Grounds)")
	# Changing scenes frees the current scene: hand that role to a throwaway
	# node first so this test survives.
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	get_tree().change_scene_to_file("res://scenes/training_grounds_world.tscn")
	await _physics_frames(3)
	_check("Training Grounds has no match of its own", get_tree().get_nodes_in_group(MatchManager.GROUP).size() == 1, "")
	manager.queue_free()
	await _physics_frames(1)
	var sandbox := DebugTools.start_match_here()
	await _physics_frames(2)
	_check("Start a match here adds a manager with the player", sandbox != null
		and sandbox.has_hero(DebugTools.get_player()), "")
	sandbox.end_match(&"a")
	_check("its end shows the victory screen (tree paused)", get_tree().paused, "")
	get_tree().paused = false


# --- Helpers --------------------------------------------------------------------------

func _build_map() -> void:
	var map := GameMap.new()
	map.name = "Map"
	for team in [&"a", &"b"]:
		var marker := Marker2D.new()
		marker.position = SPAWN_A if team == &"a" else SPAWN_B
		marker.add_to_group(StringName("spawn_%s" % team))
		map.add_child(marker)
	add_child(map)


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _wait_respawn(hero: Hero) -> void:
	for i in 200:
		if not hero.health_component.is_dead():
			return
		await get_tree().physics_frame


func _zero_gold() -> void:
	for hero in manager.get_roster():
		manager.get_record(hero).gold = 0.0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
