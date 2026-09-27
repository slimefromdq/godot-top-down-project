extends Node2D

# Headless checks for the Dreamers: banking vs delivering rewards and the
# depositor bonus, highest value first, ticks speeding up, ticks stopping
# (leaving, a jostle), no deposits in transit, Sweet Dreams thresholds, the
# stir and its grace, a win from one Mote after the grace, the Lullaby
# (defenders, contested pause, banking), both reset percentages, both
# Dreamers stirring at once, faster defender respawns, the relayed signals
# and the HUD arrows.
#
#   godot --headless res://tools/match/dreamer_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DREAMER := "res://scenes/match/dreamer.tscn"
const AIRLOCK := "res://resources/minigames/airlock.tres"
const HOME_A := Vector2(0, 2000)
const HOME_B := Vector2(0, -2000)
const FAR := Vector2(4000, 0)

var failures := 0
var manager: MatchManager
var director: MoteDirector
var rules: MatchRules
var dreamer_a: Dreamer
var dreamer_b: Dreamer
var a1: Hero
var a2: Hero
var b1: Hero
var relayed: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.passive_xp_per_second = 0.0
	rules.trickle_interval = 1e6
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	rules.deposit_tick = 0.1
	rules.deposit_tick_speedup = 0.9
	rules.deposit_tick_min = 0.06
	rules.sweet_dreams_threshold = 10.0
	rules.stir_grace = 0.5
	rules.stir_duration = 2.0
	rules.respawn_base = 0.5
	rules.respawn_per_level = 0.0
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	director = manager.get_node("MoteDirector")
	director.reset_schedule()
	dreamer_a = _dreamer(&"a", HOME_A)
	dreamer_b = _dreamer(&"b", HOME_B)
	a1 = _hero(&"a", FAR)
	a2 = _hero(&"a", FAR + Vector2(300, 0))
	b1 = _hero(&"b", FAR + Vector2(0, 600))
	manager.wake_changed.connect(func(t, v): relayed.append(["wake", t, v]))
	manager.stir_started.connect(func(t): relayed.append(["stir", t]))
	manager.settled.connect(func(t, how): relayed.append(["settled", t, how]))
	manager.woke.connect(func(t): relayed.append(["woke", t]))
	await _frames(3)
	manager.start_warmup()
	await _frames(2)

	_test_setup()
	await _test_bank_and_deliver()
	await _test_highest_first_and_speedup()
	await _test_interruptions()
	await _test_no_deposit_in_transit()
	await _test_sweet_dreams()
	await _test_stir_and_grace()
	await _test_lullaby()
	await _test_resets_and_both_stirring()
	_test_arrows()
	await _test_win()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_setup() -> void:
	print("\n-- Setup")
	_check("both Dreamers registered with the manager", manager.get_dreamer(&"a") == dreamer_a
		and manager.get_dreamer(&"b") == dreamer_b, "")
	_check("a Dreamer's body blocks walking, not shots", dreamer_a.get_node("Body").collision_layer == MapLayers.LOW_COVER, "")
	_check("on the minimap in its team's colour", dreamer_a.is_in_group(&"minimap_objectives") and dreamer_a.team == &"a", "")


func _test_bank_and_deliver() -> void:
	print("\n-- Bank vs deliver")
	_zero_gold()
	_carry(a1, [1, 1, 1, 1])
	await _visit(a1, dreamer_a)
	var team_share := rules.bank_gold_per_value * 4 / 2.0
	var bonus := rules.bank_gold_per_value * 4 * rules.depositor_bonus_pct
	_check("banking pays the team, split evenly", _near(manager.get_gold(a2), team_share), str(manager.get_gold(a2)))
	_check("the depositor gets a bonus on top", _near(manager.get_gold(a1), team_share + bonus),
		"%.1f vs %.1f" % [manager.get_gold(a1), team_share + bonus])
	_check("banking fills Sweet Dreams, not a wake meter", _near(dreamer_a.sweet, 4.0) and dreamer_a.wake == 0.0
		and dreamer_b.wake == 0.0, "")
	_check("Dusk isn't paid for Dawn's bank", _near(manager.get_gold(b1), 0.0), "")
	dreamer_a.sweet = 0.0

	_zero_gold()
	_carry(a1, [1, 1, 1, 1])
	await _visit(a1, dreamer_b)
	var deliver_share := rules.deliver_gold_per_value * 4 / 2.0
	_check("delivering pays more than banking", _near(manager.get_gold(a2), deliver_share)
		and deliver_share > team_share, str(manager.get_gold(a2)))
	_check("delivering fills the enemy's wake meter", _near(dreamer_b.wake, 4.0), str(dreamer_b.wake))
	_check("wake_changed is relayed with the team", relayed.any(func(e): return e[0] == "wake" and e[1] == &"b"), "")
	dreamer_b.set_wake(0.0)


func _test_highest_first_and_speedup() -> void:
	print("\n-- Highest first, ticks speed up")
	var values: Array = []
	var times: Array = []
	var on_tick := func(_h, value, _d, _i):
		values.append(value)
		times.append(Time.get_ticks_msec())
	dreamer_a.deposit_ticked.connect(on_tick)
	var start := Time.get_ticks_msec()
	_carry(a1, [1, 5, 2, 1, 1, 1, 1, 1])
	a1.global_position = HOME_A + Vector2(0, -200)
	await _until(func(): return MoteCarrier.find_on(a1).get_mote_count() == 0, 5.0)
	a1.global_position = FAR
	dreamer_a.deposit_ticked.disconnect(on_tick)
	_check("highest value first", values.slice(0, 3) == [5, 2, 1], str(values))
	var first_gap: float = (times[0] - start) / 1000.0
	var last_gap: float = (times[-1] - times[-2]) / 1000.0
	_check("the first Mote goes in after deposit_tick", first_gap > rules.deposit_tick * 0.7 and first_gap < rules.deposit_tick * 2.5,
		"%.3f" % first_gap)
	_check("later ticks come faster", last_gap < first_gap, "%.3f -> %.3f" % [first_gap, last_gap])
	dreamer_a.sweet = 0.0


func _test_interruptions() -> void:
	print("\n-- Interruptions")
	var carrier := MoteCarrier.find_on(a1)
	_carry(a1, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	a1.global_position = HOME_B + Vector2(0, 200)
	await _until(func(): return carrier.get_mote_count() <= 7, 3.0)
	a1.global_position = FAR
	await _frames(2)
	var left := carrier.get_mote_count()
	var wake := dreamer_b.wake
	await _seconds(0.4)
	_check("leaving the ring stops the ticking", carrier.get_mote_count() == left and dreamer_b.wake == wake, "%d left" % left)
	_check("what went in stays in", _near(dreamer_b.wake, 10 - left), str(dreamer_b.wake))

	# A jostle mid-visit stops it too.
	a1.global_position = HOME_B + Vector2(0, 200)
	await _until(func(): return dreamer_b.is_depositing(a1), 1.0)
	var push := StatusEffect.new()
	push.id = &"test_push"
	push.duration = 0.05
	push.displace_distance = 150.0
	push.displace_duration = 0.4
	b1.global_position = a1.global_position + Vector2(200, 0)
	a1.status_component.apply(push, b1, Vector2.LEFT)
	await _frames(2)
	_check("a jostle stops the visit", not dreamer_b.is_depositing(a1), "")
	await _seconds(0.6)
	b1.global_position = FAR + Vector2(0, 600)
	a1.global_position = FAR
	carrier.clear()
	director.clear_motes()
	dreamer_b.set_wake(0.0)


func _test_no_deposit_in_transit() -> void:
	print("\n-- No deposits in transit")
	var carrier := MoteCarrier.find_on(a1)
	_carry(a1, [1, 1, 1])
	# Fly right across the ring (over the body), landing outside it.
	a1.global_position = HOME_A + Vector2(-420, -150)
	a1.launch(HOME_A + Vector2(420, -150), 0.8)
	await _until(func(): return not a1.is_airborne(), 2.0)
	_check("airborne across the ring: nothing goes in", carrier.get_mote_count() == 3, str(carrier.get_mote_count()))
	a1.global_position = FAR
	await _frames(2)
	a1.global_position = HOME_A + Vector2(0, -200)
	var host := MinigameHost.find_or_create(a1)
	host.play(AirlockMinigame.new(load(AIRLOCK)))
	await _seconds(0.4)
	_check("abducted (in a minigame): nothing goes in", carrier.get_mote_count() == 3, str(carrier.get_mote_count()))
	host.stop()
	a1.global_position = FAR
	await _frames(2)
	var ring := ContainmentRing.spawn(self, HOME_A + Vector2(0, -200), 150.0, 1.0, [a1])
	a1.global_position = HOME_A + Vector2(0, -200)
	await _seconds(0.4)
	_check("inside a ContainmentRing: nothing goes in", carrier.get_mote_count() == 3, str(carrier.get_mote_count()))
	ring.end()
	a1.global_position = FAR
	carrier.clear()
	await _frames(2)


func _test_sweet_dreams() -> void:
	print("\n-- Sweet Dreams")
	var grants: Array = []
	dreamer_a.sweet_dreams_granted.connect(func(): grants.append(1))
	dreamer_a.sweet = 0.0
	_carry(a1, [1, 1, 1, 1, 1, 1, 1, 1, 1])
	await _visit(a1, dreamer_a)
	_check("below the threshold: no buff", grants.is_empty() and _near(dreamer_a.sweet, 9.0), "")
	_carry(a1, [3])
	await _visit(a1, dreamer_a)
	var status := rules.sweet_dreams_status
	_check("every threshold: the whole team gets the buff", grants.size() == 1
		and a1.status_component.has_status(status.id) and a2.status_component.has_status(status.id)
		and not b1.status_component.has_status(status.id), "")
	_check("the meter resets after each threshold (keeps the extra)", _near(dreamer_a.sweet, 2.0), str(dreamer_a.sweet))
	_check("the buff lasts sweet_dreams_duration", absf(a2.status_component.get_time_left(status.id)
		- rules.sweet_dreams_duration) < 1.0, str(a2.status_component.get_time_left(status.id)))
	_check("it speeds you up and regenerates", status.stat_multipliers.get(StatusEffect.MOVE_SPEED, 1.0) > 1.0
		and status.tick_heal_ratio > 0.0, "")
	a1.status_component.clear()
	a2.status_component.clear()
	dreamer_a.sweet = 0.0


func _test_stir_and_grace() -> void:
	print("\n-- Stir and grace")
	var carrier := MoteCarrier.find_on(a1)
	dreamer_b.set_wake(rules.wake_meter_max - 2)
	_carry(a1, [1, 1, 1, 1, 1])
	a1.global_position = HOME_B + Vector2(0, 200)
	await _until(func(): return dreamer_b.is_stirring(), 2.0)
	_check("filling the meter starts a stir", dreamer_b.is_stirring() and relayed.any(func(e): return e == ["stir", &"b"]), "")
	_check("the filling deposit stops (the rest stays carried)", carrier.get_mote_count() == 3, str(carrier.get_mote_count()))
	_check("defenders respawn faster while it stirs", _near(manager.get_respawn_time(b1),
		rules.respawn_time(b1.get_level(), manager.clock) * rules.stir_defender_respawn_mult), "")
	await _seconds(rules.stir_grace * 0.6)
	_check("no deposits during the grace, even standing in the ring", carrier.get_mote_count() == 3
		and manager.state == MatchManager.State.PLAYING, "")
	a1.global_position = FAR
	carrier.clear()
	dreamer_b.settle(Dreamer.SETTLE_TIMEOUT)
	_check("settling restores the respawn time", _near(manager.get_respawn_time(b1),
		rules.respawn_time(b1.get_level(), manager.clock)), "")
	dreamer_b.set_wake(0.0)
	await _frames(2)


func _test_lullaby() -> void:
	print("\n-- Lullaby")
	dreamer_b.start_stir()
	b1.global_position = HOME_B + Vector2(400, 0)    # inside the Lullaby ring, outside the deposit ring
	await _seconds(0.5)
	var progress := dreamer_b.lullaby
	_check("a defender in the ring fills it (rate x defenders)", progress > 0.0
		and absf(progress - rules.lullaby_rate_per_defender * 0.5) < 0.01, "%.3f" % progress)
	a1.global_position = HOME_B + Vector2(-450, 0)
	await _frames(2)
	var paused_at := dreamer_b.lullaby
	await _seconds(0.3)
	_check("paused while an attacker is inside", _near(dreamer_b.lullaby, paused_at) and dreamer_b.is_lullaby_contested(), "")
	a1.global_position = FAR
	await _seconds(0.2)
	_check("resumes when they leave", dreamer_b.lullaby > paused_at, "")
	var before := dreamer_b.lullaby
	await _seconds(rules.stir_grace)
	_carry(b1, [5])
	await _visit(b1, dreamer_b)
	_check("banking at your own stirring Dreamer adds lullaby_per_banked_value",
		dreamer_b.lullaby >= before + 5 * rules.lullaby_per_banked_value, "%.3f -> %.3f" % [before, dreamer_b.lullaby])
	b1.global_position = FAR + Vector2(0, 600)
	dreamer_b.settle(Dreamer.SETTLE_TIMEOUT)
	dreamer_b.sweet = 0.0


func _test_resets_and_both_stirring() -> void:
	print("\n-- Resets, both at once")
	dreamer_a.start_stir()
	dreamer_b.start_stir()
	_check("both Dreamers can stir at once", dreamer_a.is_stirring() and dreamer_b.is_stirring(), "")
	dreamer_a.lullaby = 0.99
	dreamer_a._add_lullaby(0.02)
	_check("a full Lullaby settles it at lullaby_reset_pct", not dreamer_a.is_stirring()
		and _near(dreamer_a.wake, rules.wake_meter_max * rules.lullaby_reset_pct), str(dreamer_a.wake))
	_check("the other keeps stirring", dreamer_b.is_stirring(), "")
	await _seconds(rules.stir_duration + 0.2)
	_check("running out of time settles it at timeout_reset_pct", not dreamer_b.is_stirring()
		and _near(dreamer_b.wake, rules.wake_meter_max * rules.timeout_reset_pct), str(dreamer_b.wake))
	_check("settled(team, how) relayed for each", relayed.has(["settled", &"a", Dreamer.SETTLE_LULLABY])
		and relayed.has(["settled", &"b", Dreamer.SETTLE_TIMEOUT]), "")
	dreamer_a.set_wake(0.0)
	dreamer_b.set_wake(0.0)


func _test_arrows() -> void:
	print("\n-- HUD arrows")
	_check("no Dreamer arrows while carrying nothing", dreamer_a.offscreen_arrow_for(a1).is_empty()
		and dreamer_b.offscreen_arrow_for(a1).is_empty(), "")
	_carry(a1, [1])
	var own := dreamer_a.offscreen_arrow_for(a1)
	var enemy := dreamer_b.offscreen_arrow_for(a1)
	_check("while carrying: your own Dreamer's arrow is soft, the enemy's bold", not own.is_empty() and not enemy.is_empty()
		and own.scale < enemy.scale and own.color.a < enemy.color.a, "%s / %s" % [own, enemy])
	MoteCarrier.find_on(a1).clear()


func _test_win() -> void:
	print("\n-- The win")
	var winners: Array = []
	manager.match_ended.connect(func(t): winners.append(t))
	dreamer_b.set_wake(rules.wake_meter_max)
	_check("a full meter from anywhere stirs it", dreamer_b.is_stirring(), "")
	await _seconds(rules.stir_grace + 0.1)
	_carry(a1, [1])
	a1.global_position = HOME_B + Vector2(0, 200)
	await _until(func(): return manager.state == MatchManager.State.ENDED, 2.0)
	_check("one more Mote after the grace wakes it: attackers win", winners == [&"a"] and manager.winner == &"a", str(winners))
	_check("woke(team) relayed", relayed.has(["woke", &"b"]), "")


# --- Helpers --------------------------------------------------------------------------

func _build_map() -> void:
	var map := GameMap.new()
	map.name = "Map"
	for entry in [[&"spawn_a", Vector2(-3000, 3000)], [&"spawn_b", Vector2(3000, -3000)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	add_child(map)


func _dreamer(team: StringName, at: Vector2) -> Dreamer:
	var dreamer: Dreamer = load(DREAMER).instantiate()
	dreamer.team = team
	dreamer.position = at
	add_child(dreamer)
	return dreamer


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _carry(hero: Hero, values: Array) -> void:
	var carrier := MoteCarrier.find_on(hero)
	for v in values:
		carrier.add_mote(director.small_data, v)


# Stand in `dreamer`'s deposit ring until the stack is empty (or 3 s), then leave.
func _visit(hero: Hero, dreamer: Dreamer) -> void:
	var back := hero.global_position
	hero.global_position = dreamer.global_position + (Vector2(0, 200) if dreamer.team == &"b" else Vector2(0, -200))
	await _until(func(): return MoteCarrier.find_on(hero).get_mote_count() == 0, 3.0)
	hero.global_position = back
	await _frames(2)


func _until(condition: Callable, timeout: float) -> void:
	var t := 0.0
	while not condition.call() and t < timeout:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _zero_gold() -> void:
	for hero in manager.get_roster():
		manager.get_record(hero).gold = 0.0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
