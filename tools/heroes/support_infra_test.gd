extends Node2D

# Headless checks for the shared support systems:
#   A1 rhythm phrases, A2 shields, A3 explosive projectiles, A4 fading
#   multipliers, A5 ally targeting + tether, A6 trail-following formations.
#
#   godot --headless res://tools/heroes/support_infra_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"

var failures := 0
var hero: Hero
var cues: Array = []
var spawned: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	hero = _hero(Vector2.ZERO, &"a")
	hero.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	await _physics_frames(3)

	await _test_rhythm()
	await _test_shields()
	await _test_explosions()
	await _test_fade()
	await _test_ally_targeting()
	await _test_formation()
	await _test_charged_bash_and_passive()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- A1 Rhythm ----------------------------------------------------------------

func _phrase() -> RhythmPhrase:
	var phrase := RhythmPhrase.new()
	phrase.note_count = 4
	phrase.bpm = 120.0    # a beat every 0.5 s
	phrase.lead_in = 0.3
	phrase.good_window = 0.12
	phrase.perfect_window = 0.05
	phrase.note_pitches = [1.0, 1.25, 1.5, 2.0]
	return phrase


# Waits until the performer's clock reaches `t`, then presses.
func _press_at(performer: RhythmPerformer, t: float) -> int:
	while performer.is_playing() and performer.time < t:
		await get_tree().physics_frame
	return performer.press_note()


func _test_rhythm() -> void:
	var phrase := _phrase()
	_check("phrase validates", phrase.validate().is_empty(), "\n".join(phrase.validate()))
	var performer := RhythmPerformer.find_or_create(hero)
	_check("performer is created once, on the actor", RhythmPerformer.find_or_create(hero) == performer
		and RhythmPerformer.find_on(hero) == performer, "")
	var graded := []
	var finished := []
	performer.note_graded.connect(func(i, g): graded.append([i, g]))
	performer.phrase_finished.connect(func(r): finished.append(r))
	cues.clear()
	performer.play(phrase, &"test")
	await _physics_frames(1)
	_check("the ring is drawn on the actor", _ring_on(hero) != null, "")
	_check("a press far from any beat is ignored", performer.press_note() == -1, "")
	var g0: int = await _press_at(performer, phrase.get_beat_time(0))
	var g1: int = await _press_at(performer, phrase.get_beat_time(1) + 0.09)
	# note 2: no press
	var g3: int = await _press_at(performer, phrase.get_beat_time(3))
	await _physics_frames(2)
	_check("on the beat = PERFECT", g0 == RhythmResults.Grade.PERFECT, str(g0))
	_check("0.09 s late = GOOD", g1 == RhythmResults.Grade.GOOD, str(g1))
	_check("unpressed = MISS", graded.size() == 4 and graded[2][1] == RhythmResults.Grade.MISS, str(graded))
	_check("last note PERFECT", g3 == RhythmResults.Grade.PERFECT, str(g3))
	_check("phrase_finished with totals", finished.size() == 1 and finished[0].get_perfects() == 2
		and finished[0].get_goods() == 1 and finished[0].get_misses() == 1 and not finished[0].cancelled, "")
	var notes := cues.filter(func(c): return str(c[0]).begins_with("test_note_"))
	_check("per-grade cues with the phrase's pitches", notes.size() == 4 and notes[0][0] == &"test_note_perfect"
		and notes[1][0] == &"test_note_good" and notes[2][0] == &"test_note_miss"
		and is_equal_approx(notes[3][1].pitch, 2.0), str(notes.map(func(c): return c[0])))
	await _seconds(0.5)
	_check("the ring goes away after the phrase", _ring_on(hero) == null, "")

	# A stun ends it early; the notes so far count.
	finished.clear()
	performer.play(phrase, &"test")
	await _press_at(performer, phrase.get_beat_time(0))
	hero.status_component.apply(_stun(0.2))
	await _physics_frames(2)
	_check("a stun cancels the phrase, keeping graded notes", finished.size() == 1 and finished[0].cancelled
		and finished[0].grades.size() == 1 and finished[0].get_perfects() == 1, str(finished.size()))
	await _seconds(0.3)

	# Silence doesn't, unless the phrase says so.
	finished.clear()
	var silence := StatusEffect.new()
	silence.id = &"test_silence"
	silence.duration = 0.3
	silence.silences = true
	performer.play(phrase, &"test")
	await _physics_frames(2)
	hero.status_component.apply(silence)
	await _physics_frames(3)
	_check("silence doesn't cancel by default", performer.is_playing(), "")
	performer.cancel()
	await _seconds(0.35)
	phrase.cancel_on_silence = true
	performer.play(phrase, &"test")
	await _physics_frames(2)
	hero.status_component.apply(silence)
	await _physics_frames(3)
	_check("...unless cancel_on_silence", not performer.is_playing(), "")
	await _seconds(0.35)

	# The player's key plays notes while a phrase runs (not the slot).
	phrase.cancel_on_silence = false
	var input := PlayerHeroInput.new()
	input.set_physics_process(false)
	input.set_process(false)
	hero.add_child(input)
	finished.clear()
	performer.play(phrase, &"test")
	while performer.time < phrase.get_beat_time(0):
		await get_tree().physics_frame
	var press := InputEventAction.new()
	press.action = phrase.input_action
	press.pressed = true
	input._unhandled_input(press)
	_check("the phrase's input action plays a note", performer.results.grades.size() == 1
		and performer.results.grades[0] == RhythmResults.Grade.PERFECT, str(performer.results.grades))
	_check("...instead of requesting the slot", not hero.get_ability(&"cc").is_casting()
		and hero.get_ability(&"cc").is_ready(), "")
	performer.cancel()
	input.queue_free()
	await _physics_frames(2)


func _ring_on(actor: Node) -> Node:
	for child in actor.get_node("Visuals").get_children():
		if child.get_script() == RhythmPerformer.RING_SCRIPT and not child.is_queued_for_deletion():
			return child
	return null


# --- A2 Shields ---------------------------------------------------------------

func _shield(amount: float, duration: float = 5.0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = &"test_shield"
	effect.duration = duration
	effect.shield_amount = ScalingValue.make(amount)
	return effect


func _test_shields() -> void:
	var dummy := _dummy(Vector2(400, 400), 1000.0)
	await _physics_frames(2)
	var health := dummy.health_component
	var status := dummy.status_component
	var bar: HealthBar = dummy.get_node("HealthBar")
	DebugTools.meter.tracked = hero
	DebugTools.meter.reset()
	var absorbed_events := []
	var on_absorbed := func(amount, src, target, id, _i): absorbed_events.append([amount, src, target, id])
	CombatEvents.damage_absorbed.connect(on_absorbed)

	status.apply(_shield(100.0), hero)
	_check("shield total", is_equal_approx(status.get_shield_total(), 100.0), "")
	_check("health bar shows the shield overlay", is_equal_approx(bar.get_shield(), 100.0)
		and bar.max_value >= health.max_health, "")
	dummy.hurtbox.take_hit(DamageInfo.create(60.0, null, DamageInfo.Type.TRUE))
	_check("shield absorbs before health", health.current_health == 1000.0
		and is_equal_approx(status.get_shield_total(), 40.0), "hp %.0f" % health.current_health)
	var info := DamageInfo.create(60.0, null, DamageInfo.Type.TRUE)
	dummy.hurtbox.take_hit(info)
	_check("overflow reaches health", is_equal_approx(health.current_health, 980.0)
		and is_equal_approx(info.absorbed, 40.0) and is_equal_approx(info.final_amount, 20.0),
		"hp %.0f" % health.current_health)
	_check("a depleted shield ends its status", not status.has_status(&"test_shield"), "")
	_check("absorbed damage is reported (with the shield's applier)", absorbed_events.size() == 2
		and absorbed_events[0][1] == hero and absorbed_events[0][2] == dummy, str(absorbed_events.size()))
	_check("the meter logs shielding done by its applier", is_equal_approx(DebugTools.meter.get_total_shielding_done(), 100.0),
		"%.0f" % DebugTools.meter.get_total_shielding_done())

	# REFRESH keeps the larger remaining shield.
	status.apply(_shield(100.0), hero)
	dummy.hurtbox.take_hit(DamageInfo.create(70.0, null, DamageInfo.Type.TRUE))
	status.apply(_shield(50.0), hero)
	_check("refresh keeps the larger shield (50 > 30)", is_equal_approx(status.get_shield_total(), 50.0), "")
	status.apply(_shield(20.0), hero)
	_check("refresh never shrinks it (50 > 20)", is_equal_approx(status.get_shield_total(), 50.0), "")
	var stacking := _shield(30.0)
	stacking.id = &"test_stack_shield"
	stacking.stack_rule = StatusEffect.StackRule.STACK
	stacking.max_stacks = 5
	status.apply(stacking, hero)
	status.apply(stacking, hero)
	_check("STACK adds shields", is_equal_approx(status.get_shield_total(), 110.0), "")
	status.apply(_shield(40.0), hero, Vector2.ZERO, 0.5)
	_check("strength scales a new shield", is_equal_approx(status.get_shield_total(), 110.0), "")
	status.clear()
	_check("shield expiry clears the overlay", is_equal_approx(bar.get_shield(), 0.0), "")

	var short := _shield(100.0, 0.2)
	status.apply(short, hero)
	await _seconds(0.3)
	_check("an unused shield expires with its status", status.get_shield_total() == 0.0, "")
	CombatEvents.damage_absorbed.disconnect(on_absorbed)
	DebugTools.meter.tracked = null
	_clear()
	await _physics_frames(2)


# --- A3 Explosions ------------------------------------------------------------

func _blast_data() -> ProjectileData:
	var data := ProjectileData.new()
	data.speed = 1500.0
	data.lifetime = 0.2    # 300 px
	data.radius = 12.0
	data.explosion_shape = HitShape.circle(100.0)
	return data


func _test_explosions() -> void:
	# Explode at max range: catches everything in the radius around the end.
	# Off the flight line (hurtbox radius 55 + projectile 12), inside the
	# 100 px blast around the end point (300, 0).
	var at_end := _dummy(Vector2(320, 85), 1000.0)
	var near_end := _dummy(Vector2(370, -70), 1000.0)
	var far_from_end := _dummy(Vector2(300, 260), 1000.0)
	var ally := _dummy(Vector2(240, -75), 1000.0)
	ally.team = &"a"
	await _physics_frames(2)
	var data := _blast_data()
	data.explode_on_expire = true
	var buff := StatusEffect.new()
	buff.id = &"test_ally_buff"
	buff.duration = 2.0
	data.explosion_ally_status = buff
	var hits := []
	var projectile := Projectile.fire(hero, data, Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(40.0, hero, DamageInfo.Type.MAGIC))
	projectile.hit_landed.connect(func(i, h): hits.append(h.owner))
	var boomed := [false]
	projectile.exploded.connect(func(_at): boomed[0] = true)
	await _seconds(0.35)
	_check("explodes at max distance", boomed[0], "")
	_check("the blast damages enemies in radius", at_end.health_component.current_health == 960.0
		and near_end.health_component.current_health == 960.0, "")
	_check("...not outside it", far_from_end.health_component.current_health == 1000.0, "")
	_check("allies take ally_status, no damage", ally.status_component.has_status(&"test_ally_buff")
		and ally.health_component.current_health == 1000.0, "")
	_check("blast hits report through hit_landed", hits.has(at_end) and hits.has(near_end), str(hits.size()))
	_clear()
	await _physics_frames(2)

	# Explode on hit: the first target and its neighbour, no double hit.
	var front := _dummy(Vector2(250, 0), 1000.0)
	var beside := _dummy(Vector2(290, 80), 1000.0)
	var behind := _dummy(Vector2(600, 0), 1000.0)
	await _physics_frames(2)
	data = _blast_data()
	data.lifetime = 1.0
	data.explode_on_hit = true
	Projectile.fire(hero, data, Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(40.0, hero, DamageInfo.Type.TRUE))
	await _seconds(0.4)
	_check("explodes on the first enemy hit (hit once)", front.health_component.current_health == 960.0,
		"%.0f" % front.health_component.current_health)
	_check("the blast catches the neighbour", beside.health_component.current_health == 960.0, "")
	_check("the projectile stops there", behind.health_component.current_health == 1000.0, "")
	_clear()
	await _physics_frames(2)

	# Split: a fan of children from the blast point; children never re-split.
	var child := _blast_data()
	child.lifetime = 0.3
	child.explode_on_expire = true
	child.explosion_shape = HitShape.circle(40.0)
	child.split_on_explode = true    # must be ignored for children
	child.split_projectile = child
	data = _blast_data()
	data.explode_on_expire = true
	data.split_on_explode = true
	data.split_projectile = child
	data.split_count = 3
	data.split_fan_degrees = 60.0
	data.split_damage_multiplier = 0.5
	var spawned_projectiles := [0]
	var on_child := func(n): if n is Projectile: spawned_projectiles[0] += 1
	child_entered_tree.connect(on_child)
	# Children fly 450 px from (300, 0) at -30, 0, +30 degrees.
	var left := _dummy(Vector2(300, 0) + Vector2.RIGHT.rotated(deg_to_rad(-30)) * 450.0, 1000.0)
	var mid := _dummy(Vector2(750, 0), 1000.0)
	var right := _dummy(Vector2(300, 0) + Vector2.RIGHT.rotated(deg_to_rad(30)) * 450.0, 1000.0)
	await _physics_frames(2)
	Projectile.fire(hero, data, Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(40.0, hero, DamageInfo.Type.TRUE))
	await _seconds(0.8)
	child_entered_tree.disconnect(on_child)
	_check("splits into 3 in a fan", left.health_component.current_health == 980.0
		and mid.health_component.current_health == 980.0 and right.health_component.current_health == 980.0,
		"%.0f %.0f %.0f" % [left.health_component.current_health, mid.health_component.current_health,
			right.health_component.current_health])
	_check("children don't split again (1 + 3 projectiles)", spawned_projectiles[0] == 4, str(spawned_projectiles[0]))
	_check("explosion data validates", data.validate().is_empty(), "\n".join(data.validate()))
	var broken := ProjectileData.new()
	broken.explode_on_hit = true
	broken.split_on_explode = true
	_check("validation catches a blast with no shape / split with no child", broken.validate().size() >= 2, "")
	_clear()
	await _physics_frames(2)


# --- A4 Fade ------------------------------------------------------------------

func _test_fade() -> void:
	var dummy := _dummy(Vector2(-400, 400), 1000.0)
	await _physics_frames(2)
	var status := dummy.status_component
	var haste := StatusEffect.new()
	haste.id = &"test_wind"
	haste.duration = 1.0
	haste.stat_multipliers = {StatusEffect.MOVE_SPEED: 2.0}
	haste.fade_multipliers = true
	status.apply(haste, hero)
	_check("fade starts at full", is_equal_approx(status.get_multiplier(StatusEffect.MOVE_SPEED), 2.0), "")
	await _seconds(0.5)
	var mid := status.get_multiplier(StatusEffect.MOVE_SPEED)
	var ratio := status.get_fade_ratio(&"test_wind")
	_check("halfway: ~1.5x and fade ratio ~0.5", absf(mid - 1.5) < 0.05 and absf(ratio - 0.5) < 0.05,
		"%.3f / %.3f" % [mid, ratio])
	await _seconds(0.6)
	_check("ends back at exactly 1.0", status.get_multiplier(StatusEffect.MOVE_SPEED) == 1.0
		and not status.has_status(&"test_wind"), "")
	status.apply(haste, hero, Vector2.ZERO, 0.5)
	_check("strength 0.5 starts at 1.5x", is_equal_approx(status.get_multiplier(StatusEffect.MOVE_SPEED), 1.5), "")
	status.apply(haste, hero, Vector2.ZERO, 1.0, 4.0)
	_check("duration override", is_equal_approx(status.get_time_left(&"test_wind"), 4.0), "")
	_clear()
	await _physics_frames(2)


# --- A5 Ally targeting --------------------------------------------------------

func _test_ally_targeting() -> void:
	hero.global_position = Vector2.ZERO
	var ally := _dummy(Vector2(300, 0), 1000.0)
	ally.team = &"a"
	var enemy := _dummy(Vector2(330, 60), 1000.0)
	var far_ally := _dummy(Vector2(1100, 0), 1000.0)
	far_ally.team = &"a"
	var hidden_ally := _dummy(Vector2(0, -400), 1000.0)
	hidden_ally.team = &"a"
	var wall: Node2D = load(WALL).instantiate()
	wall.position = Vector2(0, -200)
	add_child(wall)
	spawned.append(wall)
	await _physics_frames(3)
	var rule := AllyTargeting.new()
	rule.cast_range = 700.0
	rule.snap_radius = 150.0
	_check("finds the ally near the cursor (not the nearer enemy)", rule.find(hero, Vector2(330, 50)) == ally.hurtbox, "")
	_check("out of range: nothing", rule.find(hero, far_ally.global_position) == null, "")
	_check("behind a wall: nothing", rule.find(hero, hidden_ally.global_position) == null, "")
	_check("self excluded by default", rule.find(hero, hero.global_position) == null, "")
	rule.allow_self = true
	_check("...allowed with allow_self", rule.find(hero, hero.global_position) == hero.hurtbox, "")
	rule.allow_self = false

	# An ally-targeted ability on the hero.
	var data := AbilityData.new()
	data.id = &"test_ally_cast"
	data.ability_script = Ability
	data.cooldown = 5.0
	data.ally_targeting = rule
	data.charge_enabled = true
	data.charge_time_max = 1.0
	data.tether_range = 500.0
	var ability := Ability.new()
	ability.set_data(data)
	hero.ability_controller.add_ability(ability, &"test_ally")
	await _physics_frames(1)
	_check("no ally: fails without spending the cooldown",
		not hero.ability_controller.try_activate(ability, Vector2(-500, 300)) and ability.is_ready(), "")
	_check("with an ally: casts and remembers it",
		hero.ability_controller.try_activate(ability, Vector2(320, 20)) and ability.cast_ally == ally, "")

	var input := PlayerHeroInput.new()
	input.set_physics_process(false)
	input.set_process(false)
	hero.add_child(input)
	# Highlight only while the ability is ready: cancel the charge first.
	ability.cancel_charge()
	hero.aim_point = Vector2(320, 20)
	input._update_ally_highlight()
	_check("the candidate ally is highlighted", ally.visuals._is_highlighted, "")
	hero.aim_point = Vector2(-500, 300)
	input._update_ally_highlight()
	_check("...and unhighlighted when the cursor leaves", not ally.visuals._is_highlighted, "")
	input.queue_free()

	# Tether: walking out of range cancels the charge (no cooldown).
	hero.ability_controller.try_activate(ability, Vector2(320, 20))
	cues.clear()
	hero.global_position = Vector2(-400, 0)    # 700 px from the ally
	await _physics_frames(2)
	_check("breaking the tether cancels the charge", not ability.is_casting() and ability.is_ready()
		and cues.any(func(c): return c[0] == &"test_ally_cast_tether_break"), "")
	hero.global_position = Vector2.ZERO
	hero.ability_controller.remove_all()
	await _physics_frames(1)
	hero.queue_free()
	hero = _hero(Vector2.ZERO, &"a")
	hero.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	_clear()
	await _physics_frames(3)


# --- A6 Formations ------------------------------------------------------------

func _formation_status() -> StatusEffect:
	var march := StatusEffect.new()
	march.id = &"test_march"
	march.duration = 30.0
	march.compel_enabled = true
	march.compel_follow_trail = true
	march.compel_trail_spacing = 100.0
	march.compel_speed_multiplier = 1.5
	march.compel_stop_distance = 4.0
	march.compel_breakable = true
	march.compel_break_hold_time = 0.4
	return march


func _test_formation() -> void:
	hero.global_position = Vector2(0, 1200)
	hero.movement_component.move_speed = 260.0    # followers walk 330 here
	var first := _dummy(Vector2(-60, 1200), 1000.0)
	var second := _dummy(Vector2(-120, 1260), 1000.0)
	for d in [first, second]:
		d.return_to_anchor = false
	await _physics_frames(2)
	var march := _formation_status()
	first.status_component.apply(march, hero)
	second.status_component.apply(march, hero)
	var recorder := TrailRecorder.find_on(hero)
	_check("the applier records a trail", recorder != null, "")
	_check("slots in order of joining", recorder.get_slot(first) == 0 and recorder.get_slot(second) == 1, "")

	hero.move_direction = Vector2.RIGHT
	await _seconds(1.6)
	hero.move_direction = Vector2.DOWN
	await _seconds(0.9)
	var corner_y := 1200.0
	var gap_first := first.global_position.distance_to(recorder.point_behind(100.0))
	var gap_second := second.global_position.distance_to(recorder.point_behind(200.0))
	_check("followers stand at their trail points", gap_first < 45.0 and gap_second < 45.0,
		"%.0f / %.0f px off" % [gap_first, gap_second])
	_check("they form a line, not a bunch", first.global_position.distance_to(second.global_position) > 70.0,
		"%.0f" % first.global_position.distance_to(second.global_position))
	_check("the line turns her corner (the back one is still on the first leg)",
		first.global_position.y > corner_y + 40.0 and second.global_position.y < first.global_position.y - 40.0,
		"first %s second %s hero %s" % [first.global_position, second.global_position, hero.global_position])
	hero.move_direction = Vector2.ZERO

	# break_formation (AI) frees them; the line closes up.
	first.status_component.break_formation()
	_check("break_formation frees a follower", not first.status_component.has_status(&"test_march"), "")
	_check("the one behind moves up a slot", recorder.get_slot(second) == 0, "")
	second.status_component.remove(&"test_march")
	await _physics_frames(2)
	_check("the trail goes away with the last follower", TrailRecorder.find_on(hero) == null, "")

	# A hero follower breaks free with opposing input, and can shoot meanwhile.
	var follower := _hero(hero.global_position + Vector2(-100, 0), &"a")
	await _physics_frames(3)
	follower.status_component.apply(march, hero)
	hero.move_direction = Vector2.RIGHT
	await _seconds(0.4)
	_check("followers can still shoot", follower.request_slot(&"primary", follower.global_position + Vector2(0, 300)), "")
	follower.move_direction = Vector2.LEFT
	await _seconds(0.2)
	_check("brief opposing input doesn't break it", follower.status_component.has_status(&"test_march"), "")
	await _seconds(0.35)
	_check("holding it breaks free", not follower.status_component.has_status(&"test_march"), "")
	follower.move_direction = Vector2.ZERO

	# A movement ability breaks free too.
	follower.status_component.apply(march, hero)
	await _physics_frames(2)
	follower.request_slot(&"movement", follower.global_position + Vector2(0, 300))
	await _physics_frames(2)
	_check("a movement ability breaks the formation", not follower.status_component.has_status(&"test_march"), "")
	hero.move_direction = Vector2.ZERO
	follower.queue_free()
	_clear()
	await _physics_frames(2)


# --- Charged bash dash + passive slot (generic pieces Melody builds on) --------

func _test_charged_bash_and_passive() -> void:
	hero.global_position = Vector2(0, -1500)
	hero.move_direction = Vector2.ZERO
	await _physics_frames(2)
	var boop := StatusEffect.new()
	boop.id = &"test_boop"
	boop.duration = 0.2
	boop.displace_distance = 120.0
	boop.displace_duration = 0.12
	boop.displace_direction = StatusEffect.DisplaceDirection.ALONG_HIT
	var data := ChargeData.new()
	data.id = &"test_bash"
	data.ability_script = ChargeAbility
	data.cooldown = 1.0
	data.distance = 400.0
	data.min_distance = 100.0
	data.speed = 1600.0
	data.charge_enabled = true
	data.charge_time_max = 1.0
	data.hit_shape = HitShape.circle(70.0)
	data.damage = ScalingValue.make(20.0)
	data.values = {&"damage_full": ScalingValue.make(60.0)}
	data.on_hit_status = boop
	var dash := ChargeAbility.new()
	dash.set_data(data)
	hero.ability_controller.add_ability(dash, &"test_bash_slot")
	var target := _dummy(Vector2(180, -1500), 1000.0)
	target.return_to_anchor = false
	await _physics_frames(2)
	var start := hero.global_position
	hero.aim_direction = Vector2.RIGHT
	hero.aim_point = start + Vector2(400, 0)
	hero.ability_controller.try_activate(dash, start + Vector2(400, 0))
	await _seconds(0.5)
	hero.ability_controller.release(dash, start + Vector2(400, 0))
	var ratio := dash.get_charge_ratio()
	await _seconds(0.5)
	var travelled := hero.global_position.x - start.x
	_check("charged dash length = lerp(min_distance, distance)", absf(travelled - lerpf(100.0, 400.0, ratio)) < 12.0,
		"%.0f vs %.0f" % [travelled, lerpf(100.0, 400.0, ratio)])
	_check("the bash hits once for charged damage", is_equal_approx(1000.0 - target.health_component.current_health,
		lerpf(20.0, 60.0, ratio)), "%.1f" % (1000.0 - target.health_component.current_health))
	_check("...and boops (knockback status)", target.global_position.x > 250.0, str(target.global_position))
	hero.ability_controller.remove_all()
	await _physics_frames(1)

	var rules := GameRules.current()
	var passive := rules.get_slot(&"passive")
	_check("GameRules has an optional passive slot with no key", passive != null and not passive.required
		and passive.input_action == &"", "")
	var never := PassiveAbility.new()
	_check("a PassiveAbility never casts (silently)", never.get_block_reason() == "Passive"
		and never._is_silent_block("Passive"), "")
	never.free()
	_clear()
	await _physics_frames(2)


# --- Helpers ------------------------------------------------------------------

func _hero(at: Vector2, team: StringName) -> Hero:
	var h: Hero = load(HERO).instantiate()
	h.team = team
	add_child(h)
	h.global_position = at
	h.aim_direction = Vector2.RIGHT
	h.aim_point = at + Vector2.RIGHT * 300.0
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


func _stun(duration: float) -> StatusEffect:
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = duration
	stun.stuns = true
	return stun


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
