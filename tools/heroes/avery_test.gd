extends Node2D

# Headless checks for Avery's kit against training dummies.
#
#   godot --headless res://tools/heroes/avery_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const AVERY := "res://heroes/avery/avery.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var avery: Hero
var dummies: Array[TrainingDummy] = []
var hits_log: Array[DamageInfo] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	avery = load(AVERY).instantiate()
	avery.team = &"a"
	add_child(avery)
	await _physics_frames(3)

	_test_assembled()
	await _test_primary_combo()
	await _test_crescent_pokes()
	await _test_searing_cut()
	await _test_charge()
	await _test_burn()
	await _test_sunbrand()
	await _test_blaze()
	await _test_revive()
	await _test_levels()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate"]:
		_check("slot %s filled" % slot, avery.get_ability(slot) != null, "")
	_check("ability_2 left empty", avery.get_ability(&"ability_2") == null, "")
	_check("definition validates", avery.definition.validate().is_empty(), "\n".join(avery.definition.validate()))


func _test_primary_combo() -> void:
	_reset_avery(Vector2.ZERO)
	var target := _dummy(Vector2(130, 0))
	await _physics_frames(2)
	hits_log.clear()
	var steps: Array[int] = []
	var primary := avery.get_ability(&"primary") as MeleeAttackAbility
	var on_act := func(): steps.append(primary._step_index + 1)
	primary.activated.connect(on_act)
	# Hold the button for ~1.6 s: the buffer should chain the full combo.
	await _hold_slot(&"primary", target.global_position, 1.6)
	primary.activated.disconnect(on_act)
	await _seconds(0.5)    # let the last swing finish
	var blade := hits_log.filter(func(i: DamageInfo): return i.target == target and i.label == &"blade")
	_check("holding primary chains the 3-hit combo", steps.slice(0, 3) == [1, 2, 3], str(steps))
	_check("each swing hits once", blade.size() == steps.size(), "%d hits / %d swings" % [blade.size(), steps.size()])
	if blade.size() >= 3:
		_check("finisher hits harder", blade[2].final_amount > blade[0].final_amount * 1.4,
			"%.0f vs %.0f" % [blade[2].final_amount, blade[0].final_amount])
	_clear_dummies()


func _test_crescent_pokes() -> void:
	_reset_avery(Vector2.ZERO)
	var near := _dummy(Vector2(130, 0))
	var far := _dummy(Vector2(480, 0))
	await _physics_frames(2)
	hits_log.clear()
	avery.request_slot(&"primary", far.global_position)
	await _seconds(0.8)
	var near_blade := _sum(near, &"blade")
	var near_crescent := _sum(near, &"crescent")
	var far_blade := _sum(far, &"blade")
	var far_crescent := _sum(far, &"crescent")
	_check("crescent reaches beyond the blade", far_blade == 0.0 and far_crescent > 0.0,
		"far blade %.0f crescent %.0f" % [far_blade, far_crescent])
	_check("crescent does less than the blade", near_crescent > 0.0 and near_crescent < near_blade,
		"blade %.0f crescent %.0f" % [near_blade, near_crescent])
	_check("crescent burns", far.status_component.has_status(&"avery_burn"), "")
	await _seconds(1.6)
	_check("burn ticks show up as 'burn'", _sum(far, &"burn") > 0.0, "")
	_clear_dummies()


func _test_searing_cut() -> void:
	_reset_avery(Vector2.ZERO)
	for i in 5:
		_dummy(Vector2(140, -80 + 40 * i))
	await _physics_frames(2)
	avery.health_component.current_health = 100.0
	var healed := [0.0]
	var on_heal := func(amount, _target, label): if label == &"searing_cut_heal": healed[0] += amount
	avery.combat_hooks.heal_done.connect(on_heal)
	avery.request_slot(&"ability_1", Vector2(300, 0))
	await _seconds(0.7)
	avery.combat_hooks.heal_done.disconnect(on_heal)
	var data := avery.get_ability(&"ability_1").data as SearingCutData
	var stats := avery.stats_component
	var expected := 0.0
	for n in range(1, 6):
		expected += data.heal_for_target(n, stats)
	expected = minf(expected, data.heal_cap.evaluate(stats))
	var single := data.heal_for_target(1, stats)
	_check("Searing Cut heals with falloff over 5 targets", is_equal_approx(healed[0], expected),
		"%.1f healed, expected %.1f" % [healed[0], expected])
	_check("5 targets heal less than 5x one target", healed[0] < single * 2.5,
		"%.1f vs single %.1f" % [healed[0], single])
	_clear_dummies()


func _test_charge() -> void:
	_reset_avery(Vector2.ZERO)
	var on_path := _dummy(Vector2(220, 0))
	await _physics_frames(2)
	hits_log.clear()
	var charge := avery.get_ability(&"movement").data as ChargeData
	avery.request_slot(&"movement", Vector2(1000, 0))
	await _seconds(0.08)
	_check("charge telegraphs before moving", avery.global_position.x < 20.0, "x=%.0f" % avery.global_position.x)
	await _seconds(0.6)
	var moved := avery.global_position.x
	_check("charge travels its distance", absf(moved - charge.distance) < 40.0,
		"%.0f vs %.0f" % [moved, charge.distance])
	await _seconds(0.6)
	_check("fire trail burns targets on the path", _sum(on_path, &"fire_trail") > 0.0, "")
	_clear_dummies()


func _test_burn() -> void:
	var burn := load("res://heroes/avery/data/avery_burn.tres") as StatusEffect
	_check("burn is true damage", burn.tick_damage_type == DamageInfo.Type.TRUE, str(burn.tick_damage_type))
	var stats := avery.stats_component
	var at_1 := burn.tick_damage.evaluate(stats)
	stats.set_level(10)
	var at_10 := burn.tick_damage.evaluate(stats)
	stats.set_level(1)
	_check("burn scales with Magic", burn.tick_damage.magic_ratio > 0.0 and at_10 > at_1 * 1.5,
		"%.1f -> %.1f per tick" % [at_1, at_10])
	# True damage ignores armor / magic resist: a dummy's tick lands in full.
	_reset_avery(Vector2.ZERO)
	var target := _dummy(Vector2(400, 0))
	await _physics_frames(2)
	hits_log.clear()
	target.status_component.apply(burn, avery)
	await _seconds(0.6)
	var ticks := hits_log.filter(func(i: DamageInfo): return i.target == target and i.label == &"burn")
	var expected := at_1 * GameRules.current().ttk_damage_multiplier    # only the global knob applies
	_check("burn ticks land in full", not ticks.is_empty() and is_equal_approx(ticks[0].final_amount, expected),
		"%s vs %.1f" % [str(ticks.map(func(i): return i.final_amount)), expected])
	_clear_dummies()


func _test_sunbrand() -> void:
	_reset_avery(Vector2.ZERO)
	var target := _dummy(Vector2(600, 0))
	await _physics_frames(2)
	hits_log.clear()
	var data := avery.get_ability(&"cc").data as RangedAttackData
	_check("Sunbrand reaches past Searing Cut", data.projectile.speed * data.projectile.lifetime
		> (avery.get_ability(&"ability_1").data as SearingCutData).hit_shape.get_reach() * 2.0, "")
	avery.request_slot(&"cc", target.global_position)
	await _seconds(0.7)
	_check("Sunbrand hits at range", _sum(target, &"sunbrand") > 0.0, "")
	var brand := target.status_component.has_status(&"avery_sunbrand")
	_check("target is branded", brand, "")
	_check("branded target is slowed, not stunned", not target.status_component.is_stunned(), "")
	var speed_mult := target.status_component.get_multiplier(StatusEffect.MOVE_SPEED)
	_check("brand slows movement 40%", is_equal_approx(speed_mult, 0.6), str(speed_mult))
	await _seconds(1.0)
	_check("brand burns for true damage", _sum(target, &"sunbrand_burn") > 0.0, "")
	_clear_dummies()


func _test_blaze() -> void:
	_reset_avery(Vector2.ZERO)
	var near := _dummy(Vector2(200, 0))
	await _physics_frames(2)
	hits_log.clear()
	var ult := avery.get_ability(&"ultimate")
	var data := ult.data as PhoenixRebirthData
	avery.health_component.current_health = 100.0
	_check("ult is ready", ult.is_ready(), "")
	_check("Blaze can be cast while alive", avery.request_slot(&"ultimate", near.global_position), "")
	await _seconds(0.5)
	_check("Blaze spends the ultimate", not ult.is_ready(), "")
	_check("Blaze puts the status on Avery", avery.status_component.has_status(&"avery_blaze"), "")
	_check("Blaze is faster", avery.status_component.get_multiplier(StatusEffect.MOVE_SPEED) > 1.2, "")
	await _seconds(1.0)
	_check("Blaze aura burns enemies", _sum(near, &"blaze_aura") > 0.0 and near.status_component.has_status(&"avery_burn"), "")
	_check("Blaze regenerates health", avery.health_component.current_health > 100.0,
		str(avery.health_component.current_health))
	# No revive while the ultimate is spent.
	var died := [false]
	var on_died := func(): died[0] = true
	avery.health_component.died.connect(on_died)
	avery.health_component.apply_damage(DamageInfo.create(99999.0, near, DamageInfo.Type.TRUE))
	_check("no revive after Blazing", died[0], "")
	avery.health_component.died.disconnect(on_died)
	_check("Blaze data validates", data.validate().is_empty(), "\n".join(data.validate()))
	_clear_dummies()
	avery.queue_free()
	avery = load(AVERY).instantiate()
	avery.team = &"a"
	add_child(avery)
	await _physics_frames(2)


func _test_revive() -> void:
	_reset_avery(Vector2.ZERO)
	var near := _dummy(Vector2(200, 0))
	await _physics_frames(2)
	hits_log.clear()
	var ult := avery.get_ability(&"ultimate")
	var data := ult.data as PhoenixRebirthData
	var died := [false]
	var on_died := func(): died[0] = true
	avery.health_component.died.connect(on_died)

	avery.health_component.apply_damage(DamageInfo.create(99999.0, near, DamageInfo.Type.TRUE))
	_check("lethal hit is survived while the ult is ready", not died[0] and not avery.health_component.is_dead(), "")
	_check("ult goes on cooldown", not ult.is_ready(), "")
	_check("she can't act during the rebirth", not avery.request_slot(&"primary", near.global_position), "")
	avery.health_component.apply_damage(DamageInfo.create(500.0, near))
	_check("invulnerable during the rebirth", is_equal_approx(avery.health_component.current_health, 1.0),
		str(avery.health_component.current_health))
	await _seconds(data.rebirth_duration + 0.1)
	_check("rises with restore_health_ratio of max HP",
		is_equal_approx(avery.health_component.current_health, avery.health_component.max_health * data.restore_health_ratio),
		"%.0f / %.0f" % [avery.health_component.current_health, avery.health_component.max_health])
	_check("fire burst damages nearby enemies", _sum(near, &"phoenix_burst") > 0.0, "")

	await _seconds(data.invulnerable_after + 0.1)
	avery.health_component.apply_damage(DamageInfo.create(99999.0, near, DamageInfo.Type.TRUE))
	_check("dies normally while the ult is on cooldown", died[0], "")
	avery.health_component.died.disconnect(on_died)
	_clear_dummies()

	# Fresh Avery for the rest (the dead one stays hidden).
	avery.queue_free()
	avery = load(AVERY).instantiate()
	avery.team = &"a"
	add_child(avery)
	await _physics_frames(2)


func _test_levels() -> void:
	var hp_1 := avery.health_component.max_health
	var searing := avery.get_ability(&"ability_1").data as SearingCutData
	var heal_1 := searing.heal_for_target(1, avery.stats_component)
	var cd_1 := avery.get_ability(&"ability_1").get_cooldown()
	avery.stats_component.set_level(10)
	var def := avery.definition
	_check("level 10 HP = base + 9 growth", is_equal_approx(avery.health_component.max_health,
		def.stats.health.base + def.stats.health.growth * 9), str(avery.health_component.max_health))
	_check("heal grows with level (Magic + per level)", searing.heal_for_target(1, avery.stats_component) > heal_1, "")
	_check("cooldown shrinks with level", avery.get_ability(&"ability_1").get_cooldown() < cd_1, "")
	_check("HP grows 1 -> 10", avery.health_component.max_health > hp_1, "")


# --- Helpers ------------------------------------------------------------------

func _reset_avery(at: Vector2) -> void:
	avery.ability_controller.interrupt()
	avery.status_component.clear()
	avery.movement_component.stop_forced_move()
	avery.global_position = at
	avery.velocity = Vector2.ZERO
	avery.health_component.reset()
	for ability in avery.ability_controller.abilities:
		ability.cooldown_remaining = 0.0


func _dummy(at: Vector2) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = 5000.0
	add_child(d)
	dummies.append(d)
	return d


func _clear_dummies() -> void:
	for d in dummies:
		d.queue_free()
	dummies.clear()
	await _physics_frames(2)


func _sum(target: Node, label: StringName) -> float:
	var total := 0.0
	for info in hits_log:
		if info.target == target and info.label == label:
			total += info.final_amount
	return total


# Simulates holding a hold_to_repeat slot: request every physics tick.
func _hold_slot(slot: StringName, at: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		avery.aim_point = at
		avery.aim_direction = (at - avery.global_position).normalized()
		avery.request_slot(slot, at)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
