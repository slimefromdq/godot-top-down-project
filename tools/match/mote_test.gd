extends Node2D

# Headless checks for Motes: pickup and the carry cap, the regrab lockout,
# decoys, fading, the death burst, Jostle (pushes, pulls, carries,
# abductions, friendly pushes, short pushes, immunity, the count rule), heavy
# pockets, can_deposit, reveal steps and minimap fog, the MoteDirector's
# trickle, mirrored dreaming zones, Dream Mote uniqueness and the late-match
# multiplier, and Dream Basin's markers.
#
#   godot --headless res://tools/match/mote_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const PAD := "res://scenes/map/jump_pad.tscn"
const MINIMAP := "res://scenes/hud/minimap.tscn"
const AIRLOCK := "res://resources/minigames/airlock.tres"
const DREAM_BASIN := "res://scenes/maps/dream_basin.tscn"

var failures := 0
var manager: MatchManager
var director: MoteDirector
var rules: MatchRules
var map: GameMap
var a1: Hero
var a2: Hero
var b1: Hero
var pings: Array = []


# Stands in for the minimap in "minimaps" (records pings).
class PingCatcher extends Node:
	var log: Array
	func add_ping(position: Vector2, team: StringName, kind: StringName = &"") -> void:
		log.append([position, team, kind])


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.passive_xp_per_second = 0.0
	# Director timings pushed out of the way; each test sets what it needs.
	rules.trickle_interval = 1000.0
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	director = manager.get_node("MoteDirector")
	director.reset_schedule()
	var catcher := PingCatcher.new()
	catcher.log = pings
	catcher.add_to_group(&"minimaps")
	add_child(catcher)
	a1 = _hero(&"a", Vector2(0, 0))
	a2 = _hero(&"a", Vector2(-2000, 0))
	b1 = _hero(&"b", Vector2(2000, 0))
	await _frames(3)
	manager.start_warmup()
	await _frames(2)

	_test_basics()
	await _test_pickup_and_cap()
	await _test_lockout_decoy_fade()
	await _test_death_burst()
	await _test_jostle()
	await _test_heavy_pockets()
	await _test_can_deposit()
	await _test_reveal()
	await _test_minimap_fog()
	await _test_trickle()
	await _test_zones()
	await _test_dream_mote()
	_test_late_match()
	await _test_dream_basin_markers()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_basics() -> void:
	print("\n-- Setup")
	_check("every hero has a MoteCarrier", MoteCarrier.find_on(a1) != null and MoteCarrier.find_on(b1) != null, "")
	_check("the MatchManager made a MoteDirector", director != null and MoteDirector.find(get_tree()) == director, "")
	_check("MoteData: small worth 1, Dream Mote worth 5", director.small_data.value == 1
		and director.dream_data.value == 5 and director.dream_data.is_dream, "")
	_check("playing", manager.is_playing(), "")


func _test_pickup_and_cap() -> void:
	print("\n-- Pickup and the cap")
	var carrier := MoteCarrier.find_on(a1)
	var mote := director.spawn_mote(a1.global_position + Vector2(80, 0))
	var got: Array = []
	mote.picked_up.connect(func(h): got.append(h))
	await _frames(20)
	_check("a nearby Mote is pulled in and attaches", carrier.get_mote_count() == 1 and got == [a1],
		str(carrier.get_mote_count()))
	_check("get_mote_count / get_mote_value", carrier.get_mote_count() == 1 and carrier.get_mote_value() == 1, "")
	for i in 7:
		carrier.add_mote(director.small_data, 1)
	_check("capped at max_carried (5)", carrier.get_mote_count() == 5, str(carrier.get_mote_count()))
	var extra := director.spawn_mote(a1.global_position + Vector2(60, 0))
	await _frames(20)
	_check("a full carrier doesn't pull in more", is_instance_valid(extra) and carrier.get_mote_count() == 5, "")
	extra.queue_free()
	carrier.clear()
	await _frames(1)


func _test_lockout_decoy_fade() -> void:
	print("\n-- Regrab lockout, decoys, fading")
	var carrier := MoteCarrier.find_on(a1)
	carrier.add_mote(director.small_data, 1)
	var dropped := carrier.drop_one(70.0)
	await _frames(40)
	_check("its last carrier can't grab it back at once", is_instance_valid(dropped) and carrier.get_mote_count() == 0, "")
	# An ally walks up: anyone else can.
	a2.global_position = dropped.global_position + Vector2(40, 0)
	await _frames(20)
	_check("anyone else can", MoteCarrier.find_on(a2).get_mote_count() == 1, "")
	MoteCarrier.find_on(a2).clear()
	a2.global_position = Vector2(-2000, 0)

	var decoy := director.spawn_mote(a1.global_position + Vector2(60, 0))
	decoy.is_decoy = true
	await _frames(20)
	_check("a decoy pops on pickup and adds nothing", not is_instance_valid(decoy) and carrier.get_mote_count() == 0, "")

	var fast: MoteData = director.small_data.duplicate()
	fast.fade_time = 0.3
	fast.blink_time = 0.2
	var dropped_mote := Mote.spawn(self, fast, Vector2(900, 900), 1, true)
	var spawned_mote := Mote.spawn(self, fast, Vector2(1100, 900), 1, false)
	await _seconds(0.2)
	_check("a dropped Mote is in its blink window before fading", dropped_mote.data.fade_time - dropped_mote.age < fast.blink_time, "")
	await _seconds(0.3)
	_check("a dropped Mote fades after fade_time", not is_instance_valid(dropped_mote), "")
	_check("a spawned Mote doesn't fade", is_instance_valid(spawned_mote), "")
	spawned_mote.queue_free()


func _test_death_burst() -> void:
	print("\n-- Death burst")
	var carrier := MoteCarrier.find_on(a1)
	a1.global_position = Vector2(0, 0)
	for i in 3:
		carrier.add_mote(director.small_data, 1)
	carrier.add_mote(director.dream_data, 5)
	var events: Array = []
	carrier.dropped.connect(func(p, n): events.append(n), CONNECT_ONE_SHOT)
	a1.health_component.kill(b1)
	await _frames(2)
	var loose := director.get_loose_motes(true)
	_check("every Mote bursts out", carrier.get_mote_count() == 0 and loose.size() == 4 and events == [4],
		"%d loose" % loose.size())
	var ring_ok := true
	for m in loose:
		var d: float = m._to.distance_to(Vector2.ZERO)
		ring_ok = ring_ok and m.dropped and d > rules.burst_radius * 0.5 and d < rules.burst_radius * 1.3
	_check("scattered in a ring around the body", ring_ok, "")
	_check("the values come with them", loose.map(func(m): return m.value).reduce(func(s, v): return s + v, 0) == 8, "")
	director.clear_motes()
	manager.respawn_now(a1)
	a1.global_position = Vector2(0, 0)
	await _frames(2)


func _test_jostle() -> void:
	print("\n-- Jostle")
	var carrier := MoteCarrier.find_on(a1)
	var push := _push_status(200.0)
	b1.global_position = a1.global_position + Vector2(300, 0)

	_fill(carrier, 3)
	a1.status_component.apply(push, b1, Vector2.LEFT)
	_check("pending while still being pushed", carrier.is_jostle_pending() and carrier.get_mote_count() == 3, "")
	await _frames(20)
	var loose := director.get_loose_motes()
	_check("an enemy push drops one Mote where they land", carrier.get_mote_count() == 2 and loose.size() == 1
		and loose[0].dropped and loose[0].last_carrier == a1, "%d carried, %d loose" % [carrier.get_mote_count(), loose.size()])
	director.clear_motes()

	_fill(carrier, 2)
	a1.status_component.apply(push, a2, Vector2.LEFT)
	await _frames(20)
	_check("an ally's push doesn't", carrier.get_mote_count() == 2, "")

	a1.status_component.apply(_push_status(50.0), b1, Vector2.LEFT)
	await _frames(20)
	_check("a push shorter than jostle_min_distance doesn't", carrier.get_mote_count() == 2, "")

	var iron := StatusEffect.new()
	iron.id = &"test_iron_will"
	iron.duration = 2.0
	iron.stat_multipliers = {StatusEffect.DISPLACEMENT_TAKEN: 0.0}
	a1.status_component.apply(iron, a1)
	a1.status_component.apply(push, b1, Vector2.LEFT)
	var carry := StatusEffect.new()
	carry.id = &"test_carry"
	carry.duration = 0.2
	carry.carry_enabled = true
	a1.status_component.apply(carry, b1)
	await _frames(30)
	_check("can't-be-displaced immunity blocks Jostle (push and carry)", carrier.get_mote_count() == 2, "")
	a1.status_component.remove(&"test_iron_will")

	a1.status_component.apply(carry, b1)
	_check("a carry starts a Jostle", carrier.is_jostle_pending(), "")
	await _seconds(0.1)
	_check("...that waits until the carry ends", carrier.get_mote_count() == 2, "")
	await _seconds(0.25)
	_check("...then drops one", carrier.get_mote_count() == 1, str(carrier.get_mote_count()))
	director.clear_motes()

	_fill(carrier, 2)
	var host := MinigameHost.find_or_create(a1)
	host.play(AirlockMinigame.new(load(AIRLOCK)), b1)
	await _frames(3)
	host.stop()
	await _frames(5)
	_check("an abduction (a sourced minigame) jostles when it ends", carrier.get_mote_count() == 1, str(carrier.get_mote_count()))
	var practice := MinigameHost.find_or_create(a1)
	practice.play(AirlockMinigame.new(load(AIRLOCK)))
	await _frames(3)
	practice.stop()
	await _frames(5)
	_check("a practice minigame (no source) doesn't", carrier.get_mote_count() == 1, "")
	director.clear_motes()

	rules.jostle_displacements_required = 2
	_fill(carrier, 2)
	a1.status_component.apply(push, b1, Vector2.LEFT)
	await _frames(20)
	_check("jostle_displacements_required 2: one push isn't enough", carrier.get_mote_count() == 2, "")
	a1.status_component.apply(push, b1, Vector2.RIGHT)
	await _frames(20)
	_check("...the second is", carrier.get_mote_count() == 1, str(carrier.get_mote_count()))
	rules.jostle_displacements_required = 1
	carrier.clear()
	director.clear_motes()
	b1.global_position = Vector2(2000, 0)


func _test_heavy_pockets() -> void:
	print("\n-- Heavy pockets")
	var carrier := MoteCarrier.find_on(a1)
	var pad: JumpPad = load(PAD).instantiate()
	pad.position = Vector2(0, 600)
	pad.landing_offset = Vector2(500, 0)
	add_child(pad)
	await _frames(2)
	var plain := await _flight_time(pad)
	_fill(carrier, 3)
	_check("extra_air_time = 0.1 s per Mote", is_equal_approx(MoteCarrier.extra_air_time(a1), 0.3), "")
	var heavy := await _flight_time(pad)
	_check("a jump pad flight is 0.3 s longer with 3 Motes", absf(heavy - plain - 0.3) < 0.06,
		"%.2f -> %.2f" % [plain, heavy])
	carrier.clear()
	pad.queue_free()


func _flight_time(pad: JumpPad) -> float:
	a1.global_position = pad.global_position + Vector2(0, 300)
	await _frames(2)
	var start := Time.get_ticks_msec()
	a1.global_position = pad.global_position
	a1.velocity = Vector2.ZERO
	for i in 20:
		await get_tree().physics_frame
		if a1.is_airborne():
			break
	var frames := 0
	while a1.is_airborne() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	return frames / float(Engine.physics_ticks_per_second)


func _test_can_deposit() -> void:
	print("\n-- can_deposit")
	var carrier := MoteCarrier.find_on(a1)
	a1.global_position = Vector2(0, 0)
	await _frames(2)
	_check("standing: yes", carrier.can_deposit(), "")
	a1.launch(Vector2(300, 0), 0.4)
	_check("airborne: no", not carrier.can_deposit(), "")
	await _seconds(0.5)
	var host := MinigameHost.find_or_create(a1)
	host.play(AirlockMinigame.new(load(AIRLOCK)))
	await _frames(2)
	_check("abducted (in a minigame): no", not carrier.can_deposit(), "")
	host.stop()
	await _frames(2)
	var ring := ContainmentRing.spawn(self, a1.global_position, 300.0, 2.0, [a1])
	await _frames(2)
	_check("inside a ContainmentRing: no", not carrier.can_deposit(), "")
	ring.end()
	await _frames(2)
	_check("free again: yes", carrier.can_deposit(), "")
	var ready_events: Array = []
	carrier.deposit_ready.connect(func(): ready_events.append(1))
	_fill(carrier, 1)
	await _frames(2)
	_check("deposit_ready once carrying and able", ready_events.size() == 1, str(ready_events.size()))
	carrier.clear()


func _test_reveal() -> void:
	print("\n-- Reveal steps")
	var carrier := MoteCarrier.find_on(a1)
	_fill(carrier, 3)
	_check("value 3: hidden", carrier.get_reveal_interval() < 0.0, str(carrier.get_reveal_interval()))
	_fill(carrier, 1)
	_check("value 4: pings every 6 s", is_equal_approx(carrier.get_reveal_interval(), 6.0), "")
	carrier.clear()
	carrier.add_mote(director.small_data, 2)
	carrier.add_mote(director.small_data, 5)
	_check("value 7: pings every 3 s", is_equal_approx(carrier.get_reveal_interval(), 3.0), "")
	pings.clear()
	await _frames(3)
	_check("pings the ENEMY team's minimap", pings.size() >= 1 and pings[0][1] == &"b", str(pings))
	carrier.add_mote(director.small_data, 3)
	await _frames(2)
	_check("value 10: always shown (minimap_revealed)", carrier.get_reveal_interval() == 0.0
		and a1.is_in_group(MoteCarrier.REVEALED_GROUP), "")
	carrier.clear()
	await _frames(2)
	_check("empty: not revealed", not a1.is_in_group(MoteCarrier.REVEALED_GROUP), "")
	carrier.add_mote(director.dream_data, 5)
	_check("carrying a Dream Mote: always shown", carrier.get_reveal_interval() == 0.0, "")
	carrier.clear()


func _test_minimap_fog() -> void:
	print("\n-- Minimap fog")
	a1.add_to_group(&"player")
	var minimap: Minimap = load(MINIMAP).instantiate()
	add_child(minimap)
	await _frames(3)
	b1.global_position = a1.global_position + Vector2(5000, 0)
	var far_mote := director.spawn_mote(a1.global_position + Vector2(0, 5000))
	var dream := director.spawn_mote(a1.global_position + Vector2(0, -5000), true)
	minimap._refresh_fog()
	_check("an enemy nobody on your team can see is hidden", not minimap.is_shown(b1), "")
	_check("an ally is always shown", minimap.is_shown(a2), "")
	_check("a far small Mote is hidden", not minimap.is_shown(far_mote), "")
	_check("the Dream Mote is always shown", minimap.is_shown(dream), "")
	b1.global_position = a1.global_position + Vector2(600, 0)
	minimap._refresh_fog()
	_check("an enemy in sight is shown", minimap.is_shown(b1), "")
	b1.global_position = a1.global_position + Vector2(5000, 0)
	b1.add_to_group(MoteCarrier.REVEALED_GROUP)
	minimap._refresh_fog()
	_check("a revealed carrier is shown anywhere", minimap.is_shown(b1), "")
	b1.remove_from_group(MoteCarrier.REVEALED_GROUP)
	minimap.add_ping(Vector2(100, 100), &"a")
	minimap.add_ping(Vector2(100, 100), &"b")
	_check("pings are kept for their team", minimap.get_pings().size() == 2, "")
	minimap.queue_free()
	a1.remove_from_group(&"player")
	far_mote.queue_free()
	dream.queue_free()
	b1.global_position = Vector2(2000, 0)
	await _frames(2)


func _test_trickle() -> void:
	print("\n-- Trickle")
	director.clear_motes()
	await _frames(1)
	# The test map has two trickle points: one next to a1 (seen), one far away.
	var seen_point := get_tree().get_nodes_in_group(&"mote_spawn")[0] as Node2D
	var hidden_point := get_tree().get_nodes_in_group(&"mote_spawn")[1] as Node2D
	_check("a point near a hero is 'seen'", director.is_point_seen(seen_point) and not director.is_point_seen(hidden_point), "")
	_check("unseen points are preferred", director.pick_trickle_point() == hidden_point, "")
	rules.trickle_interval = 0.1
	rules.max_loose_motes = 2
	director.reset_schedule()
	await _seconds(0.6)
	_check("trickle spawns up to max_loose_motes", director.get_loose_motes().size() == 2,
		str(director.get_loose_motes().size()))
	_check("never two on one point", director.pick_trickle_point() == null, "")
	rules.trickle_interval = 1000.0
	director.reset_schedule()
	director.clear_motes()
	await _frames(1)


func _test_zones() -> void:
	print("\n-- Dreaming zones")
	var warnings: Array = []
	var starts: Array = []
	var ends: Array = []
	director.zone_warning.connect(func(id, _n, _s): warnings.append(id))
	director.zone_started.connect(func(id, _n): starts.append(id))
	director.zone_ended.connect(func(id, _n): ends.append(id))
	rules.zone_warning = 0.2
	rules.zone_duration = 0.5
	rules.zone_spawn_interval = 0.1
	rules.zone_max_per_half = 2
	rules.zone_interval = 0.8
	rules.zone_first_time = manager.clock + 0.3
	director.reset_schedule()
	await _seconds(0.2)
	var pair := director.get_active_pair()
	var halves: Array = director.get_zone_pairs()[pair]
	_check("warned first, both halves at once", warnings.size() == 1 and halves.size() == 2
		and halves.all(func(z): return z.zone_state == DreamZone.ZoneState.WARNING), str(warnings))
	await _seconds(0.4)
	_check("then both halves dream together", starts == [pair]
		and halves.all(func(z): return z.zone_state == DreamZone.ZoneState.DREAMING), str(starts))
	var per_half := halves.map(func(z): return director.get_loose_motes().filter(func(m): return m.origin == z).size())
	_check("each half spawns, up to zone_max_per_half", per_half == [2, 2], str(per_half))
	await _seconds(0.3)
	_check("then both end", ends == [pair] and halves.all(func(z): return z.zone_state == DreamZone.ZoneState.OFF), "")
	for i in 3:
		await _seconds(0.9)
	var repeats := 0
	for i in range(1, warnings.size()):
		if warnings[i] == warnings[i - 1]:
			repeats += 1
	_check("never the same pair twice in a row", warnings.size() >= 3 and repeats == 0, str(warnings))
	rules.zone_first_time = 1e6
	rules.zone_interval = 1e6
	await _seconds(0.8)
	director.reset_schedule()
	director.clear_motes()


func _test_dream_mote() -> void:
	print("\n-- Dream Mote")
	var warned: Array = []
	var spawned: Array = []
	var picked: Array = []
	director.dream_mote_warning.connect(func(_p, s): warned.append(s))
	director.dream_mote_spawned.connect(func(m): spawned.append(m))
	director.dream_mote_picked_up.connect(func(h): picked.append(h))
	rules.dream_mote_warning = 0.2
	rules.dream_mote_interval = 0.3
	rules.dream_mote_first_time = manager.clock + 0.3
	director.reset_schedule()
	await _seconds(0.15)
	_check("announced dream_mote_warning early", warned.size() == 1 and spawned.is_empty(), str(warned))
	await _seconds(0.25)
	_check("spawns at the Dream Mote spot", spawned.size() == 1
		and spawned[0].global_position.distance_to(director.get_dream_point()) < 1.0, "")
	await _seconds(0.5)
	_check("only one at a time", spawned.size() == 1 and director.get_loose_motes(true).size() == 1, "")
	var dream: Mote = spawned[0]
	a1.global_position = dream.global_position + Vector2(50, 0)
	await _frames(20)
	_check("picking it up is announced", picked == [a1] and MoteCarrier.find_on(a1).has_dream_mote(), "")
	await _seconds(0.5)
	_check("none while it's carried", spawned.size() == 1, "")
	# It drops (a death), then fades: the timer restarts from then.
	var fast: MoteData = director.dream_data.duplicate()
	fast.fade_time = 0.2
	MoteCarrier.find_on(a1).clear()
	Mote.spawn(self, fast, Vector2(3000, 3000), 5, true)
	await _frames(2)
	await _seconds(0.35)
	_check("after it fades, none until the interval passes", spawned.size() == 1, str(spawned.size()))
	await _seconds(0.4)
	_check("then the next one comes", spawned.size() == 2, str(spawned.size()))
	rules.dream_mote_first_time = 1e6
	rules.dream_mote_interval = 1e6
	director.clear_motes()
	await _frames(2)
	director.reset_schedule()
	a1.global_position = Vector2.ZERO


func _test_late_match() -> void:
	print("\n-- Late match")
	var early := director.spawn_mote(Vector2(3000, -3000))
	var saved := manager.clock
	manager.clock = rules.late_match_time + 1.0
	var late := director.spawn_mote(Vector2(3000, -3200))
	var late_dream := director.spawn_mote(Vector2(3000, -3400), true)
	_check("values x%.0f after late_match_time" % rules.late_match_value_mult,
		early.value == 1 and late.value == 2 and late_dream.value == 10,
		"%d %d %d" % [early.value, late.value, late_dream.value])
	manager.clock = saved
	director.clear_motes()


func _test_dream_basin_markers() -> void:
	print("\n-- Dream Basin markers")
	var basin: Node2D = load(DREAM_BASIN).instantiate()
	basin.name = "DreamBasinCheck"
	# Check the scene's own data without adding it (its groups would mix in).
	var spawns: Array[Vector2] = []
	var zones := {}
	var dream_spots := 0
	for node in basin.find_children("*", "", true, false):
		if node.is_in_group(&"mote_spawn"):
			spawns.append((node as Node2D).position)
		if node.is_in_group(&"dream_mote_spawn"):
			dream_spots += 1
		if node is DreamZone:
			if not zones.has(node.pair_id):
				zones[node.pair_id] = []
			zones[node.pair_id].append(node)
	_check("24 trickle points", spawns.size() == 24, str(spawns.size()))
	_check("every trickle point is 180-degree mirrored", _all_mirrored(spawns, spawns), "")
	_check("6 zone pairs, two halves each", zones.size() == 6 and zones.values().all(func(z): return z.size() == 2),
		str(zones.keys()))
	var mirrored := true
	for pair in zones:
		var a: PackedVector2Array = _zone_polygon(zones[pair][0])
		var b: PackedVector2Array = _zone_polygon(zones[pair][1])
		mirrored = mirrored and a.size() == b.size() and _all_mirrored(Array(a), Array(b))
	_check("each pair's halves are 180-degree mirrored", mirrored, "")
	_check("one Dream Mote spot", dream_spots == 1, "")
	basin.free()
	await _frames(1)


# Every point of `points` has its 180-degree twin in `others`.
func _all_mirrored(points: Array, others: Array) -> bool:
	for p in points:
		var found := false
		for q in others:
			if (q as Vector2).distance_to(-(p as Vector2)) < 1.0:
				found = true
		if not found:
			return false
	return true


func _zone_polygon(zone: DreamZone) -> PackedVector2Array:
	for child in zone.get_children():
		if child is CollisionPolygon2D:
			return child.polygon
	return PackedVector2Array()


# --- Helpers --------------------------------------------------------------------------

func _build_map() -> void:
	map = GameMap.new()
	map.name = "Map"
	for entry in [[&"spawn_a", Vector2(0, 2000)], [&"spawn_b", Vector2(0, -2000)],
			[&"mote_spawn", Vector2(150, 0)], [&"mote_spawn", Vector2(-3000, 3000)],
			[&"dream_mote_spawn", Vector2(-1000, -1000)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	# Two mirrored pairs of dreaming zones, far from everyone.
	for pair in [[&"north", Vector2(0, -3500)], [&"east", Vector2(3500, 0)]]:
		for sign in [1.0, -1.0]:
			var zone := DreamZone.new()
			zone.pair_id = pair[0]
			zone.display_name = str(pair[0])
			var shape := CollisionPolygon2D.new()
			var c: Vector2 = pair[1] * sign
			shape.polygon = PackedVector2Array([c + Vector2(-300, -300), c + Vector2(300, -300),
				c + Vector2(300, 300), c + Vector2(-300, 300)])
			zone.add_child(shape)
			for offset in [Vector2(-150, 0), Vector2(150, 0), Vector2(0, 150)]:
				var point := Marker2D.new()
				point.position = c + offset
				zone.add_child(point)
			map.add_child(zone)
	add_child(map)


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _push_status(distance: float) -> StatusEffect:
	var push := StatusEffect.new()
	push.id = StringName("test_push_%d" % distance)
	push.duration = 0.05
	push.displace_distance = distance
	push.displace_duration = 0.15
	return push


func _fill(carrier: MoteCarrier, n: int) -> void:
	for i in n:
		carrier.add_mote(director.small_data, 1)


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
