extends Node2D

# Headless checks for Hazmat's kit and the shared pieces it added
# (GroundZoneData ramp + leaves_zone, ProjectileData lobbed + explosion_zone).
#
#   godot --headless res://tools/heroes/hazmat_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HAZMAT := "res://heroes/hazmat/hazmat_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"
const YELLOW_DEF := "res://heroes/cpt_yellow/cpt_yellow_definition.tres"
const AVERY_DEF := "res://heroes/avery/avery_definition.tres"
# Zones are found by meter label: heroes run on duplicates of their data.
const CLOUD := &"canister_cloud"
const RESIDUE := &"breach_residue"

var failures := 0
var hazmat: Hero
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	hazmat = load(HAZMAT).instantiate()
	hazmat.team = &"a"
	add_child(hazmat)
	await _physics_frames(3)
	_test_assembled()
	await _test_aura_ramp()
	await _test_ramp_reset()
	await _test_sprayer_head_start()
	await _test_quarantine_and_resolve()
	await _test_canister()
	await _test_seal_suit()
	await _test_breach()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, hazmat.get_ability(slot) != null, "")
	var definition := hazmat.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Hazmat"
		and definition.title == "The Contaminant" and definition.get_role_name() == "Tank", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"hazmat"), "")
	var yellow: HeroDefinition = load(YELLOW_DEF)
	_check("slower than Cpt. Yellow", definition.move_speed < yellow.move_speed,
		"%d vs %d" % [definition.move_speed, yellow.move_speed])
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 950.0) and _near(stats.health.value_at(10), 1850.0)
		and _near(stats.weapon.value_at(10), 70.0) and _near(stats.magic.value_at(10), 80.0)
		and _near(stats.armor.value_at(10), 75.0) and _near(stats.magic_resist.value_at(10), 55.0),
		"HP %.0f, W %.1f, M %.1f, A %.1f, MR %.1f" % [stats.health.value_at(10), stats.weapon.value_at(10),
		stats.magic.value_at(10), stats.armor.value_at(10), stats.magic_resist.value_at(10)])
	_check("Canister and Quarantine are the generic gun (data only)",
		hazmat.get_ability(&"ability_1").get_script() == RangedAttackAbility
		and hazmat.get_ability(&"cc").get_script() == RangedAttackAbility, "")
	_check("Seal Suit is the generic ChargeAbility (data only)", hazmat.get_ability(&"movement").get_script() == ChargeAbility, "")
	_check("Contamination is a passive", hazmat.get_ability(&"passive") is PassiveAbility, "")


# --- Contamination ------------------------------------------------------------------

func _test_aura_ramp() -> void:
	print("\n-- Contamination ramp")
	_reset(Vector2(0, 0))
	await _physics_frames(3)
	var passive := hazmat.get_ability(&"passive")
	_check("the aura follows Hazmat", is_instance_valid(passive.aura)
		and passive.aura.global_position.distance_to(hazmat.global_position) < 1.0, "")
	var dummy := _dummy(Vector2(120, 0))
	hits_log.clear()
	await _until(func(): return not _hits(dummy, &"contamination").is_empty(), 1.5)
	await _seconds(4.2)
	var ticks := _hits(dummy, &"contamination")
	_check("one tick per second", ticks.size() == 5, "%d ticks in 4 s" % ticks.size())
	if ticks.size() < 5:
		return
	var base := _base_tick()
	_check("the first tick is x1 (10 + 20% Magic)", _near(ticks[0].amount, base), "%.2f vs %.2f" % [ticks[0].amount, base])
	_check("+50% per second inside", _near(ticks[1].amount, base * 1.5) and _near(ticks[2].amount, base * 2.0), "")
	_check("after 4 s inside it deals 3x the first second's damage", _near(ticks[4].amount, ticks[0].amount * 3.0),
		"%.2f vs %.2f" % [ticks[4].amount, ticks[0].amount])
	await _seconds(1.0)
	ticks = _hits(dummy, &"contamination")
	_check("capped at 3x", _near(ticks.back().amount, base * 3.0), "%.2f" % ticks.back().amount)
	_clear()


func _test_ramp_reset() -> void:
	print("\n-- Ramp reset")
	_reset(Vector2(0, 3000))
	var dummy := _dummy(Vector2(120, 3000))
	await _seconds(2.2)
	var base := _base_tick()
	var ramped: float = _hits(dummy, &"contamination").back().amount
	_check("ramped up while inside", ramped > base * 1.4, "%.2f" % ramped)

	# A short step out keeps the ramp.
	dummy.global_position = Vector2(600, 3000)
	await _seconds(0.5)
	dummy.global_position = Vector2(120, 3000)
	hits_log.clear()
	await _until(func(): return not _hits(dummy, &"contamination").is_empty(), 1.5)
	var after_short := _hits(dummy, &"contamination")
	_check("stepping out for 0.5 s keeps the ramp", not after_short.is_empty() and after_short[0].amount > base * 1.4,
		"%.2f" % (after_short[0].amount if not after_short.is_empty() else 0.0))

	# 1 s outside resets it.
	dummy.global_position = Vector2(600, 3000)
	await _seconds(1.2)
	dummy.global_position = Vector2(120, 3000)
	hits_log.clear()
	await _until(func(): return not _hits(dummy, &"contamination").is_empty(), 1.5)
	var after_long := _hits(dummy, &"contamination")
	_check("stepping out for 1 s resets the ramp", not after_long.is_empty() and _near(after_long[0].amount, base),
		"%.2f vs %.2f" % [after_long[0].amount if not after_long.is_empty() else 0.0, base])
	_clear()


func _test_sprayer_head_start() -> void:
	print("\n-- Sprayer")
	_reset(Vector2(0, 6000))
	var dummy := _dummy(Vector2(300, 6000))
	var far := _dummy(Vector2(700, 6000))
	await _physics_frames(2)
	hits_log.clear()
	_aim(Vector2(300, 6000))
	for i in 6:
		hazmat.request_slot(&"primary", Vector2(300, 6000))
		await get_tree().physics_frame
	await _seconds(0.4)
	_check("the spray hits in range", not _hits(dummy, &"sprayer").is_empty(), "%d hits" % _hits(dummy, &"sprayer").size())
	_check("short range: nothing reaches 700 px", _hits(far, &"sprayer").is_empty(), "")
	_check("a hit starts the target one ramp step higher",
		ZoneRamp.get_steps(hazmat, &"contamination", dummy) == 1, str(ZoneRamp.get_steps(hazmat, &"contamination", dummy)))
	dummy.global_position = Vector2(120, 6000)
	hits_log.clear()
	await _until(func(): return not _hits(dummy, &"contamination").is_empty(), 1.5)
	var first := _hits(dummy, &"contamination")
	_check("...so its first aura tick is x1.5", not first.is_empty() and _near(first[0].amount, _base_tick() * 1.5),
		"%.2f" % (first[0].amount if not first.is_empty() else 0.0))
	_clear()


# --- Quarantine ------------------------------------------------------------------------

func _test_quarantine_and_resolve() -> void:
	print("\n-- Quarantine")
	_reset(Vector2(0, 9000))
	var target := _dummy(Vector2(450, 9000))
	await _physics_frames(2)
	_aim(target.global_position)
	var first := await _cast_quarantine(target)
	_check("Quarantine hooks the first enemy and stuns 0.4 s", _near(first, 0.4, 0.04), "%.3f s" % first)
	await _seconds(0.35)
	var gap := target.global_position.distance_to(hazmat.global_position)
	_check("...pulled all the way to Hazmat", gap < 160.0, "%.0f px away" % gap)

	await _until(func(): return not target.status_component.has_status(&"hazmat_quarantine"), 1.0)
	target.global_position = Vector2(450, 9000)
	hazmat.get_ability(&"cc").cooldown_remaining = 0.0
	await _physics_frames(2)
	_aim(target.global_position)
	var second := await _cast_quarantine(target)
	_check("a second stun within 2 s is halved (Resolve)", _near(second, 0.2, 0.04), "%.3f s" % second)
	_clear()


# Fires Quarantine and returns the stun's time left when it lands.
func _cast_quarantine(target: TrainingDummy) -> float:
	hazmat.request_slot(&"cc", target.global_position)
	var waited := 0.0
	while waited < 1.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if target.status_component.has_status(&"hazmat_quarantine"):
			return target.status_component.get_time_left(&"hazmat_quarantine")
	return 0.0


# --- Canister ----------------------------------------------------------------------------

func _test_canister() -> void:
	print("\n-- Canister")
	_reset(Vector2(0, 12000))
	var wall: Node2D = load(WALL).instantiate()
	wall.position = Vector2(250, 12000)
	add_child(wall)
	spawned.append(wall)
	var at := Vector2(550, 12000)
	var target := _dummy(at)
	await _physics_frames(2)
	hits_log.clear()
	_aim(at)
	hazmat.request_slot(&"ability_1", at)
	await _seconds(0.9)
	var cloud := _find_zone(CLOUD)
	_check("lobbed over a wall, it lands on the cursor and leaves a gas cloud",
		cloud != null and cloud.global_position.distance_to(at) < 20.0,
		str(cloud.global_position) if cloud != null else "no cloud")
	_check("the burst damages", not _hits(target, &"canister").is_empty(), "")
	_check("the cloud is 250 px and lasts 6 s", cloud != null and cloud.data.shape.radius == 250.0 and cloud.duration == 6.0, "")
	await _seconds(1.1)
	_check("the cloud's gas ramps on the shared Contamination ramp",
		ZoneRamp.get_steps(hazmat, &"contamination", target) >= 2, str(ZoneRamp.get_steps(hazmat, &"contamination", target)))
	if cloud != null:
		cloud.end()
	_clear()


# --- Seal Suit ---------------------------------------------------------------------------

func _test_seal_suit() -> void:
	print("\n-- Seal Suit")
	_reset(Vector2(0, 15000))
	await _physics_frames(2)
	_aim(Vector2(800, 15000))
	hazmat.request_slot(&"movement", Vector2(800, 15000))
	await _seconds(0.6)
	var moved := hazmat.global_position.x
	_check("shoves about 400 px forward", absf(moved - 400.0) < 40.0, "%.0f px" % moved)
	var status := hazmat.status_component
	_check("...then takes 30% less damage", status.has_status(&"hazmat_sealed")
		and _near(status.get_multiplier(StatusEffect.DAMAGE_TAKEN_PHYSICAL), 0.7)
		and _near(status.get_multiplier(StatusEffect.DAMAGE_TAKEN_MAGIC), 0.7), "")
	await _seconds(2.0)
	_check("...for 2 s", not status.has_status(&"hazmat_sealed"), "")


# --- Containment Breach --------------------------------------------------------------

func _test_breach() -> void:
	print("\n-- Containment Breach")
	_reset(Vector2(0, 18000))
	var target := _dummy(Vector2(400, 18000))
	await _physics_frames(3)
	hits_log.clear()
	hazmat.request_slot(&"ultimate", Vector2(300, 18000))
	await _seconds(0.3)
	var passive := hazmat.get_ability(&"passive")
	var breach = hazmat.get_ability(&"ultimate").zone
	_check("Breach replaces the aura with a 500 px zone", is_instance_valid(breach) and breach.data.shape.radius == 500.0
		and not is_instance_valid(passive.aura), "")
	var ticks := _hits(target, &"containment_breach")
	_check("...at full ramp at once (x3 on the first tick at 400 px)",
		not ticks.is_empty() and _near(ticks[0].amount, _base_tick() * 3.0),
		"%.2f" % (ticks[0].amount if not ticks.is_empty() else 0.0))
	_check("Hazmat isn't channelling: he can act during Breach", not hazmat.ability_controller.is_busy(), "")
	var end_spot: Vector2 = breach.global_position if is_instance_valid(breach) else Vector2.ZERO
	await _seconds(6.0)
	var residue := _find_zone(RESIDUE)
	_check("when it ends it leaves a residue zone behind", residue != null
		and residue.global_position.distance_to(end_spot) < 5.0 and residue.duration == 8.0, "")
	_check("...and the normal aura comes back", is_instance_valid(passive.aura) and passive.aura.data.shape.radius == 220.0, "")
	if residue != null:
		residue.end()
	_clear()


# --- Helpers -------------------------------------------------------------------------------

func _base_tick() -> float:
	var zone: GroundZoneData = hazmat.get_ability(&"passive").data.zone
	return zone.tick_damage.evaluate(hazmat.stats_component)


func _hits(target: Node, label: StringName) -> Array[DamageInfo]:
	return hits_log.filter(func(i): return i.target == target and i.label == label)


func _find_zone(label: StringName) -> GroundZone:
	for node in get_tree().current_scene.get_children():
		if node is GroundZone and not node.is_queued_for_deletion() and node.data.meter_label == label:
			return node
	return null


func _reset(at: Vector2) -> void:
	hazmat.ability_controller.interrupt()
	hazmat.status_component.clear()
	hazmat.movement_component.stop_forced_move()
	hazmat.global_position = at
	hazmat.velocity = Vector2.ZERO
	hazmat.move_direction = Vector2.ZERO
	hazmat.health_component.reset()
	for ability in hazmat.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	hazmat.aim_point = at
	hazmat.aim_direction = (at - hazmat.global_position).normalized()


func _dummy(at: Vector2, hp: float = 50000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	spawned.append(d)
	return d


func _clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()


func _near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= maxf(tolerance, absf(b) * 0.001)


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _until(condition: Callable, timeout: float) -> void:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
