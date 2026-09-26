extends Node2D

# Headless checks for Cpt. Yellow's kit and the shared pieces it added
# (MovementComponent cruise, StatusEffect carry, SelfStatusAbility,
# RideAbility, ChargeAbility arrival release).
#
#   godot --headless res://tools/heroes/cpt_yellow_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const YELLOW := "res://heroes/cpt_yellow/cpt_yellow_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var yellow: Hero
var cues: Array = []
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	yellow = _spawn_yellow(1)
	await _physics_frames(3)
	_test_assembled()
	await _test_stinger_volley()
	await _test_swarm_ride()
	await _test_swarm_ride_interrupted()
	await _test_rally()
	await _test_sting()
	await _test_charge()
	await _test_bug_army()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate"]:
		_check("slot %s filled" % slot, yellow.get_ability(slot) != null, "")
	_check("definition validates", yellow.definition.validate().is_empty(), "\n".join(yellow.definition.validate()))
	_check("name, title and role", yellow.definition.display_name == "Cpt. Yellow"
		and yellow.definition.title == "Yellow Army" and yellow.definition.get_role_name() == "Tank", "")
	var found := HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"cpt_yellow")
	_check("listed in hero selection (F1 > Play as)", found, "")
	var stats := yellow.definition.stats
	var avery: HeroDefinition = load("res://heroes/avery/avery_definition.tres")
	_check("more base HP and HP growth than Avery",
		stats.health.base > avery.stats.health.base and stats.health.growth > avery.stats.health.growth, "")
	_check("primary and Sting are the generic gun (data only)",
		yellow.get_ability(&"primary").get_script() == RangedAttackAbility
		and yellow.get_ability(&"cc").get_script() == RangedAttackAbility, "")
	_check("CHARGE! is the generic ChargeAbility (data only)", yellow.get_ability(&"ultimate").get_script() == ChargeAbility, "")
	_check("Swarm Ride / Rally are the shared RideAbility / SelfStatusAbility",
		yellow.get_ability(&"ability_1") is RideAbility and yellow.get_ability(&"movement") is SelfStatusAbility, "")


# --- Stinger Volley ---------------------------------------------------------------

func _test_stinger_volley() -> void:
	_reset(Vector2(0, 0), 1)
	var near := _dummy(Vector2(250, 0))
	var far := _dummy(Vector2(900, 0))
	await _physics_frames(2)
	hits_log.clear()
	cues.clear()
	_aim(Vector2(250, 0))
	for i in 12:
		yellow.request_slot(&"primary", Vector2(250, 0))
		await get_tree().physics_frame
	await _seconds(0.5)
	var shots := _cue_count(&"stinger_volley_fire")
	_check("holding fires", shots >= 1, "%d" % shots)
	_check("each volley is 4 bugs", _sum_count(near, &"stinger") >= 3, "%d hits" % _sum_count(near, &"stinger"))
	_check("short range: nothing reaches 900 px", _sum_count(far, &"stinger") == 0, "")
	_check("no ammo to manage", not yellow.get_ranged_ability().has_magazine(), "")
	_clear()


# --- Swarm Ride -------------------------------------------------------------------

func _test_swarm_ride() -> void:
	_reset(Vector2(0, 3000), 1)
	var ride: RideAbility = yellow.get_ability(&"ability_1")
	var start := yellow.global_position
	_aim(start + Vector2(500, 0))
	cues.clear()
	yellow.request_slot(&"ability_1", yellow.aim_point)
	await _seconds(0.5)
	_check("holding rides", ride.is_riding() and yellow.movement_component.is_cruising(), "")
	var ridden := yellow.global_position.x - start.x
	_check("...forward at high speed (well above walking)", ridden > yellow.movement_component.move_speed * 0.5 * 1.3,
		"%.0f px in 0.5 s" % ridden)
	_check("cooldown not spent while riding", ride.is_ready(), "")
	# Steer: movement input turns the ride.
	yellow.move_direction = Vector2.DOWN
	var y_before := yellow.global_position.y
	await _seconds(0.5)
	yellow.move_direction = Vector2.ZERO
	_check("steering with movement turns the ride", yellow.global_position.y - y_before > 150.0,
		"%.0f px down" % (yellow.global_position.y - y_before))
	# Land next to two dummies: they get the telegraph, then the burst.
	var at := yellow.global_position
	var a := _dummy(at + Vector2(150, 0))
	var b := _dummy(at + Vector2(-100, 120))
	var outside := _dummy(at + Vector2(700, 0))
	for d in [a, b, outside]:
		d.return_to_anchor = false
	await _physics_frames(1)
	hits_log.clear()
	cues.clear()
	yellow.release_slot(&"ability_1", yellow.aim_point)
	await _physics_frames(2)
	_check("release ends the ride and starts the telegraph", not ride.is_riding()
		and ride.phase == Ability.Phase.WINDUP and _cue_count(&"swarm_ride_windup") == 1, "")
	var tele: Array = _cue_contexts(&"swarm_ride_windup")
	_check("...telegraph carries its radius and 0.25 s duration", not tele.is_empty()
		and is_equal_approx(tele[0].radius, 260.0) and is_equal_approx(tele[0].duration, 0.25), str(tele))
	_check("...no damage during the telegraph", hits_log.is_empty(), "")
	_check("cooldown starts at the end of the ride", not ride.is_ready(), "")
	var a_before := a.global_position
	await _seconds(0.3)
	_check("burst hits everyone nearby", _sum_count(a, &"swarm_landing") == 1 and _sum_count(b, &"swarm_landing") == 1, "")
	_check("...not beyond the radius", _sum_count(outside, &"swarm_landing") == 0, "")
	await _seconds(0.3)
	var pushed := a.global_position.distance_to(at) - a_before.distance_to(at)
	_check("...and knocks them outward", pushed > 200.0, "%.0f px" % pushed)
	_clear()

	# Max duration: lands by itself after 3 s.
	_reset(Vector2(0, 5000), 1)
	_aim(yellow.global_position + Vector2(500, 0))
	cues.clear()
	yellow.request_slot(&"ability_1", yellow.aim_point)
	await _seconds(2.9)
	_check("still riding at 2.9 s", ride.is_riding(), "")
	await _seconds(0.25)
	_check("lands by itself after max duration", not ride.is_riding() and _cue_count(&"swarm_ride_windup") == 1, "")
	await _seconds(0.6)


func _test_swarm_ride_interrupted() -> void:
	_reset(Vector2(0, 7000), 1)
	var ride: RideAbility = yellow.get_ability(&"ability_1")
	_aim(yellow.global_position + Vector2(500, 0))
	cues.clear()
	yellow.request_slot(&"ability_1", yellow.aim_point)
	await _seconds(0.3)
	yellow.status_component.apply(_status(&"test_stun", "stuns"), null)
	await _physics_frames(2)
	_check("a stun ends the ride without landing", not ride.is_riding() and not ride.is_casting()
		and _cue_count(&"swarm_ride_windup") == 0, "")
	_check("...still costs the cooldown", not ride.is_ready(), "")
	_check("...and the cruise is released", not yellow.movement_component.is_cruising(), "")
	await _seconds(0.3)


# --- Rally ------------------------------------------------------------------------

func _test_rally() -> void:
	_reset(Vector2(0, 9000), 1)
	var rally: SelfStatusAbility = yellow.get_ability(&"movement")
	cues.clear()
	yellow.request_slot(&"movement", yellow.global_position)
	await _seconds(0.2)
	var alone := yellow.status_component.get_shield_total()
	_check("Rally shields him alone", alone > 100.0 and rally.last_enemy_count == 0, "%.0f" % alone)
	await _seconds(2.1)
	_check("...for about 2 s", yellow.status_component.get_shield_total() == 0.0, "")

	_reset(Vector2(0, 9000), 1)
	for i in 3:
		_dummy(yellow.global_position + Vector2.from_angle(i * 2.0) * 250.0)
	_dummy(yellow.global_position + Vector2(1200, 0))    # too far to count
	await _physics_frames(2)
	yellow.request_slot(&"movement", yellow.global_position)
	await _seconds(0.2)
	var crowded := yellow.status_component.get_shield_total()
	_check("3 enemies nearby: counted 3", rally.last_enemy_count == 3, "%d" % rally.last_enemy_count)
	_check("...and the shield scales up (1 + 3 x 0.4)", is_equal_approx(crowded, alone * 2.2), "%.0f vs %.0f" % [crowded, alone])
	var hp := yellow.health_component.current_health
	yellow.hurtbox.take_hit(DamageInfo.create(200.0, null, DamageInfo.Type.TRUE))
	_check("...soaking damage before health", yellow.health_component.current_health == hp, "")
	_clear()
	await _seconds(2.1)


# --- Sting ------------------------------------------------------------------------

func _test_sting() -> void:
	_reset(Vector2(0, 11000), 1)
	var target := _dummy(Vector2(400, 11000))
	await _physics_frames(2)
	hits_log.clear()
	_aim(target.global_position)
	yellow.request_slot(&"cc", target.global_position)
	await _seconds(0.5)
	_check("Sting hits", _sum_count(target, &"sting") == 1, "")
	_check("...latches a bug: slowed", target.status_component.has_status(&"sting_slow")
		and is_equal_approx(target.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 0.6), "")
	_check("...with the bug showing", target.visuals._status_vfx.has(&"sting_slow"), "")
	await _seconds(2.4)
	_check("slow lasts ~2.5 s", not target.status_component.has_status(&"sting_slow"), "")
	_clear()


# --- CHARGE! ----------------------------------------------------------------------

func _test_charge() -> void:
	_reset(Vector2(0, 13000), 10)
	var charge: ChargeAbility = yellow.get_ability(&"ultimate")
	var start := yellow.global_position
	var first := _dummy(start + Vector2(250, 60))
	var second := _dummy(start + Vector2(600, -150))
	var side := _dummy(start + Vector2(400, 600))    # outside the wave
	for d in [first, second, side]:
		d.return_to_anchor = false
	await _physics_frames(2)
	_aim(start + Vector2(1000, 0))
	cues.clear()
	hits_log.clear()
	yellow.request_slot(&"ultimate", yellow.aim_point)
	await _seconds(0.1)
	_check("wind-up: bugle cue with the lane", _cue_count(&"charge_windup") == 1, "")
	var windup: Array = _cue_contexts(&"charge_windup")
	_check("...0.5 s long and the wave's width", not windup.is_empty() and is_equal_approx(windup[0].duration, 0.5)
		and is_equal_approx(windup[0].hit_width, 460.0), str(windup))
	_check("...he is planted", yellow.global_position.distance_to(start) < 3.0, "")
	_check("...nothing hit yet", hits_log.is_empty(), "")
	await _seconds(0.55)
	_check("the wave surges", charge.phase == Ability.Phase.ACTIVE, str(charge.phase))
	_check("enemies hit are stunned and carried", first.status_component.is_stunned()
		and first.status_component.is_carried(), "")
	var gap := first.global_position - yellow.global_position
	_check("...riding the crest (in front, within 150 px)", gap.length() <= 152.0, "%.0f" % gap.length())
	await _seconds(0.9)
	var end := start + Vector2(1000, 0)
	_check("he ends at the wave's end point", yellow.global_position.distance_to(end) < 10.0, str(yellow.global_position))
	_check("both enemies in the lane were hit", _sum_count(first, &"charge_wave") == 1 and _sum_count(second, &"charge_wave") == 1, "")
	_check("...not the one off to the side", _sum_count(side, &"charge_wave") == 0, "")
	_check("carried enemies arrive with him", first.global_position.x > end.x - 200.0
		and second.global_position.x > end.x - 200.0, "%s %s" % [first.global_position, second.global_position])
	_check("...and are dropped (no longer carried)", not first.status_component.is_carried()
		and not second.status_component.is_carried(), "")
	_check("...stunned briefly on the drop", first.status_component.has_status(&"charge_dropped"), "")
	var dropped_at := first.global_position
	await _seconds(0.2)
	_check("...and stay where they were dropped", first.global_position.distance_to(dropped_at) < 5.0, "")
	_check("drop cue per target", _cue_count(&"charge_drop") == 2, "%d" % _cue_count(&"charge_drop"))
	_clear()

	# A stun on him mid-wave drops everyone where they are.
	_reset(Vector2(0, 15000), 10)
	var victim := _dummy(yellow.global_position + Vector2(250, 0))
	victim.return_to_anchor = false
	await _physics_frames(2)
	_aim(yellow.global_position + Vector2(1000, 0))
	yellow.request_slot(&"ultimate", yellow.aim_point)
	await _seconds(0.7)
	_check("(carried before the stun)", victim.status_component.is_carried(), "")
	yellow.status_component.apply(_status(&"test_stun", "stuns"), null)
	await _physics_frames(2)
	_check("stunning him mid-wave releases the carried", not victim.status_component.is_carried()
		and victim.status_component.has_status(&"charge_dropped"), "")
	_clear()
	await _seconds(0.3)


# --- Bug army (cosmetic) ------------------------------------------------------------

func _test_bug_army() -> void:
	_reset(Vector2(0, 17000), 1)
	await _physics_frames(2)
	var army: Node = yellow.visuals.get_meta(&"cpt_yellow_bug_army") if yellow.visuals.has_meta(&"cpt_yellow_bug_army") else null
	_check("the bug army is on him", is_instance_valid(army), "")
	if not is_instance_valid(army):
		return
	var full: int = army.get_shown_count()
	yellow.hurtbox.take_hit(DamageInfo.create(yellow.health_component.max_health * 0.5, null, DamageInfo.Type.TRUE))
	await _physics_frames(1)
	var hurt: int = army.get_shown_count()
	_check("losing half his HP drops about half the bugs", hurt < full and hurt >= full / 2 - 1, "%d -> %d" % [full, hurt])
	yellow.health_component.heal(yellow.health_component.max_health)
	await _physics_frames(1)
	_check("healing brings them back", army.get_shown_count() == full, "%d" % army.get_shown_count())


# --- Helpers ----------------------------------------------------------------------

func _spawn_yellow(level: int) -> Hero:
	var y: Hero = load(YELLOW).instantiate()
	y.team = &"a"
	y.start_level = level
	add_child(y)
	y.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	return y


func _reset(at: Vector2, level: int) -> void:
	yellow.ability_controller.interrupt()
	yellow.status_component.clear()
	yellow.movement_component.stop_forced_move()
	yellow.stats_component.set_level(level)
	yellow.global_position = at
	yellow.velocity = Vector2.ZERO
	yellow.move_direction = Vector2.ZERO
	yellow.health_component.reset()
	for ability in yellow.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	yellow.aim_point = at
	yellow.aim_direction = (at - yellow.global_position).normalized()


func _dummy(at: Vector2, hp: float = 5000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	spawned.append(d)
	return d


func _status(id: StringName, flag: String) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = 0.2
	effect.set(flag, true)
	return effect


func _clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()


func _cue_count(name: StringName) -> int:
	return cues.filter(func(c): return c[0] == name).size()


func _cue_contexts(name: StringName) -> Array:
	return cues.filter(func(c): return c[0] == name).map(func(c): return c[1])


func _sum_count(target: Node, label: StringName) -> int:
	return hits_log.filter(func(i): return i.target == target and i.label == label).size()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
