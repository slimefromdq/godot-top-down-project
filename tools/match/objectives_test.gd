extends Node2D

# Headless checks for neutral objectives: every NeutralData is valid; the
# ObjectiveDirector's schedule (first spawn, respawn after a clear, the
# Nightmare only once, its warning, nothing during warmup or with
# objectives off); monster level from the heroes; a monster stays passive
# until hit, then fights back, and leashes (walks home, heals: reset_heal_fraction,
# full by default);
# rewards (killer and team gold/XP, ultimate charge, a pack pays per
# monster); claimed Motes (only the killer's team, until the claim runs
# out); the Nightmare's team buff (dead heroes get the rest on respawn);
# Dream Basin's camps; and the debug controls (spawn jungle, the Nightmare
# now / its warning, clear).
#
#   godot --headless res://tools/match/objectives_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const NIGHTMARE := "res://resources/match/neutrals/nightmare.tres"
const SLEEPWALKER := "res://resources/match/neutrals/sleepwalker.tres"
const WISPS := "res://resources/match/neutrals/dream_wisps.tres"
const DREAM_BASIN := "res://scenes/maps/dream_basin.tscn"

var failures := 0
var manager: MatchManager
var director: ObjectiveDirector
var rules: MatchRules
var map: GameMap
var jungle: NeutralCamp
var pack: NeutralCamp
var lair: NeutralCamp
var a1: Hero
var a2: Hero
var b1: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.passive_xp_per_second = 0.0
	rules.ult_charge_per_second = 0.0
	rules.trickle_interval = 1000.0
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	director = manager.get_node("ObjectiveDirector")
	a1 = _hero(&"a", Vector2(0, 2000))
	a2 = _hero(&"a", Vector2(-300, 2000))
	b1 = _hero(&"b", Vector2(0, -2000))
	await _frames(3)

	_test_data()
	await _test_schedule()
	await _test_fight_and_leash()
	await _test_rewards()
	await _test_pack()
	await _test_claimed_motes()
	await _test_nightmare()
	await _test_dream_basin_camps()
	await _test_debug_controls()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_data() -> void:
	print("\n-- Data")
	for path in [NIGHTMARE, SLEEPWALKER, WISPS]:
		var data: NeutralData = load(path)
		_check("%s is valid" % data.id, data.validate().is_empty(), str(data.validate()))
	var nightmare: NeutralData = load(NIGHTMARE)
	var sleepwalker: NeutralData = load(SLEEPWALKER)
	_check("the Nightmare spawns once, mid/late game", nightmare.respawn_time == 0.0
		and nightmare.first_spawn_time >= 480.0 and nightmare.first_spawn_time < rules.late_match_time + 300.0,
		"at %.0f s" % nightmare.first_spawn_time)
	_check("the Nightmare is announced", nightmare.announce and nightmare.warning_time > 0.0, "")
	_check("the Nightmare pays many Motes", nightmare.mote_count * nightmare.mote_value >= 50,
		"%d x %d" % [nightmare.mote_count, nightmare.mote_value])
	_check("the Nightmare buffs the team", nightmare.team_status != null, "")
	_check("jungle camps come back", sleepwalker.respawn_time > 0.0, "")
	_check("jungle camps pay a little", sleepwalker.mote_count * sleepwalker.mote_value < 10
		and sleepwalker.killer_xp > 0.0, "")


func _test_schedule() -> void:
	print("\n-- Schedule")
	manager.start_warmup()
	rules.warmup_time = 5.0
	manager.start_warmup()
	manager.clock = 1e6
	await _frames(3)
	_check("nothing spawns during warmup", not jungle.is_alive() and not lair.is_alive(), "")
	manager.start_playing()
	manager.clock = 0.0
	director.reset_schedule()
	rules.objectives_enabled = false
	manager.clock = 1e5
	await _frames(2)
	_check("objectives_enabled off: nothing spawns", not jungle.is_alive(), "")
	rules.objectives_enabled = true
	manager.clock = 0.0
	director.reset_schedule()
	await _frames(2)
	_check("not before first_spawn_time", not jungle.is_alive(), "")
	manager.clock = jungle.data.first_spawn_time
	await _frames(2)
	_check("the jungle camp spawns on time", jungle.is_alive() and jungle.get_living_monsters().size() == 1, "")
	var monster := jungle.get_living_monsters()[0]
	_check("monsters are on the neutral team", monster.team == NeutralMonster.TEAM, "")
	_check("level follows the heroes' average", monster.level == jungle.data.get_level(director.get_average_level()),
		"%d" % monster.level)
	var warned: Array = []
	director.objective_warning.connect(func(camp, seconds): warned.append([camp, seconds]))
	manager.clock = lair.data.first_spawn_time - lair.data.warning_time + 0.1
	await _frames(2)
	_check("the Nightmare is announced warning_time early", warned.size() == 1 and warned[0][0] == lair
		and lair.state == NeutralCamp.CampState.WARNING, str(warned))
	_check("but isn't up yet", not lair.is_alive(), "")
	manager.clock = lair.data.first_spawn_time
	await _frames(2)
	_check("the Nightmare awakens", lair.is_alive(), "")
	lair.despawn()
	lair.state = NeutralCamp.CampState.WAITING
	lair.next_spawn_time = INF


func _test_fight_and_leash() -> void:
	print("\n-- Fighting and leashing")
	var monster := jungle.get_living_monsters()[0]
	var home := monster.home
	a1.global_position = home + Vector2(400, 0)
	await _frames(40)
	_check("passive until hit", not monster.is_fighting() and a1.health_component.current_health == a1.health_component.max_health, "")
	_hit(monster, a1, 100.0)
	_check("hit: it fights the attacker", monster.is_fighting() and monster.target == a1, "")
	var hp := a1.health_component.current_health
	await _frames(120)
	_check("it shoots back", a1.health_component.current_health < hp,
		"%.0f -> %.0f" % [hp, a1.health_component.current_health])
	_hit(monster, a1, 200.0)
	var hurt := monster.health_component.current_health
	a1.global_position = home + Vector2(monster.data.leash_radius + 200.0, 0)
	await _frames(3)
	_check("the attacker leaves the leash: it gives up", not monster.is_fighting(), "")
	_check("...and heals to full", monster.health_component.current_health > hurt
		and is_equal_approx(monster.health_component.current_health, monster.health_component.max_health), "")
	_hit(monster, b1, 10.0)
	b1.global_position = home + Vector2(300, 0)
	_check("any hero can pull it", monster.target == b1, "")
	var reset_frames := int((monster.data.reset_time + 0.5) * Engine.physics_ticks_per_second)
	b1.health_component.god_mode = true
	await _frames(reset_frames)
	_check("nobody hitting it for reset_time: it gives up", not monster.is_fighting(), "")
	b1.health_component.god_mode = false
	b1.global_position = Vector2(0, -2000)
	a1.global_position = Vector2(0, 2000)
	a1.health_component.reset()
	b1.health_component.reset()


func _test_rewards() -> void:
	print("\n-- Rewards")
	var monster := jungle.get_living_monsters()[0]
	var data := jungle.data
	var gold1 := manager.get_gold(a1)
	var gold2 := manager.get_gold(a2)
	var goldb := manager.get_gold(b1)
	var xp1 := manager.get_record(a1).total_xp
	var charge := manager.get_ultimate_ratio(a1)
	var cleared: Array = []
	director.objective_cleared.connect(func(camp, team, killer): cleared.append([camp, team, killer]), CONNECT_ONE_SHOT)
	_kill(monster, a1)
	await _frames(2)
	var team_share := data.team_gold / 2.0
	_check("killer gets killer + team share of gold", is_equal_approx(manager.get_gold(a1) - gold1, data.killer_gold + team_share),
		"%.1f" % (manager.get_gold(a1) - gold1))
	_check("teammate gets the team share", is_equal_approx(manager.get_gold(a2) - gold2, team_share), "")
	_check("the enemy gets nothing", is_equal_approx(manager.get_gold(b1), goldb), "")
	_check("killer gets XP", manager.get_record(a1).total_xp - xp1 >= data.killer_xp, "")
	_check("killer gets ultimate charge", manager.get_ultimate_ratio(a1) > charge, "")
	_check("cleared, credited to Dawn", cleared.size() == 1 and cleared[0][1] == &"a" and cleared[0][2] == a1, str(cleared))
	var motes := _motes_near(monster.global_position, 400.0)
	_check("Motes burst out (%d)" % data.mote_count, motes.size() == data.mote_count, str(motes.size()))
	_check("the camp waits to respawn", jungle.state == NeutralCamp.CampState.WAITING
		and absf(jungle.next_spawn_time - (manager.clock + data.respawn_time)) < 0.2, "")
	for mote in motes:
		mote.queue_free()
	manager.clock = jungle.next_spawn_time
	await _frames(2)
	_check("and comes back after respawn_time", jungle.is_alive(), "")


func _test_pack() -> void:
	print("\n-- Packs")
	director.spawn_camp(pack)
	await _frames(1)
	var wisps := pack.get_living_monsters()
	_check("a pack spawns data.count monsters", wisps.size() == pack.data.count, str(wisps.size()))
	var gold := manager.get_gold(b1)
	var cleared: Array = []
	director.objective_cleared.connect(func(camp, team, killer): cleared.append(camp), CONNECT_ONE_SHOT)
	_kill(wisps[0], b1)
	await _frames(1)
	_check("one down: not cleared yet", cleared.is_empty() and pack.is_alive(), "")
	for wisp in wisps.slice(1):
		_kill(wisp, b1)
	await _frames(1)
	_check("all down: cleared", cleared == [pack], "")
	_check("each monster paid", is_equal_approx(manager.get_gold(b1) - gold,
		pack.data.count * (pack.data.killer_gold + pack.data.team_gold)), "%.1f" % (manager.get_gold(b1) - gold))
	for mote in _motes_near(pack.global_position, 800.0):
		mote.queue_free()


func _test_claimed_motes() -> void:
	print("\n-- Claimed Motes")
	var data: NeutralData = load(SLEEPWALKER)
	var at := Vector2(2500, 0)
	var motes := director.burst_motes(at, data, &"b")
	await _frames(30)
	_check("the burst lands", motes.size() == data.mote_count and motes.all(func(m): return not m.is_landing()), "")
	var mote: Mote = motes[0]
	a1.global_position = mote.global_position
	await _frames(20)
	_check("the other team can't take a claimed Mote", is_instance_valid(mote) and not mote.is_queued_for_deletion()
		and MoteCarrier.find_on(a1).get_mote_count() == 0, "")
	mote.claim_left = 0.0
	await _frames(30)
	_check("once the claim runs out they can", not is_instance_valid(mote) or mote.is_queued_for_deletion()
		or MoteCarrier.find_on(a1).get_mote_count() > 0, "")
	b1.global_position = motes[1].global_position
	await _frames(30)
	_check("the claiming team can take theirs", MoteCarrier.find_on(b1).get_mote_count() > 0, "")
	MoteCarrier.find_on(a1).clear()
	MoteCarrier.find_on(b1).clear()
	for m in _motes_near(at, 800.0):
		m.queue_free()
	a1.global_position = Vector2(0, 2000)
	b1.global_position = Vector2(0, -2000)


func _test_nightmare() -> void:
	print("\n-- The Nightmare")
	director.spawn_camp(lair)
	await _frames(1)
	var boss: NeutralMonster = lair.get_living_monsters()[0]
	_check("it's big and tough", boss.health_component.max_health >= 5000.0, "%.0f HP" % boss.health_component.max_health)
	_hit(boss, b1, 10.0)
	b1.global_position = boss.global_position + Vector2(600, 0)
	b1.health_component.god_mode = true
	var fired := 0
	for i in int(lair.data.ring_interval * Engine.physics_ticks_per_second) + 10:
		await get_tree().physics_frame
		fired = maxi(fired, get_tree().get_nodes_in_group(&"bot_projectiles").size())
	_check("it fights with volleys and a ring", fired >= lair.data.ring_count, "%d bolts in flight" % fired)
	var worn := boss.health_component.current_health
	b1.global_position = boss.global_position + Vector2(lair.data.leash_radius + 200.0, 0)
	await _frames(3)
	_check("it doesn't heal when it gives up (reset_heal_fraction 0)", not boss.is_fighting()
		and is_equal_approx(boss.health_component.current_health, worn)
		and worn < boss.health_component.max_health, "%.0f / %.0f" % [boss.health_component.current_health, worn])
	b1.health_component.god_mode = false
	a2.health_component.kill()
	await _frames(1)
	var gold := manager.get_gold(a1)
	var status := lair.data.team_status
	_kill(boss, a1)
	await _frames(2)
	_check("a big team payout", manager.get_gold(a1) - gold >= lair.data.killer_gold + lair.data.team_gold / 2.0 - 0.1, "")
	_check("living teammates get the buff", a1.status_component.has_status(status.id), "")
	_check("the enemy doesn't", not b1.status_component.has_status(status.id), "")
	_check("the buff lasts team_status_duration", absf(a1.status_component.get_time_left(status.id)
		- lair.data.team_status_duration) < 0.2, "%.1f" % a1.status_component.get_time_left(status.id))
	var motes := _motes_near(boss.global_position, 800.0)
	var value := 0
	for mote in motes:
		value += mote.value
	_check("a large number of Motes (value %d)" % value, motes.size() == lair.data.mote_count
		and value >= lair.data.mote_count * lair.data.mote_value, "")
	_check("claimed by the killing team", motes.all(func(m): return m.claim_team == &"a" and m.claim_left > 0.0), "")
	_check("gone for good", lair.state == NeutralCamp.CampState.GONE and lair.next_spawn_time == INF, "")
	manager.clock += 10000.0
	await _frames(2)
	_check("never comes back", not lair.is_alive(), "")
	manager.clock -= 10000.0
	manager.clock += 20.0
	manager.respawn_now(a2)
	await _frames(1)
	_check("a teammate dead at the kill gets the rest of it on respawn", a2.status_component.has_status(status.id)
		and absf(a2.status_component.get_time_left(status.id) - (lair.data.team_status_duration - 20.0)) < 0.5,
		"%.1f" % a2.status_component.get_time_left(status.id))
	for mote in motes:
		if is_instance_valid(mote):
			mote.queue_free()


func _test_dream_basin_camps() -> void:
	print("\n-- Dream Basin")
	var basin: Node = load(DREAM_BASIN).instantiate()
	var camps: Array = basin.find_children("*", "Node2D", true, false).filter(func(n): return n is NeutralCamp)
	var nightmares := camps.filter(func(c): return c.data.id == &"nightmare")
	_check("one Nightmare lair, in the middle", nightmares.size() == 1 and nightmares[0].position == Vector2.ZERO, "")
	var jungle_camps := camps.filter(func(c): return c.data.id != &"nightmare")
	_check("jungle camps all over the map (%d)" % jungle_camps.size(), jungle_camps.size() >= 8, "")
	var mirrored := jungle_camps.all(func(c): return jungle_camps.any(
		func(o): return o.position.distance_to(-c.position) < 1.0 and o.data == c.data))
	_check("jungle camps are mirrored", mirrored, "")
	basin.free()


func _test_debug_controls() -> void:
	print("\n-- Debug controls")
	director.despawn_all()
	await _frames(1)
	_check("clear: nothing up", not jungle.is_alive() and not pack.is_alive() and not lair.is_alive(), "")
	director.force_spawn_all(true)
	_check("spawn jungle camps: jungle up, no Nightmare", jungle.is_alive() and pack.is_alive() and not lair.is_alive(), "")
	var warned: Array = []
	director.objective_warning.connect(func(camp, _s): warned.append(camp), CONNECT_ONE_SHOT)
	director.force_warning()
	_check("Nightmare warning: announced now", warned == [lair] and lair.state == NeutralCamp.CampState.WARNING, "")
	director.force_spawn_announced()
	_check("Nightmare now: up (even after it was slain)", lair.is_alive(), "")
	director.despawn_all()
	await _frames(1)
	# (The Nightmare slain by the test before may still be fading out.)
	var left := get_tree().get_nodes_in_group(NeutralMonster.GROUP).filter(
		func(m): return not m.is_queued_for_deletion() and not m.health_component.is_dead())
	_check("clear again", not lair.is_alive() and left.is_empty(), "%s %s" % [lair.state, left])


# --- Helpers -----------------------------------------------------------------

func _build_map() -> void:
	map = GameMap.new()
	map.name = "Map"
	map.bounds = Rect2(-4000, -4000, 8000, 8000)
	for entry in [[&"spawn_a", Vector2(0, 2000)], [&"spawn_b", Vector2(0, -2000)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	jungle = _camp(SLEEPWALKER, Vector2(-2500, 0))
	pack = _camp(WISPS, Vector2(2500, 1500))
	lair = _camp(NIGHTMARE, Vector2(0, 0))
	add_child(map)


func _camp(path: String, at: Vector2) -> NeutralCamp:
	var camp := NeutralCamp.new()
	camp.data = load(path)
	camp.position = at
	map.add_child(camp)
	return camp


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _hit(monster: NeutralMonster, from: Hero, amount: float) -> void:
	monster.health_component.apply_damage(DamageInfo.create(amount, from, DamageInfo.Type.TRUE))


func _kill(monster: NeutralMonster, by: Hero) -> void:
	_hit(monster, by, monster.health_component.current_health + 1.0)


func _motes_near(at: Vector2, radius: float) -> Array[Mote]:
	var result: Array[Mote] = []
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote != null and not mote.is_queued_for_deletion() and mote.global_position.distance_to(at) <= radius:
			result.append(mote)
	return result


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
