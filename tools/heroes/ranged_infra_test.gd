extends Node

# Headless checks for the shared ranged-combat and status infrastructure:
# RangedAttackAbility (ammo, reloads, fire rate, muzzles, SEMI buffer),
# hold-to-charge, compel, status stat modifiers and applier notifications,
# and owned zones that follow / face / apply statuses while inside.
#
#   godot --headless res://tools/heroes/ranged_infra_test.tscn
#
# Uses the TEST-ONLY hero in tools/heroes/ranged_test/.
# Exits with the number of failed checks (0 = all passed).

const HERO_SCENE := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const HERO_BASE := "res://scenes/heroes/hero_base.tscn"
const AUTO_DEFINITION := "res://tools/heroes/ranged_test/ranged_test_auto_definition.tres"
const DEFINITION := "res://tools/heroes/ranged_test/ranged_test_definition.tres"
const DUMMY := "res://scenes/training_dummy.tscn"
const ENEMY := "res://scenes/enemy.tscn"
const COMPEL := "res://tools/heroes/ranged_test/data/ranged_test_compel.tres"
const WITHER := "res://tools/heroes/ranged_test/data/ranged_test_wither.tres"
const CONE_SLOW := &"ranged_test_cone_slow"

var failures := 0
var hero: Hero
var cues: Array = []    # [cue, context] from the main hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_data_and_roster()
	await _setup()
	await _test_ammo_and_muzzles()
	await _test_semi_buffer_and_hold()
	await _test_auto_and_per_round_reload()
	await _test_manual_reload_and_instant()
	await _test_fire_rate_and_full_reload()
	await _test_charge()
	await _test_compel()
	await _test_compel_on_enemy()
	await _test_stat_modifier_status()
	await _test_status_target_died()
	await _test_follow_cone()
	_test_cooldown_api()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- Data -------------------------------------------------------------------

func _test_data_and_roster() -> void:
	for path in [DEFINITION, AUTO_DEFINITION]:
		var def: HeroDefinition = load(path)
		var problems := def.validate()
		_check("test hero validates clean: %s" % def.hero_id, problems.is_empty(), "\n  ".join(problems))
	var roster := HeroScaffold.find_definitions().map(func(d): return d.hero_id)
	var dev := HeroScaffold.find_dev_definitions().map(func(d): return d.hero_id)
	_check("test hero is NOT in the roster", not roster.has(&"ranged_test"), str(roster))
	_check("test hero is in the dev (Play as) list", dev.has(&"ranged_test") and dev.has(&"ranged_test_auto"), str(dev))

	var bad: RangedAttackData = load("res://tools/heroes/ranged_test/ranged_test_revolver.tres").duplicate_deep()
	bad.projectile = null
	bad.shots_per_second = 0.0
	bad.ammo_per_shot = 9
	bad.charge_enabled = true
	bad.charge_time_max = 0.0
	_check("validation catches bad ranged/charge data", bad.validate().size() >= 4, "\n  ".join(bad.validate()))

	var rows := BalanceExporter.build_rows([load(DEFINITION)] as Array[HeroDefinition], [1, 10, 20] as Array[int])
	var burst := -1.0
	var sustained := -1.0
	var has_magazine := false
	for row in rows:
		if row[2] == 1 and row[5] == "ranged_test_revolver":
			match row[6]:
				"burst_dps": burst = row[7]
				"sustained_dps": sustained = row[7]
				"magazine_size": has_magazine = row[7] == 6
	# 50 dmg x 3/s = 150 burst. Sustained: 6 shots in 2 s + 6 x 0.4 s reload.
	_check("CSV has gun metrics", has_magazine and is_equal_approx(burst, 150.0), "burst %.1f" % burst)
	_check("CSV sustained DPS includes reloads", is_equal_approx(sustained, 50.0 * 6.0 / (2.0 + 2.4)), "%.2f" % sustained)


# --- Arena ------------------------------------------------------------------

func _setup() -> void:
	hero = _spawn_hero(load(HERO_SCENE), Vector2.ZERO, &"a")
	hero.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	await _frames(3)


func _spawn_hero(scene: PackedScene, at: Vector2, team: StringName, definition: HeroDefinition = null) -> Hero:
	var h: Hero = scene.instantiate()
	if definition != null:
		h.definition = definition
	h.team = team
	add_child(h)
	h.global_position = at
	h.aim_direction = Vector2.RIGHT
	h.aim_point = at + Vector2.RIGHT * 300.0
	return h


func _spawn_dummy(at: Vector2, hp: float = 5000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.max_health = hp
	add_child(d)
	return d


func _aim(h: Hero, at: Vector2) -> void:
	h.aim_point = at
	h.aim_direction = (at - h.global_position).normalized()


func _cue_contexts(name: StringName) -> Array:
	return cues.filter(func(c): return c[0] == name).map(func(c): return c[1])


# --- Guns -------------------------------------------------------------------

func _test_ammo_and_muzzles() -> void:
	var dummy := _spawn_dummy(Vector2(300, 0))
	await _frames(2)
	var gun := hero.get_ranged_ability()
	_check("get_ranged_ability finds the primary gun", gun != null and gun.ability_id == &"ranged_test_revolver", "")
	_check("magazine starts full", gun.get_ammo() == 6 and gun.get_max_ammo() == 6, "%d/%d" % [gun.get_ammo(), gun.get_max_ammo()])

	cues.clear()
	var hp := dummy.health_component.current_health
	_aim(hero, dummy.global_position)
	var fired := hero.request_slot(&"primary", dummy.global_position)
	await _seconds(0.3)
	_check("SEMI shot fired", fired, "")
	_check("ammo decrements by ammo_per_shot", gun.get_ammo() == 5, str(gun.get_ammo()))
	# 30 + 0.5 x 40 Weapon, inside falloff_start.
	_check("shot damage = damage ScalingValue", is_equal_approx(hp - dummy.health_component.current_health, 50.0),
		"%.1f" % (hp - dummy.health_component.current_health))
	_check("fire and hit cues", _cue_contexts(&"ranged_test_revolver_fire").size() == 1
		and _cue_contexts(&"ranged_test_revolver_hit").size() == 1, "")

	for i in 2:
		await _seconds(0.35)
		hero.request_slot(&"primary", dummy.global_position)
	await _physics_frames(2)
	var fires := _cue_contexts(&"ranged_test_revolver_fire")
	var indices := fires.map(func(c): return c.muzzle_index)
	_check("muzzles alternate", indices == [0, 1, 0], str(indices))
	if fires.size() >= 2:
		var gap: float = (fires[0].position as Vector2).distance_to(fires[1].position)
		_check("alternating muzzles are 28 px apart", is_equal_approx(gap, 28.0), "%.1f" % gap)

	# Falloff: a target past falloff_end takes falloff_min_multiplier.
	var far := _spawn_dummy(Vector2(0, 790))
	await _frames(2)
	await _seconds(0.35)
	var far_hp := far.health_component.current_health
	_aim(hero, far.global_position)
	hero.request_slot(&"primary", far.global_position)
	await _seconds(0.6)
	var far_dealt := far_hp - far.health_component.current_health
	# Hurtbox centre is ~740 px from the muzzle: 1 - 0.4 x (240/300) = 0.68.
	_check("damage falls off with distance", far_dealt > 25.0 and far_dealt < 40.0, "%.1f" % far_dealt)
	far.queue_free()
	dummy.queue_free()
	gun.reload_instantly()


func _test_semi_buffer_and_hold() -> void:
	var gun := hero.get_ranged_ability()
	var rifle_data: RangedAttackData = load("res://tools/heroes/ranged_test/ranged_test_rifle.tres")
	_check("SEMI does not repeat while held", not gun.repeats_while_held(true), "")
	_check("charge abilities don't repeat while held", not hero.get_ability(&"ability_1").repeats_while_held(true), "")
	_check("AUTO repeats while held, in any slot", rifle_data.fire_mode == RangedAttackData.FireMode.AUTO, "")
	var melee := MeleeAttackAbility.new()
	_check("melee keeps the slot's hold_to_repeat",
		melee.repeats_while_held(true) and not melee.repeats_while_held(false), "")
	melee.free()

	await _seconds(0.4)
	cues.clear()
	hero.request_slot(&"primary", hero.aim_point)
	await _seconds(0.25)
	# Too early (interval is 0.33 s) but within the 0.12 s SEMI buffer.
	var early := hero.request_slot(&"primary", hero.aim_point)
	await _seconds(0.15)
	_check("early SEMI click isn't eaten (buffered)", not early and _cue_contexts(&"ranged_test_revolver_fire").size() == 2,
		"%d shots" % _cue_contexts(&"ranged_test_revolver_fire").size())
	await _seconds(0.4)
	# Much too early: dropped.
	cues.clear()
	hero.request_slot(&"primary", hero.aim_point)
	await _seconds(0.05)
	hero.request_slot(&"primary", hero.aim_point)
	await _seconds(0.35)
	_check("a click far too early is dropped", _cue_contexts(&"ranged_test_revolver_fire").size() == 1,
		"%d shots" % _cue_contexts(&"ranged_test_revolver_fire").size())
	_check("waiting on the fire interval is silent", _cue_contexts(&"ability_failed").is_empty(), "")
	gun.reload_instantly()


func _test_auto_and_per_round_reload() -> void:
	var gun := hero.get_ranged_ability()
	await _seconds(0.4)
	cues.clear()
	await _fire_until_empty(hero, &"primary", 4.0)
	_check("emptied the magazine", gun.get_ammo() == 0, str(gun.get_ammo()))
	_check("auto reload starts when empty", gun.is_reloading(), "")
	_check("reload_start cue", not _cue_contexts(&"ranged_test_revolver_reload_start").is_empty(), "")
	await _seconds(0.85)
	_check("PER_ROUND loads one round per interval", gun.get_ammo() == 2, str(gun.get_ammo()))
	var ratio := gun.get_reload_ratio()
	_check("reload ratio reflects progress", ratio > 0.3 and ratio < 0.5, "%.2f" % ratio)

	var cancelled := [0]
	var on_cancel := func(): cancelled[0] += 1
	gun.reload_cancelled.connect(on_cancel)
	var fired := hero.request_slot(&"primary", hero.aim_point)
	await _physics_frames(2)
	gun.reload_cancelled.disconnect(on_cancel)
	_check("firing interrupts a PER_ROUND reload", fired and cancelled[0] == 1 and not gun.is_reloading(), "")
	_check("the interrupting shot used a loaded round", gun.get_ammo() == 1, str(gun.get_ammo()))


func _test_manual_reload_and_instant() -> void:
	var gun := hero.get_ranged_ability()
	var finished := [0]
	var on_finished := func(): finished[0] += 1
	gun.reload_finished.connect(on_finished)
	_check("hero.reload() starts a reload", hero.reload() and gun.is_reloading(), "")
	_check("a second reload request is refused", not hero.reload(), "")
	gun.reload_instantly()
	_check("reload_instantly fills and ends the reload",
		gun.get_ammo() == 6 and not gun.is_reloading() and finished[0] == 1, "%d" % gun.get_ammo())
	_check("reload refused when full", not hero.reload(), "")
	gun.reload_finished.disconnect(on_finished)

	# The movement ability (a dash) reloads through the same public call.
	await _seconds(0.4)
	hero.request_slot(&"primary", hero.aim_point)
	await _physics_frames(2)
	var before := gun.get_ammo()
	hero.request_slot(&"movement", hero.global_position + Vector2(0, 300))
	await _seconds(0.4)
	_check("another ability can reload the gun", before == 5 and gun.get_ammo() == 6, "%d -> %d" % [before, gun.get_ammo()])
	gun.add_ammo(3)
	_check("add_ammo clamps to the magazine", gun.get_ammo() == 6, "")
	hero.global_position = Vector2.ZERO


func _test_fire_rate_and_full_reload() -> void:
	var rifle_hero := _spawn_hero(load(HERO_BASE), Vector2(0, -1500), &"a", load(AUTO_DEFINITION))
	await _frames(3)
	var gun := rifle_hero.get_ranged_ability()
	_check("AUTO variant has the rifle primary", gun != null and gun.ability_id == &"ranged_test_rifle", "")
	var shots := [0]
	var on_fire := func(cue, _c): if cue == &"ranged_test_rifle_fire": shots[0] += 1
	rifle_hero.cue_triggered.connect(on_fire)

	await _hold(rifle_hero, &"primary", 1.0)
	var base_rate: int = shots[0]
	_check("AUTO fires ~8 shots/s while held", base_rate >= 7 and base_rate <= 9, str(base_rate))

	gun.reload_instantly()
	var haste := StatusEffect.new()
	haste.id = &"test_haste"
	haste.duration = 5.0
	haste.stat_multipliers = {StatusEffect.FIRE_RATE: 2.0}
	rifle_hero.status_component.apply(haste)
	await _seconds(0.2)
	shots[0] = 0
	await _hold(rifle_hero, &"primary", 1.0)
	_check("FIRE_RATE x2 doubles shots per second", shots[0] >= 15 and shots[0] <= 17, str(shots[0]))
	rifle_hero.status_component.remove(&"test_haste")

	await _fire_until_empty(rifle_hero, &"primary", 5.0)
	_check("FULL reload starts when empty", gun.is_reloading() and gun.get_ammo() == 0, "")
	await _seconds(0.8)
	_check("FULL reload doesn't trickle rounds in", gun.get_ammo() == 0 and gun.get_reload_ratio() > 0.4, "%.2f" % gun.get_reload_ratio())
	var blocked := rifle_hero.request_slot(&"primary", rifle_hero.aim_point)
	_check("can't fire during a FULL reload", not blocked, "")
	await _seconds(0.9)
	_check("FULL reload refills the magazine", gun.get_ammo() == 24 and not gun.is_reloading(), str(gun.get_ammo()))
	rifle_hero.queue_free()


# --- Charge -----------------------------------------------------------------

func _test_charge() -> void:
	var dummy := _spawn_dummy(Vector2(300, 0))
	await _frames(2)
	_aim(hero, dummy.global_position)
	var shot := hero.get_ability(&"ability_1") as RangedAttackAbility
	var stats := hero.stats_component
	var low := shot.data.damage.evaluate(stats)                       # 40 + 0.6 x 40 = 64
	var high := shot.data.get_value(&"damage_full", stats)            # 120 + 1.4 x 40 = 176

	# Half charge.
	cues.clear()
	var hp := dummy.health_component.current_health
	_check("charge press starts charging", hero.request_slot(&"ability_1", dummy.global_position) and shot.is_charging(), "")
	_check("cooldown isn't spent while charging", shot.is_ready(), "")
	_check("charging slows walking", is_equal_approx(hero.movement_component.get_action_multiplier(), 0.5), "")
	await _seconds(0.5)
	var released := hero.release_slot(&"ability_1", dummy.global_position)
	var ratio := shot.get_charge_ratio()
	await _seconds(0.3)
	var expected := lerpf(low, high, ratio)
	var dealt := hp - dummy.health_component.current_health
	_check("release fires", released and not shot.is_ready(), "")
	_check("charge ratio ~0.5 after 0.5 s", ratio > 0.45 and ratio < 0.56, "%.2f" % ratio)
	_check("get_charged_value lerps damage -> damage_full", absf(dealt - expected) < 0.01,
		"%.1f vs %.1f" % [dealt, expected])
	_check("charge_start / charge_release cues", not _cue_contexts(&"ranged_test_charged_shot_charge_start").is_empty()
		and not _cue_contexts(&"ranged_test_charged_shot_charge_release").is_empty(), "")
	_check("half charge isn't perfect", not shot.was_perfect_release(), "")

	# Perfect release (full charge + inside the 0.2 s window). Each test
	# waits out the shot's 1 s fire interval (shots_per_second = 1).
	shot.reset_cooldown()
	await _seconds(1.0)
	hp = dummy.health_component.current_health
	hero.request_slot(&"ability_1", dummy.global_position)
	# HUD: a gun slot (ammo + reload sweep) and a charging slot (charge bar)
	# draw without errors, and the melee path is untouched.
	var hud := CanvasLayer.new()
	add_child(hud)
	for ability in [hero.get_ability(&"primary"), shot]:
		var slot := AbilitySlot.new()
		hud.add_child(slot)
		slot.setup(ability)
	await _seconds(1.1)
	hud.queue_free()
	_check("perfect window registers while held", shot.is_in_perfect_window(), "")
	_check("charge_full cue", not _cue_contexts(&"ranged_test_charged_shot_charge_full").is_empty(), "")
	hero.release_slot(&"ability_1", dummy.global_position)
	var perfect := shot.was_perfect_release()
	await _seconds(0.3)
	dealt = hp - dummy.health_component.current_health
	_check("release in the window is perfect", perfect, "")
	_check("perfect x1.25 at full charge", is_equal_approx(dealt, high * 1.25), "%.1f vs %.1f" % [dealt, high * 1.25])

	# Late release: full charge, not perfect.
	shot.reset_cooldown()
	await _seconds(1.0)
	hp = dummy.health_component.current_health
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(1.4)
	hero.release_slot(&"ability_1", dummy.global_position)
	await _seconds(0.3)
	dealt = hp - dummy.health_component.current_health
	_check("late release: full damage, not perfect", not shot.was_perfect_release() and is_equal_approx(dealt, high),
		"%.1f" % dealt)

	# Below the minimum, CANCEL: nothing fires, no cooldown.
	shot.reset_cooldown()
	await _seconds(1.0)
	hp = dummy.health_component.current_health
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(0.1)
	released = hero.release_slot(&"ability_1", dummy.global_position)
	await _seconds(0.3)
	_check("release below min (CANCEL) fires nothing",
		not released and is_equal_approx(hp, dummy.health_component.current_health), "")
	_check("cancelled charge costs no cooldown", shot.is_ready() and not shot.is_casting(), "")
	_check("cancel clears the charge slow", is_equal_approx(hero.movement_component.get_action_multiplier(), 1.0), "")

	# Below the minimum, FIRE_MINIMUM: fires at the minimum ratio.
	shot.data.charge_below_min = AbilityData.ChargeBelowMin.FIRE_MINIMUM
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(0.1)
	released = hero.release_slot(&"ability_1", dummy.global_position)
	await _seconds(0.3)
	dealt = hp - dummy.health_component.current_health
	_check("release below min (FIRE_MINIMUM) fires at the minimum", released and is_equal_approx(dealt, lerpf(low, high, 0.25)),
		"%.1f vs %.1f" % [dealt, lerpf(low, high, 0.25)])
	shot.reset_data()

	# Another ability cancels the charge (no cooldown) and starts.
	shot.reset_cooldown()
	await _seconds(0.3)
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(0.2)
	var primary_started := hero.request_slot(&"primary", dummy.global_position)
	_check("another key cancels the charge without cooldown",
		not shot.is_charging() and shot.is_ready() and primary_started, "")

	# AI path: a buffered press whose release came first still ends its charge.
	await _seconds(0.4)
	hero.request_slot(&"primary", dummy.global_position)
	await _physics_frames(1)
	hero.request_slot(&"ability_1", dummy.global_position)    # buffered behind the shot
	hero.release_slot(&"ability_1", dummy.global_position)    # released before it began
	await _seconds(0.3)
	_check("release of a buffered charge isn't lost", not shot.is_charging(), "")

	# Auto release at max.
	shot.data.charge_auto_release_at_max = true
	shot.reset_cooldown()
	await _seconds(1.0)
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(1.1)
	_check("auto release fires at full charge (never perfect)",
		not shot.is_charging() and not shot.is_ready() and not shot.was_perfect_release(), "")
	shot.reset_data()

	# A stun during the charge: interrupted, no cooldown.
	shot.reset_cooldown()
	await _seconds(0.3)
	hero.request_slot(&"ability_1", dummy.global_position)
	await _seconds(0.2)
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.1
	stun.stuns = true
	hero.status_component.apply(stun, dummy)
	_check("stun interrupts a charge without spending the cooldown", not shot.is_charging() and shot.is_ready(), "")
	await _seconds(0.2)

	# ChargeAbility (the dash) is unchanged without charge_enabled.
	var dash := hero.get_ability(&"movement")
	_check("dash doesn't charge unless its data says so", not dash.uses_charge() and dash.repeats_while_held(false) == false, "")
	dummy.queue_free()


# --- Compel -----------------------------------------------------------------

func _test_compel() -> void:
	var source := _spawn_hero(load(HERO_SCENE), Vector2(900, 400), &"b")
	var dummy := _spawn_dummy(Vector2(900, 1200))
	await _frames(3)
	var compel: StatusEffect = load(COMPEL).duplicate()
	compel.duration = 30.0    # this test ends it by killing the source
	dummy.status_component.apply(compel, source)
	_check("compel applied", dummy.status_component.is_compelled(), "")

	# Dummies walk at 220 px/s; compel_speed_multiplier 0.8 -> 176 px/s.
	var start_gap := dummy.global_position.distance_to(source.global_position)
	await _seconds(0.5)
	var gap := dummy.global_position.distance_to(source.global_position)
	_check("compelled dummy walks toward the source (ignoring its anchor)", gap < start_gap - 60.0,
		"%.0f -> %.0f" % [start_gap, gap])

	# Move the source sideways; the march follows its CURRENT position.
	source.move_direction = Vector2.RIGHT
	await _seconds(0.5)
	source.move_direction = Vector2.ZERO
	await _physics_frames(2)
	var heading := dummy.velocity.normalized()
	var wanted := (source.global_position - dummy.global_position).normalized()
	_check("compel tracks a moving source", heading.dot(wanted) > 0.97 and source.global_position.x > 1100.0,
		"dot %.3f, source x %.0f" % [heading.dot(wanted), source.global_position.x])

	# A knockback mid-compel still happens, then the march resumes.
	var knock := StatusEffect.new()
	knock.id = &"test_knock"
	knock.duration = 0.1
	knock.displace_distance = 150.0
	knock.displace_duration = 0.1
	knock.displace_direction = StatusEffect.DisplaceDirection.AWAY_FROM_SOURCE
	gap = dummy.global_position.distance_to(source.global_position)
	dummy.status_component.apply(knock, source)
	await _seconds(0.12)
	var pushed := dummy.global_position.distance_to(source.global_position)
	_check("knockback during compel still pushes", pushed > gap + 100.0, "%.0f -> %.0f" % [gap, pushed])
	await _seconds(0.4)
	_check("compel resumes after the knockback",
		dummy.global_position.distance_to(source.global_position) < pushed - 60.0 and dummy.status_component.is_compelled(), "")

	await _seconds(5.0)
	gap = dummy.global_position.distance_to(source.global_position)
	_check("compel stops at compel_stop_distance", gap > 80.0 and gap < 110.0, "%.1f" % gap)

	# Stuns still stop the march.
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.3
	stun.stuns = true
	source.global_position += Vector2(400, 0)
	dummy.status_component.apply(stun)
	var x_before := dummy.global_position.x
	await _seconds(0.25)
	_check("a stun holds a compelled target still", absf(dummy.global_position.x - x_before) < 5.0, "")

	# A hero despawns when it dies (it's freed, so it can't be told).
	source.health_component.kill(null)
	await _physics_frames(2)
	_check("compel ends when the source dies", not dummy.status_component.is_compelled(), "")

	# A source that stays in the world when dead (a dummy) is told why.
	var totem := _spawn_dummy(Vector2(1400, 1200), 100.0)
	await _frames(2)
	dummy.status_component.apply(compel, totem)
	var removed_reason := [&""]
	var on_removed := func(id, _t, reason): if id == compel.id: removed_reason[0] = reason
	CombatHooks.find_on(totem).status_removed.connect(on_removed)
	totem.health_component.kill(null)
	await _physics_frames(2)
	_check("status_removed(reason = applier_died) on the applier", not dummy.status_component.is_compelled()
		and removed_reason[0] == StatusEffectComponent.REASON_APPLIER_DIED, str(removed_reason[0]))
	dummy.queue_free()
	totem.queue_free()


func _test_compel_on_enemy() -> void:
	# Enemy AI (scenes/enemy.gd) chases the player; compel must win, exactly
	# like stuns and roots do, because both live in MovementComponent.
	hero.add_to_group(&"player")
	hero.health_component.god_mode = true
	var enemy: Actor = load(ENEMY).instantiate()
	add_child(enemy)
	enemy.global_position = Vector2(-600, 0)
	enemy.weapon_component.is_disarmed = true    # legacy rifle; not under test
	var puller := _spawn_dummy(Vector2(-600, 800))
	await _frames(3)
	var compel: StatusEffect = load(COMPEL).duplicate()
	compel.duration = 1.0
	enemy.status_component.apply(compel, puller)
	await _seconds(0.5)
	# The player is to the right; the source is straight down.
	_check("enemy AI yields to compel (walks to the source, not the player)",
		enemy.global_position.y > 40.0 and absf(enemy.global_position.x + 600.0) < 10.0,
		str(enemy.global_position))
	enemy.queue_free()
	puller.queue_free()
	hero.remove_from_group(&"player")
	hero.health_component.god_mode = false
	await _frames(2)


# --- Stat modifiers and applier notifications -------------------------------

func _test_stat_modifier_status() -> void:
	var dummy := _spawn_dummy(Vector2(-900, -900), 1000.0)
	var other := _spawn_hero(load(HERO_SCENE), Vector2(-1500, -900), &"b")
	await _frames(3)
	var health := dummy.health_component
	var wither: StatusEffect = load(WITHER)
	health.apply_damage(DamageInfo.create(100.0, null, DamageInfo.Type.TRUE))
	dummy.status_component.apply(wither, hero)
	_check("-20% Health modifier lowers max HP", is_equal_approx(health.max_health, 800.0), str(health.max_health))
	_check("current HP is clamped to the new max", is_equal_approx(health.current_health, 800.0), str(health.current_health))

	dummy.status_component.apply(wither, other)
	_check("two appliers each apply their own (stack_per_applier)", is_equal_approx(health.max_health, 600.0), str(health.max_health))
	dummy.status_component.remove_from(wither.id, hero)
	_check("removing one applier's is exact", is_equal_approx(health.max_health, 800.0)
		and dummy.status_component.has_status_from(wither.id, other), str(health.max_health))
	dummy.status_component.remove_from(wither.id, other)
	_check("removal restores max HP exactly", health.max_health == 1000.0
		and dummy.stats_component.get_stat(StatBlock.HEALTH) == 1000.0
		and dummy.stats_component.get_modifiers().is_empty(), str(health.max_health))
	_check("removal doesn't gift current HP", is_equal_approx(health.current_health, 600.0), str(health.current_health))

	# Level-ups still grant HP (the MOBA rule is untouched).
	var hp := hero.health_component.current_health
	hero.stats_component.set_level(2)
	_check("level-up still grants current HP", is_equal_approx(hero.health_component.current_health, hp + 55.0), "")
	hero.stats_component.set_level(1)
	hero.health_component.reset()

	# Natural expiry notifies the applier.
	var short: StatusEffect = wither.duplicate()
	short.duration = 0.2
	var expired := [0]
	var reasons := []
	var on_expired := func(id, target): if id == wither.id and target == dummy: expired[0] += 1
	var on_removed := func(id, _t, reason): if id == wither.id: reasons.append(reason)
	hero.combat_hooks.status_expired.connect(on_expired)
	hero.combat_hooks.status_removed.connect(on_removed)
	dummy.status_component.apply(short, hero)
	await _seconds(0.3)
	hero.combat_hooks.status_expired.disconnect(on_expired)
	hero.combat_hooks.status_removed.disconnect(on_removed)
	_check("status_expired fires on the applier", expired[0] == 1, str(expired[0]))
	_check("status_removed(reason = expired)", reasons == [StatusEffectComponent.REASON_EXPIRED], str(reasons))
	_check("expiry restores max HP", health.max_health == 1000.0, str(health.max_health))
	dummy.queue_free()
	other.queue_free()


func _test_status_target_died() -> void:
	var marked := _spawn_dummy(Vector2(300, 0), 500.0)
	var killer := _spawn_hero(load(HERO_SCENE), Vector2(300, 600), &"b")
	await _frames(3)
	var mark_ability := hero.get_ability(&"ability_2")
	_aim(hero, marked.global_position)
	hero.request_slot(&"ability_2", marked.global_position)
	await _seconds(0.3)
	_check("wither shot marks the target", marked.status_component.has_status_from(&"ranged_test_wither", hero), "")
	_check("mark shows an overhead marker (attached_vfx)", marked.visuals._status_vfx.has(&"ranged_test_wither"), "")
	_check("mark ability is on cooldown", not mark_ability.is_ready(), "")

	# A future "reset on marked kill" ability, as a hook listener.
	var died := []
	var on_died := func(id: StringName, target: Node, info: DamageInfo):
		died.append([id, target, info.source])
		if id == &"ranged_test_wither":
			mark_ability.reset_cooldown()
	hero.combat_hooks.status_target_died.connect(on_died)
	var killer_kills := [0]
	var on_kill := func(_v, _i): killer_kills[0] += 1
	killer.combat_hooks.kill.connect(on_kill)
	marked.hurtbox.take_hit(DamageInfo.create(99999.0, killer, DamageInfo.Type.TRUE))
	hero.combat_hooks.status_target_died.disconnect(on_died)
	_check("status_target_died fires on the APPLIER when a third party kills",
		died.size() == 1 and died[0][0] == &"ranged_test_wither" and died[0][1] == marked and died[0][2] == killer, str(died))
	_check("the killer still gets its kill hook", killer_kills[0] == 1, "")
	_check("reset_cooldown on marked death", mark_ability.is_ready(), "")
	_check("statuses are cleared on death", not marked.status_component.has_status(&"ranged_test_wither"), "")
	marked.queue_free()
	killer.queue_free()


# --- Owned zones ------------------------------------------------------------

func _test_follow_cone() -> void:
	hero.global_position = Vector2.ZERO
	_aim(hero, Vector2(300, 0))
	var inside := _spawn_dummy(Vector2(220, 0))
	var behind := _spawn_dummy(Vector2(-220, 0))
	await _frames(3)
	var ult := hero.get_ability(&"ultimate") as ZoneAbility
	var hp := inside.health_component.current_health
	hero.request_slot(&"ultimate", Vector2(300, 0))
	await _seconds(0.35)
	var zone := ult.zone
	_check("ultimate spawned an owned zone", is_instance_valid(zone) and ult.get_owned_zones().has(zone), "")
	if not is_instance_valid(zone):
		return
	var entered := []
	var exited := []
	var ticked := [0]
	zone.target_entered.connect(func(h): entered.append(h.owner))
	zone.target_exited.connect(func(h): exited.append(h.owner))
	zone.target_ticked.connect(func(_h): ticked[0] += 1)
	_check("cone hits and applies its while-inside status", inside.health_component.current_health < hp
		and inside.status_component.has_status(CONE_SLOW), "")
	_check("cone doesn't reach behind the hero", not behind.status_component.has_status(CONE_SLOW)
		and behind.health_component.current_health == behind.health_component.max_health, "")
	await _seconds(0.3)
	_check("target_ticked fires per tick", ticked[0] >= 1, str(ticked[0]))

	# Owner moves: the zone follows.
	hero.global_position = Vector2(0, 700)
	await _physics_frames(2)
	_check("follow_owner keeps the zone on the hero", zone.global_position.distance_to(hero.global_position) < 1.0,
		str(zone.global_position))
	_check("leaving drops the while-inside status right away", not inside.status_component.has_status(CONE_SLOW)
		and exited.has(inside), "")

	# Owner turns: the cone rotates with the aim.
	hero.global_position = Vector2.ZERO
	_aim(hero, Vector2(-300, 0))
	await _physics_frames(2)
	_check("face_aim rotates the cone", zone.direction.dot(Vector2.LEFT) > 0.99, str(zone.direction))
	_check("the rotated cone picks up the target behind (aura applies on entry)",
		behind.status_component.has_status(CONE_SLOW) and entered.has(behind), "")
	_check("...and no longer applies to the one in front", not inside.status_component.has_status(CONE_SLOW), "")

	# The zone never outlives an interrupted cast.
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.1
	stun.stuns = true
	hero.status_component.apply(stun)
	await _physics_frames(2)
	_check("interrupting the cast ends its zone", not is_instance_valid(zone) or zone.is_queued_for_deletion(), "")
	_check("zone end removes its while-inside status", not behind.status_component.has_status(CONE_SLOW), "")
	_check("zone signals exit on end", exited.has(behind), "")

	# Full duration: ends with the cast.
	ult.reset_cooldown()
	await _seconds(0.2)
	hero.request_slot(&"ultimate", Vector2(-300, 0))
	await _seconds(0.3)
	var zone2 := ult.zone
	await _seconds(4.2)
	_check("zone ends when the channel ends", not is_instance_valid(zone2), "")
	inside.queue_free()
	behind.queue_free()


func _test_cooldown_api() -> void:
	var ability := hero.get_ability(&"cc")
	ability.cooldown_remaining = 5.0
	ability.reduce_cooldown(2.0)
	_check("reduce_cooldown", is_equal_approx(ability.cooldown_remaining, 3.0), str(ability.cooldown_remaining))
	var finished := [0]
	ability.cooldown_finished.connect(func(): finished[0] += 1)
	ability.reduce_cooldown(10.0)
	_check("reducing past zero finishes the cooldown", ability.is_ready() and finished[0] == 1, "")
	ability.cooldown_remaining = 4.0
	ability.reset_cooldown()
	_check("reset_cooldown", ability.is_ready() and finished[0] == 2, "")


# --- Helpers ------------------------------------------------------------------

# AI-style "hold the trigger": request every physics tick for `seconds`.
func _hold(h: Hero, slot: StringName, seconds: float) -> void:
	var ticks := roundi(seconds * Engine.physics_ticks_per_second)
	for i in ticks:
		h.request_slot(slot, h.aim_point)
		await get_tree().physics_frame


func _fire_until_empty(h: Hero, slot: StringName, timeout: float) -> void:
	var gun := h.get_ranged_ability(slot)
	var ticks := roundi(timeout * Engine.physics_ticks_per_second)
	for i in ticks:
		if gun.get_ammo() == 0:
			return
		h.request_slot(slot, h.aim_point)
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
