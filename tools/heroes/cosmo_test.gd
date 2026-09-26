extends Node2D

# Headless checks for Cosmo's kit.
#
#   godot --headless res://tools/heroes/cosmo_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const COSMO := "res://heroes/cosmo/cosmo_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"
const HARNESS := preload("res://tools/heroes/dps_harness.gd")

var failures := 0
var cosmo: Hero
var cues: Array = []
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	await _test_moons_by_level()
	cosmo = _spawn_cosmo(1)
	await _physics_frames(3)
	_test_assembled()
	await _test_waxing_and_regen()
	await _test_crescent()
	await _test_tide()
	await _test_new_moon()
	await _test_starfall()
	await _test_dps_targets()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, cosmo.get_ability(slot) != null, "")
	_check("definition validates", cosmo.definition.validate().is_empty(), "\n".join(cosmo.definition.validate()))
	_check("title Moon Witch, role Carry", cosmo.definition.title == "Moon Witch"
		and cosmo.definition.get_role_name() == "Carry", "")
	_check("the match caps at level 10 (her data is built for 1-10)", GameRules.current().max_level == 10, "")
	var stats := cosmo.definition.stats
	_check("Magic is back-loaded (steeper after level 5 than before)",
		stats.value_at(StatBlock.MAGIC, 10) - stats.value_at(StatBlock.MAGIC, 5)
			> 3.0 * (stats.value_at(StatBlock.MAGIC, 5) - stats.value_at(StatBlock.MAGIC, 1)),
		"L1 %.0f  L5 %.0f  L10 %.0f" % [stats.value_at(StatBlock.MAGIC, 1), stats.value_at(StatBlock.MAGIC, 5),
			stats.value_at(StatBlock.MAGIC, 10)])
	_check("the New Moon blink is the generic dash (data only)", cosmo.get_ability(&"movement").get_script() == ChargeAbility, "")


# --- Waxing Moon ----------------------------------------------------------------

func _test_moons_by_level() -> void:
	var counts := []
	for level in range(1, 11):
		var c := _spawn_cosmo(level)
		await _physics_frames(1)
		counts.append(c.get_ranged_ability().get_max_ammo())
		c.queue_free()
	await _physics_frames(1)
	_check("4 base moons, +1 at levels 3, 5, 7 and 10", counts == [4, 4, 5, 5, 6, 6, 7, 7, 7, 8], str(counts))


func _test_waxing_and_regen() -> void:
	var passive = cosmo.get_ability(&"passive")
	var gun := cosmo.get_ranged_ability()
	var waxed := []
	passive.moon_waxed.connect(func(n): waxed.append(n))
	cues.clear()
	_check("she starts with 4 moons", gun.get_max_ammo() == 4 and gun.get_ammo() == 4, str(gun.get_max_ammo()))
	cosmo.stats_component.set_level(2)
	_check("no new moon before a breakpoint", waxed.is_empty() and gun.get_max_ammo() == 4, "")
	cosmo.stats_component.set_level(3)
	_check("leveling to a breakpoint adds a moon", gun.get_max_ammo() == 5 and waxed == [5], str(waxed))
	_check("...filled", gun.get_ammo() == 5, str(gun.get_ammo()))
	_check("...with the cosmo_wax cue", _cue_count(&"cosmo_wax") == 1, "")
	_check("regen speeds up as she waxes (regen_interval_by_moons)", is_equal_approx(gun.get_regen_interval(), 2.45), "")
	_check("pips show moons", passive.get_hud_pips() == Vector2i(5, 5), str(passive.get_hud_pips()))

	# Shots leave from the orbit, and fast: the whole orbit in half a second.
	var at := cosmo.global_position + Vector2(600, 0)
	_aim(at)
	cues.clear()
	cosmo.request_slot(&"primary", at)
	await _physics_frames(4)
	var fires := _cue_contexts(&"moonshot_fire")
	var launch_distance: float = (fires[0].position as Vector2).distance_to(cosmo.global_position) if not fires.is_empty() else 0.0
	_check("a moon launches from its place in the orbit", absf(launch_distance - 78.0) < 2.0, "%.1f px" % launch_distance)
	for i in 4:
		await _seconds(0.1)
		cosmo.request_slot(&"primary", at)
	await _seconds(0.05)
	_check("all 5 moons fired within half a second", gun.get_ammo() == 0 and _cue_count(&"moonshot_fire") == 5,
		"%d left, %d fired" % [gun.get_ammo(), _cue_count(&"moonshot_fire")])
	_check("R does nothing for a REGEN gun", not cosmo.reload() and not gun.is_reloading(), "")
	await _seconds(2.0)
	_check("one moon back after regen_interval (counted from the first shot)", gun.get_ammo() == 1, str(gun.get_ammo()))
	cosmo.request_slot(&"primary", at)    # fire it straight away: regen keeps going
	await _seconds(0.1)
	_check("...firing it again", gun.get_ammo() == 0, "")
	await _seconds(2.4)
	_check("regen refills one at a time while firing", gun.get_ammo() == 1, str(gun.get_ammo()))
	await _seconds(2.5)
	_check("...one per regen_interval", gun.get_ammo() == 2, str(gun.get_ammo()))

	# Moons pierce.
	_reset(Vector2(0, -6000), 1)
	await _physics_frames(2)
	var line := [_dummy(Vector2(200, -6000)), _dummy(Vector2(300, -6000)), _dummy(Vector2(400, -6000))]
	await _physics_frames(2)
	hits_log.clear()
	_aim(Vector2(700, -6000))
	cosmo.request_slot(&"primary", Vector2(700, -6000))
	await _seconds(0.6)
	var pierced := hits_log.filter(func(i): return i.label == &"moonshot" and line.has(i.target))
	_check("a moon pierces every enemy in its path", pierced.size() == 3, "%d hits" % pierced.size())
	_clear()

	# A full volley converges on the cursor: every moon hits one target.
	_reset(Vector2(0, -6000), 10)
	await _physics_frames(2)
	var single := _dummy(Vector2(400, -6000))
	await _physics_frames(2)
	hits_log.clear()
	_aim(single.global_position)
	for i in 8:
		cosmo.request_slot(&"primary", single.global_position)
		await _seconds(0.1)
	await _seconds(0.5)
	var volley := hits_log.filter(func(i): return i.label == &"moonshot" and i.target == single)
	_check("all 8 moons of a volley converge on one target", volley.size() == 8, "%d hits" % volley.size())
	_clear()


# --- Crescent -------------------------------------------------------------------

func _test_crescent() -> void:
	_reset(Vector2(0, 2000), 10)
	var target := _dummy(Vector2(300, 2000))
	await _physics_frames(2)
	hits_log.clear()
	cues.clear()
	_aim(target.global_position)
	cosmo.request_slot(&"ability_1", target.global_position)
	await _seconds(0.45)
	var after_out := target.status_component.get_multiplier(StatusEffect.DAMAGE_TAKEN_MAGIC)
	_check("one pass: Moonlit at moonlit_amp (1.2)", is_equal_approx(after_out, 1.2), "%.3f" % after_out)
	_check("the Moonlit marker shows", target.visuals._status_vfx.has(&"cosmo_moonlit"), "")
	await _seconds(0.9)
	var passes := hits_log.filter(func(i): return i.target == target and i.label == &"crescent")
	_check("Crescent hits going out and coming back", passes.size() == 2 and not passes[0].has_tag(Projectile.TAG_RETURN)
		and passes[1].has_tag(Projectile.TAG_RETURN), str(passes.size()))
	var full := target.status_component.get_multiplier(StatusEffect.DAMAGE_TAKEN_MAGIC)
	_check("both passes: Moonlit at moonlit_amp_full (1.35)", is_equal_approx(full, 1.35), "%.3f" % full)
	if passes.size() == 2:
		_check("the return pass already takes the first pass' amp", is_equal_approx(passes[1].final_amount,
			passes[0].final_amount * 1.2), "%.1f vs %.1f" % [passes[1].final_amount, passes[0].final_amount])
	hits_log.clear()
	var magic := DamageInfo.create(100.0, cosmo, DamageInfo.Type.MAGIC)
	target.hurtbox.take_hit(magic)
	var weapon := DamageInfo.create(100.0, cosmo, DamageInfo.Type.PHYSICAL)
	target.hurtbox.take_hit(weapon)
	_check("Moonlit amplifies magic damage", is_equal_approx(magic.final_amount, 135.0), "%.1f" % magic.final_amount)
	_check("...but not weapon damage", is_equal_approx(weapon.final_amount, 100.0), "%.1f" % weapon.final_amount)

	# Camp clearing: it pierces a pack.
	var pack: Array[TrainingDummy] = [_dummy(Vector2(200, 2300)), _dummy(Vector2(320, 2300)), _dummy(Vector2(440, 2300))]
	await _physics_frames(2)
	cosmo.get_ability(&"ability_1").reset_cooldown()
	await _seconds(1.0)
	hits_log.clear()
	cosmo.global_position = Vector2(0, 2300)
	_aim(Vector2(600, 2300))
	cosmo.request_slot(&"ability_1", Vector2(600, 2300))
	await _seconds(1.4)
	var pack_hits := hits_log.filter(func(i): return pack.has(i.target) and i.label == &"crescent")
	_check("it pierces a whole camp, both ways", pack_hits.size() == 6, "%d hits" % pack_hits.size())
	_clear()
	await _physics_frames(2)


# --- Tide -----------------------------------------------------------------------

func _test_tide() -> void:
	_reset(Vector2(0, 4000), 10)
	var center := Vector2(500, 4000)
	var idle := _dummy(center + Vector2(170, 0))
	idle.return_to_anchor = false
	var struggler := _dummy(center + Vector2(-120, 0))
	struggler.anchor = center + Vector2(-2000, 0)    # keeps walking away
	await _physics_frames(2)
	cues.clear()
	hits_log.clear()
	_aim(center)
	cosmo.request_slot(&"cc", center)
	await _seconds(0.25)
	var tide = cosmo.get_ability(&"cc")
	_check("Tide lands at the cursor", tide.get_center().distance_to(center) < 1.0 and _cue_count(&"tide_start") == 1, "")
	await _seconds(0.7)
	_check("enemies inside are pulled toward the centre", idle.global_position.distance_to(center) < 120.0,
		"%.0f px" % idle.global_position.distance_to(center))
	var moved_out := struggler.global_position.distance_to(center) - 120.0
	_check("...but can slowly struggle out", moved_out > 10.0 and moved_out < 0.95 * 220.0 * 0.7,
		"%.0f px in 0.7 s" % moved_out)
	await _seconds(0.6)
	var magic := cosmo.stats_component.get_magic()
	_check("then it detonates for AoE magic damage", _sum(idle, &"tide") > 0.0
		and is_equal_approx(_sum(idle, &"tide"), 60.0 + 0.9 * magic) and _cue_count(&"tide_detonate") == 1,
		"%.1f vs %.1f" % [_sum(idle, &"tide"), 60.0 + 0.9 * magic])
	_check("...and the pull ends", not idle.status_component.has_status(&"cosmo_tide_pull"), "")

	tide.reset_cooldown()
	_aim(cosmo.global_position + Vector2(3000, 0))
	cosmo.request_slot(&"cc", cosmo.global_position + Vector2(3000, 0))
	await _physics_frames(2)
	_check("a far cursor is clamped to cast_range", absf(tide.get_center().distance_to(cosmo.global_position) - 800.0) < 1.0, "")
	await _seconds(1.5)
	_clear()
	await _physics_frames(2)


# --- New Moon -------------------------------------------------------------------

func _test_new_moon() -> void:
	_reset(Vector2(0, 6000), 10)
	var start := cosmo.global_position
	_aim(start + Vector2(300, 0))
	cues.clear()
	cosmo.request_slot(&"movement", start + Vector2(300, 0))
	await _physics_frames(4)
	_check("New Moon blinks to the cursor", cosmo.global_position.distance_to(start + Vector2(300, 0)) < 6.0,
		str(cosmo.global_position))
	_check("...and she's untargetable", not cosmo.hurtbox.is_valid_target(), "")
	var hp := cosmo.health_component.current_health
	cosmo.hurtbox.take_hit(DamageInfo.create(100.0, null, DamageInfo.Type.TRUE))
	_check("...hits pass through her", cosmo.health_component.current_health == hp, "")
	_check("...a faded silhouette, not invisible", cosmo.visuals.modulate.a > 0.1 and cosmo.visuals.modulate.a < 0.5,
		str(cosmo.visuals.modulate.a))
	await _seconds(0.7)
	cosmo.hurtbox.take_hit(DamageInfo.create(100.0, null, DamageInfo.Type.TRUE))
	_check("the vanish ends after vanish_time", cosmo.health_component.current_health < hp, "")

	# Walls clamp it.
	var wall: Node2D = load(WALL).instantiate()
	wall.position = start + Vector2(500, 0)
	add_child(wall)
	spawned.append(wall)
	cosmo.global_position = start
	cosmo.get_ability(&"movement").reset_cooldown()
	await _physics_frames(2)
	_aim(start + Vector2(1000, 0))
	cosmo.request_slot(&"movement", start + Vector2(1000, 0))
	await _physics_frames(4)
	var x := cosmo.global_position.x - start.x
	_check("it can't pass walls: clamped at the last valid point", x > 350.0 and x < 400.0, "%.0f" % x)
	_clear()
	await _physics_frames(2)


# --- Starfall -------------------------------------------------------------------

func _test_starfall() -> void:
	_reset(Vector2(0, 8000), 10)
	var starfall = cosmo.get_ability(&"ultimate")
	var center := cosmo.global_position
	cues.clear()
	cosmo.request_slot(&"ultimate", center)
	await _seconds(0.3)
	_check("Starfall channels", starfall.is_channeling() and _cue_count(&"starfall_start") == 1, "")
	cosmo.move_direction = Vector2.RIGHT
	await _seconds(0.5)
	cosmo.move_direction = Vector2.ZERO
	_check("she's rooted (can't walk)", cosmo.global_position.distance_to(center) < 2.0, str(cosmo.global_position))
	var physical := DamageInfo.create(100.0, null, DamageInfo.Type.PHYSICAL)
	cosmo.hurtbox.take_hit(physical)
	var magic := DamageInfo.create(100.0, null, DamageInfo.Type.MAGIC)
	cosmo.hurtbox.take_hit(magic)
	var armor_mult := GameRules.current().resistance_multiplier(cosmo.stats_component.get_stat(StatBlock.ARMOR))
	var mr_mult := GameRules.current().resistance_multiplier(cosmo.stats_component.get_stat(StatBlock.MAGIC_RESIST))
	_check("weapon damage to her is halved (starfall_weapon_resist)", is_equal_approx(physical.final_amount, 100.0 * armor_mult * 0.5),
		"%.1f" % physical.final_amount)
	_check("magic damage is not reduced", is_equal_approx(magic.final_amount, 100.0 * mr_mult), "%.1f" % magic.final_amount)
	await _seconds(3.2)
	_check("the channel ends on its own", not starfall.is_channeling() and _cue_count(&"starfall_end") == 1, "")
	await _seconds(0.5)    # meteors already warned still land after the channel
	var impacts := _cue_contexts(&"starfall_impact").map(func(c): return c.position)
	var storm_radius: float = starfall.data.get_value(&"storm_radius", cosmo.stats_component)
	var outside := impacts.filter(func(p): return p.distance_to(center) > storm_radius)
	_check("meteors land only inside storm_radius", not impacts.is_empty() and outside.is_empty(),
		"%d impacts, %d outside" % [impacts.size(), outside.size()])
	# 8 moons (+4 over base): 5.5 meteors/s over a 3.5 s channel.
	_check("8 moons: ~5.5 meteors per second", impacts.size() >= 17 and impacts.size() <= 21, str(impacts.size()))
	_check("each meteor is warned by a shadow first", _cue_count(&"starfall_meteor_warn") == impacts.size(),
		"%d warns, %d impacts" % [_cue_count(&"starfall_meteor_warn"), impacts.size()])
	var physical_after := DamageInfo.create(100.0, null, DamageInfo.Type.PHYSICAL)
	cosmo.hurtbox.take_hit(physical_after)
	_check("the resist ends with the channel", is_equal_approx(physical_after.final_amount, 100.0 * armor_mult), "")

	# Fewer moons, fewer meteors.
	_reset(Vector2(0, 8000), 1)
	await _physics_frames(1)
	cues.clear()
	cosmo.request_slot(&"ultimate", center)
	await _seconds(4.0)
	var few := _cue_count(&"starfall_impact")
	_check("base 4 moons: ~3.5 meteors per second", few >= 10 and few <= 14, str(few))
	starfall.data.scale_with_moons = false
	_reset(Vector2(0, 8000), 1)
	cues.clear()
	cosmo.request_slot(&"ultimate", center)
	await _seconds(4.0)
	_check("scale_with_moons off: meteors_per_second (4)", _cue_count(&"starfall_impact") >= 12
		and _cue_count(&"starfall_impact") <= 16, str(_cue_count(&"starfall_impact")))
	starfall.reset_data()

	# Moonlit targets take the amp from meteors.
	_reset(Vector2(0, 8000), 10)
	var marked := _dummy(center + Vector2(40, 0))
	await _physics_frames(2)
	var moonlit: StatusEffect = load("res://heroes/cosmo/data/cosmo_moonlit.tres")
	marked.status_component.apply(moonlit, cosmo, Vector2.ZERO, 0.35)
	starfall.data.values[&"storm_radius"].base = 60.0    # every meteor lands on it
	hits_log.clear()
	cosmo.request_slot(&"ultimate", center)
	await _seconds(1.0)
	var meteor_hits := hits_log.filter(func(i): return i.target == marked and i.label == &"starfall")
	var base: float = starfall.data.damage.evaluate(cosmo.stats_component)
	_check("Moonlit targets take the amp from meteors", not meteor_hits.is_empty()
		and is_equal_approx(meteor_hits[0].final_amount, base * 1.35), "%.1f vs %.1f" % [
			meteor_hits[0].final_amount if not meteor_hits.is_empty() else 0.0, base * 1.35])
	starfall.end_channel(false)
	starfall.reset_data()
	_clear()

	# Interrupts, each per its flag.
	for case in ["stun", "silence", "recast", "new_moon"]:
		_reset(Vector2(0, 9000), 10)
		await _physics_frames(1)
		cosmo.request_slot(&"ultimate", cosmo.global_position)
		await _seconds(0.3)
		await _interrupt(case)
		await _physics_frames(3)
		_check("%s ends the channel" % case, not starfall.is_channeling(), "")
		starfall.end_channel(false)
	# With its flag off, recasting and New Moon don't.
	starfall.data.ends_on_recast = false
	starfall.data.ends_on_movement = false
	for case in ["recast", "new_moon"]:
		_reset(Vector2(0, 9000), 10)
		await _physics_frames(1)
		cosmo.request_slot(&"ultimate", cosmo.global_position)
		await _seconds(0.3)
		await _interrupt(case)
		await _physics_frames(3)
		_check("%s with its flag off keeps channelling" % case, starfall.is_channeling(), "")
		starfall.end_channel(false)
	starfall.reset_data()
	await _seconds(0.3)


func _interrupt(case: String) -> void:
	match case:
		"stun":
			cosmo.status_component.apply(_status(&"test_stun", "stuns"))
		"silence":
			cosmo.status_component.apply(_status(&"test_silence", "silences"))
		"recast":
			cosmo.request_slot(&"ultimate", cosmo.global_position)
		"new_moon":
			_aim(cosmo.global_position + Vector2(300, 0))
			cosmo.request_slot(&"movement", cosmo.global_position + Vector2(300, 0))


# --- DPS targets ----------------------------------------------------------------

func _test_dps_targets() -> void:
	cosmo.queue_free()
	await _physics_frames(2)
	var harness: Node = HARNESS.new()
	add_child(harness)
	var sustained := {}
	var burst := {}
	for hero in ["cosmo", "jose", "avery", "melody"]:
		var path: String = {"cosmo": COSMO, "jose": "res://heroes/jose/jose_hero.tscn",
			"avery": "res://heroes/avery/avery.tscn", "melody": "res://heroes/melody/melody_hero.tscn"}[hero]
		sustained[hero] = await harness.sustained(path, 1)
		burst[hero] = await harness.burst(path, 10)
	print("  L1 sustained DPS: %s" % str(sustained))
	print("  L10 3 s burst:    %s" % str(burst))
	_check("level 1: her sustained DPS is the lowest carry's (below Jose and Avery)",
		sustained.cosmo < sustained.jose and sustained.cosmo < sustained.avery, "")
	_check("level 10: her burst is the roster's highest",
		burst.cosmo > burst.jose and burst.cosmo > burst.avery and burst.cosmo > burst.melody, "")


# --- Helpers ------------------------------------------------------------------

func _spawn_cosmo(level: int) -> Hero:
	var c: Hero = load(COSMO).instantiate()
	c.team = &"a"
	c.start_level = level
	add_child(c)
	c.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	return c


func _reset(at: Vector2, level: int) -> void:
	cosmo.ability_controller.interrupt()
	var starfall = cosmo.get_ability(&"ultimate")
	starfall.end_channel(false)
	cosmo.status_component.clear()
	cosmo.movement_component.stop_forced_move()
	cosmo.stats_component.set_level(level)
	cosmo.global_position = at
	cosmo.velocity = Vector2.ZERO
	cosmo.move_direction = Vector2.ZERO
	cosmo.health_component.reset()
	for ability in cosmo.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	cosmo.get_ranged_ability().reload_instantly()
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	cosmo.aim_point = at
	cosmo.aim_direction = (at - cosmo.global_position).normalized()


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


func _sum(target: Node, label: StringName) -> float:
	var total := 0.0
	for info in hits_log:
		if info.target == target and info.label == label:
			total += info.final_amount
	return total


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
