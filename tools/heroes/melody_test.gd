extends Node2D

# Headless checks for Melody's kit.
#
#   godot --headless res://tools/heroes/melody_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const MELODY := "res://heroes/melody/melody_hero.tscn"
const ALLY_HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"

var failures := 0
var melody: Hero
var key    # melody_key.gd (her passive)
var cues: Array = []
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	melody = load(MELODY).instantiate()
	melody.team = &"a"
	add_child(melody)
	melody.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	await _physics_frames(3)
	key = melody.get_ability(&"passive")

	_test_assembled()
	await _test_performance()
	await _test_unwind()
	await _test_encore_rule()
	await _test_heavy_notes()
	await _test_wind_up_key()
	await _test_wind_up_dash()
	await _test_grand_march()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, melody.get_ability(slot) != null, "")
	_check("definition validates", melody.definition.validate().is_empty(), "\n".join(melody.definition.validate()))
	_check("title Living Doll, role Flex", melody.definition.title == "Living Doll"
		and melody.definition.get_role_name() == "Flex", "")
	_check("Magic is her main stat", melody.stats_component.get_magic() > melody.stats_component.get_weapon() * 2.0, "")
	_check("the key starts unwound, pips on the bar", key.turns == 0 and key.get_hud_pips() == Vector2i(0, 4), "")
	_check("the passive never casts", not melody.request_slot(&"passive", Vector2.ZERO), "")


# --- Performance ------------------------------------------------------------

func _test_performance() -> void:
	_reset(Vector2.ZERO)
	var near_ally := _dummy(Vector2(200, 0))
	near_ally.team = &"a"
	var far_ally := _dummy(Vector2(700, 0))
	far_ally.team = &"a"
	var enemy := _dummy(Vector2(150, 150))
	await _physics_frames(2)
	cues.clear()
	_check("Performance starts", melody.request_slot(&"cc", Vector2.ZERO), "")
	var performer := RhythmPerformer.find_on(melody)
	var phrase := performer.phrase
	await _press_at(performer, phrase.get_beat_time(0))          # PERFECT
	await _press_at(performer, phrase.get_beat_time(1) + 0.08)   # GOOD
	# note 2: MISS
	await _press_at(performer, phrase.get_beat_time(3))          # PERFECT
	await _physics_frames(2)
	_check("PERFECT/GOOD wind the key, MISS doesn't", key.turns == 3, str(key.turns))
	_check("perfects counted toward encore strength", key.perfects == 2, str(key.perfects))
	_check("the miss plays the sour honk cue", _cue_count(&"performance_note_miss") == 1, "")
	var pitches := cues.filter(func(c): return str(c[0]).begins_with("performance_note_")).map(func(c): return c[1].pitch)
	_check("notes are pitched as a melody", pitches.size() == 4 and pitches[0] != pitches[3], str(pitches))
	var full_shield := 30.0 + 0.35 * melody.stats_component.get_magic()
	_check("perfect pulse shields allies in radius", is_equal_approx(near_ally.status_component.get_shield_total(), full_shield),
		"%.1f vs %.1f" % [near_ally.status_component.get_shield_total(), full_shield])
	_check("...and Melody herself", melody.status_component.get_shield_total() > 0.0, "")
	_check("no shield outside the radius", far_ally.status_component.get_shield_total() == 0.0, "")
	_check("no shield on enemies", enemy.status_component.get_shield_total() == 0.0, "")
	_check("one pulse per scored note", _cue_count(&"performance_pulse") == 3, str(_cue_count(&"performance_pulse")))

	# A GOOD pulses a weaker shield.
	near_ally.status_component.clear()
	melody.get_ability(&"cc").reset_cooldown()
	melody.request_slot(&"cc", Vector2.ZERO)
	await _press_at(performer, phrase.get_beat_time(0) + 0.08)
	_check("a GOOD pulse is half strength", is_equal_approx(near_ally.status_component.get_shield_total(), full_shield * 0.5),
		"%.1f" % near_ally.status_component.get_shield_total())

	# The cap: extra hits still pulse.
	await _wait_phrase(performer)
	key.set_turns(3)
	cues.clear()
	melody.get_ability(&"cc").reset_cooldown()
	melody.request_slot(&"cc", Vector2.ZERO)
	for i in 4:
		await _press_at(performer, phrase.get_beat_time(i))
	await _physics_frames(2)
	_check("turns cap at max_turns", key.turns == 4, str(key.turns))
	_check("hits past the cap still pulse shields", _cue_count(&"performance_pulse") == 4, "")
	_check("Performance never spends the key", key.turns == 4, "")
	_clear()
	await _physics_frames(2)


func _test_unwind() -> void:
	# Faster timings on her runtime copy of the data, same rule.
	key.data.values[&"unwind_delay"].base = 1.0
	key.data.values[&"unwind_interval"].base = 0.5
	key.set_turns(4)
	key.note_scored(false, false)    # resets the clock
	await _seconds(1.2)
	_check("no unwinding before unwind_delay", key.turns == 4, str(key.turns))
	await _seconds(0.4)
	_check("one turn lost after delay + interval", key.turns == 3, str(key.turns))
	await _seconds(0.5)
	_check("...then one per interval", key.turns == 2, str(key.turns))
	_check("the key ticks back (unwind cue)", _cue_count(&"the_key_unwind") >= 2, "")
	key.note_scored(true, false)
	await _seconds(1.2)
	_check("scoring a note resets the unwind clock", key.turns == 2, str(key.turns))
	key.reset_data()
	key.set_turns(0)


# --- The encore rule --------------------------------------------------------

func _test_encore_rule() -> void:
	_reset(Vector2(0, -2000))
	var ally := _ally_hero(Vector2(300, -2000))
	await _physics_frames(3)
	var primary = melody.get_ability(&"primary")
	var triggered := []
	key.encore_triggered.connect(func(id, s): triggered.append([id, s]))

	# 2 turns: everything casts normally and keeps the turns.
	key.set_turns(2)
	melody.request_slot(&"primary", melody.global_position + Vector2(400, 0))
	await _physics_frames(1)
	_check("at 2 turns the primary casts normally", not primary.is_chord_pending() and key.turns == 2, "")
	await _seconds(1.0)
	await _crank_and_release(ally, 0.3)
	await _seconds(0.6)
	_check("...RMB casts normally and keeps them", key.turns == 2 and triggered.is_empty(), str(key.turns))
	melody.request_slot(&"movement", melody.global_position + Vector2(0, 300))
	await _physics_frames(2)
	_check("...Shift charges normally (no encore)", melody.get_ability(&"movement").is_charging() and key.turns == 2, "")
	melody.release_slot(&"movement", melody.global_position + Vector2(0, 300))
	await _seconds(0.6)
	_check("...and keeps the turns", key.turns == 2, str(key.turns))

	# 3 turns: the next primary is the encore and empties the key.
	await _seconds(0.5)
	key.set_turns(3)
	key.perfects = 3
	var fired: Array[ProjectileData] = []
	var on_child := func(n): if n is Projectile: fired.append(n.data)
	child_entered_tree.connect(on_child)
	melody.request_slot(&"primary", melody.global_position + Vector2(400, 0))
	await _physics_frames(10)
	child_entered_tree.disconnect(on_child)
	_check("at 3 turns the primary casts its encore (Chord)", not fired.is_empty()
		and fired[0] == (primary.data as MelodyHeavyNotesData).chord_projectile, "")
	_check("...and consumes ALL turns", key.turns == 0, str(key.turns))
	_check("encore_triggered(ability_id, strength = 1 + 3 x 0.1)", triggered.size() == 1
		and triggered[0][0] == &"heavy_notes" and is_equal_approx(triggered[0][1], 1.3), str(triggered))
	_check("the next shot is normal again", not primary.is_chord_pending(), "")
	await _seconds(1.0)
	_check("after the Chord she can act again", not melody.ability_controller.is_busy()
		and melody.request_slot(&"primary", melody.global_position + Vector2(400, 0)), "")

	# The ultimate never consumes turns.
	key.set_turns(3)
	melody.request_slot(&"ultimate", melody.global_position)
	await _seconds(0.3)
	_check("the ultimate never spends the key", key.turns == 3, str(key.turns))
	melody.get_ability(&"ultimate").end_march()
	key.set_turns(0)
	_clear()
	await _physics_frames(2)


# --- Heavy Notes ------------------------------------------------------------

func _test_heavy_notes() -> void:
	_reset(Vector2(0, 2000))
	var at_range := _dummy(Vector2(835, 2100))     # off the flight line, in the blast at max range
	var first := _dummy(Vector2(-300, 2000))
	var beside := _dummy(Vector2(-330, 2090))
	await _physics_frames(2)
	var damage := 26.0 + 0.45 * melody.stats_component.get_magic()
	await _seconds(1.0)    # the previous test's shot interval
	hits_log.clear()
	_aim(Vector2(1000, 2000))
	melody.request_slot(&"primary", Vector2(1000, 2000))
	await _seconds(1.5)
	_check("a note explodes at max distance", is_equal_approx(_sum(at_range, &"heavy_notes"), damage),
		"%.1f vs %.1f" % [_sum(at_range, &"heavy_notes"), damage])
	hits_log.clear()
	_aim(Vector2(-1000, 2000))    # notes don't lock aim in their windup
	melody.request_slot(&"primary", Vector2(-1000, 2000))
	await _seconds(0.8)
	_check("a note explodes on the first enemy hit", is_equal_approx(_sum(first, &"heavy_notes"), damage)
		and is_equal_approx(_sum(beside, &"heavy_notes"), damage),
		"%.1f / %.1f" % [_sum(first, &"heavy_notes"), _sum(beside, &"heavy_notes")])
	_check("heavy notes deal magic damage", hits_log.all(func(i): return i.type == DamageInfo.Type.MAGIC), "")

	# The Chord: splits into 3 notes, each encore_value(chord_note_damage).
	await _seconds(1.0)
	var in_fan := _dummy(Vector2(1100, 2010))    # on the middle split note's path
	await _physics_frames(2)
	key.set_turns(4)
	_aim(Vector2(1000, 2000))
	var children: Array[Projectile] = []
	var on_child := func(n): if n is Projectile: children.append(n)
	child_entered_tree.connect(on_child)
	hits_log.clear()
	melody.request_slot(&"primary", Vector2(1000, 2000))
	await _seconds(2.0)
	child_entered_tree.disconnect(on_child)
	_check("the Chord splits into 3 notes", children.size() == 4, "%d projectiles" % children.size())
	var chord_hits := hits_log.filter(func(i): return i.label == &"chord")
	_check("split notes deal chord_note_damage (base x strength)", not chord_hits.is_empty()
		and is_equal_approx(chord_hits[0].final_amount, 30.0) and chord_hits.any(func(i): return i.target == in_fan),
		"%d hits" % chord_hits.size())
	_clear()
	await _physics_frames(2)


# --- Wind-Up Key ------------------------------------------------------------

func _test_wind_up_key() -> void:
	_reset(Vector2(0, 4000))
	var ally := _ally_hero(Vector2(300, 4000))
	var enemy := _dummy(Vector2(-300, 4000))
	await _physics_frames(3)
	var wind = melody.get_ability(&"ability_1")
	cues.clear()
	_check("targeting an enemy fails (allies only), no cooldown",
		not melody.request_slot(&"ability_1", enemy.global_position) and wind.is_ready(), "")
	_check("targeting herself fails (allow_self off)",
		not melody.request_slot(&"ability_1", melody.global_position) and wind.is_ready(), "")

	# Half crank.
	var base_speed := ally.movement_component.get_move_speed()
	await _crank_and_release(ally, 0.5)
	var ratio: float = wind.get_charge_ratio()
	await _seconds(0.1)
	var strength := lerpf(0.35, 1.0, ratio)
	var speed_mult := ally.status_component.get_multiplier(StatusEffect.MOVE_SPEED)
	_check("release winds the ally", ally.status_component.has_status_from(&"melody_wound_up", melody), "")
	_check("charge scales the buff (move 1 + 0.4 x strength)", absf(speed_mult - (1.0 + 0.4 * strength)) < 0.02,
		"%.3f vs %.3f" % [speed_mult, 1.0 + 0.4 * strength])
	_check("...and fire rate (1 + 0.5 x strength)", absf(ally.status_component.get_multiplier(StatusEffect.FIRE_RATE)
		- (1.0 + 0.5 * strength)) < 0.02, "")
	_check("the ally shows a key in its back", ally.visuals._status_vfx.has(&"melody_wound_up"), "")
	await _seconds(2.0)
	var half := ally.status_component.get_multiplier(StatusEffect.MOVE_SPEED)
	_check("the wind-up fades (about half left at 2 of 4 s)", absf(half - (1.0 + 0.4 * strength * 0.5)) < 0.03,
		"%.3f" % half)
	await _seconds(2.1)
	_check("...to exactly 1.0 at the end", ally.status_component.get_multiplier(StatusEffect.MOVE_SPEED) == 1.0
		and ally.movement_component.get_move_speed() == base_speed, "")

	# A fuller crank winds harder.
	wind.reset_cooldown()
	await _crank_and_release(ally, 1.0)
	await _seconds(0.1)
	_check("a full crank gives the full buff", absf(ally.status_component.get_multiplier(StatusEffect.MOVE_SPEED) - 1.4) < 0.02, "")
	ally.status_component.clear()

	# Tether: walking away mid-crank cancels it (no cooldown).
	wind.reset_cooldown()
	melody.request_slot(&"ability_1", ally.global_position)
	await _seconds(0.2)
	melody.global_position = ally.global_position + Vector2(-800, 0)
	await _physics_frames(2)
	_check("the tether breaks when she strays too far", not wind.is_casting() and wind.is_ready()
		and _cue_count(&"wind_up_key_tether_break") == 1, "")
	melody.global_position = Vector2(0, 4000)
	await _physics_frames(1)

	# Encore (Master Key): jumps to allies near the target.
	var near := _dummy(Vector2(450, 4150))
	near.team = &"a"
	var far := _dummy(Vector2(900, 4000))
	far.team = &"a"
	await _physics_frames(2)
	key.set_turns(3)
	await _crank_and_release(ally, 0.6)
	await _seconds(0.1)
	_check("Master Key: the target is wound", ally.status_component.has_status(&"melody_wound_up"), "")
	_check("...and allies within master_key_radius", near.status_component.has_status(&"melody_wound_up"), "")
	_check("...not ones farther away", not far.status_component.has_status(&"melody_wound_up"), "")
	_check("...nor Melody (allow_self off)", not melody.status_component.has_status(&"melody_wound_up"), "")
	_check("...and the key is spent", key.turns == 0 and _cue_count(&"wind_up_key_master_key") == 1, "")
	await _seconds(0.5)
	_check("after Master Key she can act again", not wind.is_casting() and not melody.ability_controller.is_busy()
		and melody.request_slot(&"primary", Vector2(600, 4000)), "")
	_clear()
	await _physics_frames(2)


# --- Wind-Up Dash -----------------------------------------------------------

func _test_wind_up_dash() -> void:
	var dash = melody.get_ability(&"movement")
	# Distance scales with the hold.
	var lengths := []
	for hold in [0.2, 0.8]:
		_reset(Vector2(0, 6000))
		await _physics_frames(2)
		var start := melody.global_position
		_aim(start + Vector2(500, 0))
		melody.request_slot(&"movement", start + Vector2(500, 0))
		await _seconds(hold)
		var ratio: float = dash.get_charge_ratio()
		melody.release_slot(&"movement", start + Vector2(500, 0))
		await _seconds(0.5)
		lengths.append([melody.global_position.x - start.x, lerpf(150.0, 450.0, ratio)])
	_check("dash distance scales with the hold", absf(lengths[0][0] - lengths[0][1]) < 15.0
		and absf(lengths[1][0] - lengths[1][1]) < 15.0 and lengths[1][0] > lengths[0][0] + 200.0, str(lengths))

	# The boop.
	_reset(Vector2(0, 6000))
	var target := _dummy(Vector2(200, 6000))
	target.return_to_anchor = false
	await _physics_frames(2)
	hits_log.clear()
	_aim(Vector2(600, 6000))
	melody.request_slot(&"movement", Vector2(600, 6000))
	await _seconds(0.8)
	melody.release_slot(&"movement", Vector2(600, 6000))
	await _seconds(0.6)
	var full := 60.0 + 0.6 * melody.stats_component.get_magic()
	_check("the bash hits for the charged damage", absf(_sum(target, &"wind_up_dash") - full) < 1.0,
		"%.1f vs %.1f" % [_sum(target, &"wind_up_dash"), full])
	_check("...and boops the enemy away", target.global_position.x > 330.0, str(target.global_position))
	_clear()
	await _physics_frames(2)

	# Encore (Pre-wound): instant, full distance, bounces off walls twice.
	_reset(Vector2(0, 8000))
	for x in [-250.0, 250.0]:
		var wall: Node2D = load(WALL).instantiate()
		wall.position = Vector2(x, 8000)
		add_child(wall)
		spawned.append(wall)
	await _physics_frames(3)
	key.set_turns(3)
	cues.clear()
	_aim(Vector2(600, 8000))
	melody.request_slot(&"movement", Vector2(600, 8000))
	await _physics_frames(1)
	_check("Pre-wound fires instantly (no hold)", not dash.is_charging() and dash.is_casting() and dash.is_prewound(), "")
	_check("...and spends the key", key.turns == 0, "")
	await _seconds(0.8)
	var bounces := _cue_count(&"wind_up_dash_bounce")
	_check("ricochets off walls twice (bounces = 2)", bounces == 2, str(bounces))
	# 136 right, 272 back left, 42 right again: ends ~94 px left of start.
	_check("the path reflects: right, left, right", absf(melody.global_position.x - (-94.0)) < 20.0,
		str(melody.global_position))
	await _seconds(0.3)
	_check("Pre-wound ends: she can act again (regression: stuck cast)", not dash.is_casting()
		and not melody.ability_controller.is_busy() and melody.request_slot(&"primary", Vector2(600, 8000)), "")
	_clear()
	await _physics_frames(2)

	# Pre-wound also bounces off an enemy, booping it once.
	_reset(Vector2(0, 10000))
	var bumper := _dummy(Vector2(250, 10000))
	bumper.return_to_anchor = false
	await _physics_frames(2)
	key.set_turns(3)
	cues.clear()
	hits_log.clear()
	_aim(Vector2(600, 10000))
	melody.request_slot(&"movement", Vector2(600, 10000))
	await _seconds(0.8)
	_check("Pre-wound ricochets off an enemy", _cue_count(&"wind_up_dash_bounce") >= 1 and melody.global_position.x < 150.0,
		str(melody.global_position))
	_check("...booping it exactly once", hits_log.filter(func(i): return i.target == bumper).size() == 1, "")
	_clear()
	await _physics_frames(2)


# --- Grand March ------------------------------------------------------------

func _test_grand_march() -> void:
	_reset(Vector2(0, 12000))
	var first := _ally_hero(Vector2(-150, 12000))
	var second := _ally_hero(Vector2(-150, 12150))
	var outsider := _ally_hero(Vector2(-900, 12000))
	var enemy := _dummy(Vector2(0, 12300))
	await _physics_frames(3)
	var march = melody.get_ability(&"ultimate")
	var base_speed := melody.movement_component.get_move_speed()
	cues.clear()
	melody.request_slot(&"ultimate", melody.global_position)
	await _seconds(0.25)
	_check("the march starts with allies in radius", march.is_marching() and march.followers.size() == 2
		and march.followers.has(first) and march.followers.has(second), str(march.followers.size()))
	_check("...not allies outside it, nor enemies", not outsider.status_component.has_status(&"melody_parade")
		and not enemy.status_component.has_status(&"melody_parade"), "")
	_check("Melody and the line get the speed buff", melody.movement_component.get_move_speed() > base_speed * 1.4
		and first.status_component.has_status(&"melody_march_speed"), "")
	_check("Performance is disabled during the march", not melody.request_slot(&"cc", melody.global_position), "")

	# Walk right, then down: the line follows her path around the corner.
	melody.move_direction = Vector2.RIGHT
	await _seconds(1.2)
	melody.move_direction = Vector2.DOWN
	await _seconds(0.6)
	var recorder := TrailRecorder.find_on(melody)
	var lead = march.followers[0]
	var back = march.followers[1]
	_check("allies line up behind her along her path",
		lead.global_position.distance_to(recorder.point_behind(110.0)) < 70.0
			and back.global_position.distance_to(recorder.point_behind(220.0)) < 70.0,
		"%.0f / %.0f px off" % [lead.global_position.distance_to(recorder.point_behind(110.0)),
			back.global_position.distance_to(recorder.point_behind(220.0))])
	_check("...and turn her corner", back.global_position.y < lead.global_position.y - 30.0,
		"lead %s back %s" % [lead.global_position, back.global_position])
	melody.move_direction = Vector2.ZERO

	# Walking into range late doesn't join.
	outsider.global_position = melody.global_position + Vector2(100, 0)
	await _physics_frames(3)
	_check("late arrivals don't auto-join", not outsider.status_component.has_status(&"melody_parade"), "")

	# March notes: a perfect extends and shields the band; no turns.
	var performer := RhythmPerformer.find_on(melody)
	var turns_before: int = key.turns
	var index := performer.get_next_index()
	var before: float = march.get_time_left()
	await _press_at(performer, performer.phrase.get_beat_time(index))
	var after: float = march.get_time_left()
	_check("a perfect march note extends the march", absf(after - before - 0.75) < 0.1,
		"%.2f -> %.2f" % [before, after])
	_check("...and shields the formation", first.status_component.get_shield_total() > 0.0
		and melody.status_component.get_shield_total() > 0.0, "")
	_check("march notes don't add turns (data flag)", key.turns == turns_before, "")

	# Shift doesn't break it; the line follows the dash.
	melody.request_slot(&"movement", melody.global_position + Vector2(400, 0))
	await _seconds(0.1)
	melody.release_slot(&"movement", melody.global_position + Vector2(400, 0))
	await _seconds(0.4)
	_check("Melody's dash doesn't break the march", march.is_marching() and march.followers.size() == 2, "")

	# A follower breaks free with opposing input.
	melody.move_direction = Vector2.RIGHT
	back.move_direction = Vector2.LEFT
	await _seconds(0.9)
	back.move_direction = Vector2.ZERO
	melody.move_direction = Vector2.ZERO
	_check("a follower breaks free by holding against the line", not back.status_component.has_status(&"melody_parade")
		and not march.followers.has(back), "")
	_check("...and loses the march buff", not back.status_component.has_status(&"melody_march_speed"), "")

	# A stun ends it and releases everyone.
	melody.status_component.apply(_stun())
	await _physics_frames(2)
	_check("a stun ends the march", not march.is_marching() and not first.status_component.has_status(&"melody_parade")
		and not first.status_component.has_status(&"melody_march_speed"), "")
	_check("the march phrase stops too", not performer.is_playing(), "")
	_clear()
	await _physics_frames(2)


# --- Helpers ------------------------------------------------------------------

func _reset(at: Vector2) -> void:
	melody.ability_controller.interrupt()
	melody.status_component.clear()
	melody.movement_component.stop_forced_move()
	melody.global_position = at
	melody.velocity = Vector2.ZERO
	melody.move_direction = Vector2.ZERO
	melody.health_component.reset()
	var performer := RhythmPerformer.find_on(melody)
	if performer != null:
		performer.cancel()
	for ability in melody.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	melody.aim_point = at
	melody.aim_direction = (at - melody.global_position).normalized()


# Crank RMB on `ally` for `hold` seconds and release.
func _crank_and_release(ally: Node2D, hold: float) -> void:
	_aim(ally.global_position)
	melody.request_slot(&"ability_1", ally.global_position)
	await _seconds(hold)
	melody.release_slot(&"ability_1", ally.global_position)


func _press_at(performer: RhythmPerformer, t: float) -> int:
	while performer.is_playing() and performer.time < t:
		await get_tree().physics_frame
	return performer.press_note()


func _wait_phrase(performer: RhythmPerformer) -> void:
	while performer.is_playing():
		await get_tree().physics_frame


func _ally_hero(at: Vector2) -> Hero:
	var h: Hero = load(ALLY_HERO).instantiate()
	h.team = &"a"
	add_child(h)
	h.global_position = at
	spawned.append(h)
	return h


func _dummy(at: Vector2, hp: float = 5000.0) -> TrainingDummy:
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


func _stun() -> StatusEffect:
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.2
	stun.stuns = true
	return stun


func _cue_count(name: StringName) -> int:
	return cues.filter(func(c): return c[0] == name).size()


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
