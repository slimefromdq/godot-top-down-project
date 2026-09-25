extends Node2D

# Headless checks for Jose's kit against training dummies.
#
#   godot --headless res://tools/heroes/jose_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const JOSE := "res://heroes/jose/jose_hero.tscn"
const ROOK := "res://heroes/rook/rook_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"
const MARK := &"jose_coin_mark"

var failures := 0
var jose: Hero
var dummies: Array[Node] = []
var hits_log: Array[DamageInfo] = []
var cues: Array = []    # [cue, context]


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	jose = load(JOSE).instantiate()
	jose.team = &"a"
	add_child(jose)
	jose.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	await _physics_frames(3)

	_test_assembled()
	await _test_primary_and_flourish()
	await _test_last_word()
	await _test_coin()
	await _test_weapons_free()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate"]:
		_check("slot %s filled" % slot, jose.get_ability(slot) != null, "")
	_check("ability_2 left empty", jose.get_ability(&"ability_2") == null, "")
	_check("definition validates", jose.definition.validate().is_empty(), "\n".join(jose.definition.validate()))
	_check("role Carry, title Smiling Assassin", jose.definition.get_role_name() == "Carry"
		and jose.definition.title == "Smiling Assassin", "")
	_check("primary and Last Word are generic guns",
		jose.get_ability(&"primary").get_script() == RangedAttackAbility
			and jose.get_ability(&"ability_1").get_script() == RangedAttackAbility, "")
	var roster := HeroScaffold.find_definitions().map(func(d): return d.hero_id)
	_check("Jose is in the roster", roster.has(&"jose"), str(roster))


# --- Primary + Flourish -----------------------------------------------------

func _test_primary_and_flourish() -> void:
	_reset(Vector2.ZERO)
	var target := _dummy(Vector2(400, 0))
	await _physics_frames(2)
	var gun := jose.get_ranged_ability()
	_check("12-round magazine", gun.get_ammo() == 12 and gun.get_max_ammo() == 12, "")
	cues.clear()
	hits_log.clear()
	await _fire_until_empty(target.global_position, 6.0)
	await _seconds(0.3)
	var fires := _cue_contexts(&"twin_longarms_fire")
	var indices := fires.map(func(c): return c.muzzle_index)
	var alternates := fires.size() == 12
	for i in range(1, indices.size()):
		alternates = alternates and indices[i] != indices[i - 1]
	_check("12 shots, alternating muzzles", alternates, str(indices))
	if fires.size() >= 2:
		var gap: float = (fires[0].position as Vector2).distance_to(fires[1].position)
		_check("left/right muzzles are apart", gap > 30.0, "%.0f px" % gap)
	var hits := hits_log.filter(func(i: DamageInfo): return i.target == target and i.label == &"twin_longarms")
	# 22 + 0.55 x 44 Weapon.
	_check("every round hits for base + Weapon ratio", hits.size() == 12 and is_equal_approx(hits[0].final_amount, 46.2),
		"%d hits, %.1f" % [hits.size(), hits[0].final_amount if not hits.is_empty() else 0.0])
	_check("auto reload when empty", gun.get_ammo() == 0 and gun.is_reloading(), "")
	_check("reload is long (flip is the better reload)", gun.get_reload_remaining() > 2.0, "%.2f" % gun.get_reload_remaining())

	# Flourish mid-reload: refills, flips the way he walks (not the aim).
	await _seconds(0.5)
	cues.clear()
	var start := jose.global_position
	jose.move_direction = Vector2.DOWN
	var flipped := jose.request_slot(&"movement", target.global_position)
	await _physics_frames(2)
	_check("Flourish refills the magazine mid-reload", flipped and gun.get_ammo() == 12 and not gun.is_reloading(), "")
	_check("flourish_reload cue (the spin + click)", not _cue_contexts(&"flourish_reload").is_empty(), "")
	var hp := jose.health_component.current_health
	jose.hurtbox.take_hit(DamageInfo.create(50.0, target, DamageInfo.Type.TRUE))
	_check("immune during the flip window", jose.health_component.current_health == hp, "")
	await _seconds(0.35)
	jose.move_direction = Vector2.ZERO
	var moved := jose.global_position - start
	_check("flips along movement input, not the aim", moved.y > 200.0 and absf(moved.x) < 20.0, str(moved))
	jose.hurtbox.take_hit(DamageInfo.create(50.0, target, DamageInfo.Type.TRUE))
	_check("immunity ends after the window", jose.health_component.current_health < hp, "")

	# No movement input: flips toward the aim.
	_reset(Vector2.ZERO)
	await _physics_frames(1)
	jose.request_slot(&"movement", Vector2(400, 0))
	await _seconds(0.35)
	_check("no input: flips toward the aim", jose.global_position.x > 200.0, str(jose.global_position))

	# Rooted: can't flip.
	_reset(Vector2.ZERO)
	var root := StatusEffect.new()
	root.id = &"test_root"
	root.duration = 0.5
	root.roots = true
	jose.status_component.apply(root)
	_check("rooted: can't flip", not jose.request_slot(&"movement", Vector2(400, 0)), "")
	jose.status_component.clear()
	_clear_dummies()
	await _physics_frames(2)


# --- Last Word --------------------------------------------------------------

func _test_last_word() -> void:
	_reset(Vector2.ZERO)
	var line: Array[TrainingDummy] = [_dummy(Vector2(300, 0)), _dummy(Vector2(450, 0)), _dummy(Vector2(600, 0))]
	await _physics_frames(2)
	var shot := jose.get_ability(&"ability_1") as RangedAttackAbility
	var gun := jose.get_ranged_ability()
	var low := 50.0 + 0.8 * 44.0
	var full := 160.0 + 2.0 * 44.0
	var ammo_before := gun.get_ammo()

	# Partial charge.
	hits_log.clear()
	cues.clear()
	_aim(Vector2(600, 0))
	jose.request_slot(&"ability_1", Vector2(600, 0))
	_check("charging slows walking", is_equal_approx(jose.movement_component.get_action_multiplier(), 0.45), "")
	await _physics_frames(2)
	_check("a live aim line shows while charging", _live_telegraph() != null, "")
	await _seconds(0.5)
	jose.release_slot(&"ability_1", Vector2(600, 0))
	var ratio := shot.get_charge_ratio()
	await _seconds(0.3)
	var partial := hits_log.filter(func(i: DamageInfo): return i.label == &"last_word")
	_check("the aim line goes away on release", _live_telegraph() == null, "")
	_check("pierces a line of 3 dummies", partial.size() == 3, "%d hits" % partial.size())
	if not partial.is_empty():
		_check("partial charge damage = lerp(damage, damage_full)",
			absf(partial[0].final_amount - lerpf(low, full, ratio)) < 0.01,
			"%.1f at %.2f" % [partial[0].final_amount, ratio])
	_check("Last Word uses no revolver ammo", gun.get_ammo() == ammo_before, "")

	# Full charge, late: full damage, not perfect.
	shot.reset_cooldown()
	await _seconds(0.6)
	hits_log.clear()
	jose.request_slot(&"ability_1", Vector2(600, 0))
	await _seconds(1.5)
	jose.release_slot(&"ability_1", Vector2(600, 0))
	await _seconds(0.3)
	var late := hits_log.filter(func(i: DamageInfo): return i.label == &"last_word")
	_check("full charge damage", not late.is_empty() and is_equal_approx(late[0].final_amount, full) and not shot.was_perfect_release(),
		"%.1f vs %.1f" % [late[0].final_amount if not late.is_empty() else 0.0, full])

	# Perfect release.
	shot.reset_cooldown()
	await _seconds(0.6)
	hits_log.clear()
	cues.clear()
	var fired: Array[ProjectileData] = []
	var on_child := func(n): if n is Projectile: fired.append(n.data)
	child_entered_tree.connect(on_child)
	jose.request_slot(&"ability_1", Vector2(600, 0))
	await _seconds(1.16)
	var in_window := shot.is_in_perfect_window()
	jose.release_slot(&"ability_1", Vector2(600, 0))
	await _seconds(0.3)
	child_entered_tree.disconnect(on_child)
	# Abilities run on a deep copy of their data: compare with that copy.
	var heavy := fired.filter(func(d): return d == shot.get_ranged_data().perfect_projectile)
	var perfect := hits_log.filter(func(i: DamageInfo): return i.label == &"last_word")
	_check("perfect window at full charge", in_window and shot.was_perfect_release(), "")
	_check("perfect release applies perfect_damage_multiplier", not perfect.is_empty()
		and is_equal_approx(perfect[0].final_amount, full * 1.35) and perfect[0].has_tag(&"perfect"),
		"%.1f vs %.1f" % [perfect[0].final_amount if not perfect.is_empty() else 0.0, full * 1.35])
	_check("last_word_perfect cue", not _cue_contexts(&"last_word_perfect").is_empty(), "")
	_check("perfect shot draws the thicker tracer", heavy.size() == 1, "%d" % heavy.size())

	# Below the minimum: cancels, cooldown refunded.
	shot.reset_cooldown()
	await _seconds(0.6)
	hits_log.clear()
	jose.request_slot(&"ability_1", Vector2(600, 0))
	await _seconds(0.1)
	jose.release_slot(&"ability_1", Vector2(600, 0))
	await _seconds(0.3)
	_check("release under the minimum: no shot, no cooldown",
		hits_log.is_empty() and shot.is_ready() and not shot.is_casting(), "")
	_clear_dummies()
	await _physics_frames(2)


func _live_telegraph() -> TelegraphEffect:
	for child in jose.visuals.get_children():
		if child is TelegraphEffect and not child.is_queued_for_deletion() and child._ability != null:
			return child
	return null


# --- Coin -------------------------------------------------------------------

func _test_coin() -> void:
	_reset(Vector2.ZERO)
	var coin := jose.get_ability(&"cc") as RangedAttackAbility

	# A miss still spends the cooldown.
	_aim(Vector2(0, -600))
	_check("coin thrown", jose.request_slot(&"cc", Vector2(0, -600)), "")
	await _seconds(0.1)
	_check("a miss spends the cooldown", not coin.is_ready(), "%.1f" % coin.cooldown_remaining)

	# Mark, normal damage above the threshold. (Wait out the coin's 0.5 s
	# fire interval: reset_cooldown doesn't skip it.)
	await _seconds(0.5)
	coin.reset_cooldown()
	var marked := _dummy(Vector2(350, 0), 1000.0, true)
	await _physics_frames(2)
	hits_log.clear()
	_aim(marked.global_position)
	jose.request_slot(&"cc", marked.global_position)
	await _seconds(0.4)
	_check("coin marks the first enemy it hits", marked.status_component.has_status_from(MARK, jose), "")
	_check("the mark shows an overhead coin", marked.visuals._status_vfx.has(MARK), "")
	_check("coin damage is small", _sum(marked, &"coin") > 0.0 and _sum(marked, &"coin") < 20.0, "%.1f" % _sum(marked, &"coin"))
	_set_health(marked, 500.0)
	hits_log.clear()
	await _fire_one(marked.global_position)
	_check("above the threshold: a normal hit", not marked.health_component.is_dead()
		and is_equal_approx(marked.health_component.current_health, 500.0 - 46.2) and _sum(marked, &"coin_execute") == 0.0,
		"%.1f" % marked.health_component.current_health)

	# Crossing the threshold executes, through heavy mitigation.
	marked.configure(1000.0, 300.0, 0.0, 1)    # 300 armor: a revolver round does ~12
	marked.status_component.apply(load("res://heroes/jose/data/jose_coin_mark.tres"), jose)
	_set_health(marked, 125.0)    # threshold is 12% of 1000 = 120
	var tough := StatusEffect.new()
	tough.id = &"test_tough"
	tough.duration = 10.0
	tough.stat_multipliers = {StatusEffect.DAMAGE_TAKEN: 0.5}
	marked.status_component.apply(tough)
	var kills := [0]
	var on_kill := func(victim, _i): if victim == marked: kills[0] += 1
	jose.combat_hooks.kill.connect(on_kill)
	coin.cooldown_remaining = 8.0
	hits_log.clear()
	cues.clear()
	await _fire_one(marked.global_position)
	await _physics_frames(2)
	jose.combat_hooks.kill.disconnect(on_kill)
	var executes := hits_log.filter(func(i: DamageInfo): return i.label == &"coin_execute")
	_check("crossing the threshold executes", marked.health_component.is_dead(), "hp %.1f" % marked.health_component.current_health)
	_check("the execute is a labelled kill in the meter", executes.size() == 1 and executes[0].killed
		and executes[0].source == jose and executes[0].type == DamageInfo.Type.TRUE, str(executes.size()))
	_check("execute credits Jose's kill hook (kill feedback)", kills[0] == 1, "")
	_check("coin_execute cue", not _cue_contexts(&"coin_execute").is_empty(), "")
	_check("marked target dying resets Coin", coin.is_ready(), "%.1f" % coin.cooldown_remaining)
	_check("coin_reset cue", not _cue_contexts(&"coin_reset").is_empty(), "")

	# A teammate's hit never executes.
	var partner: Hero = load(ROOK).instantiate()
	partner.team = &"a"
	add_child(partner)
	partner.global_position = Vector2(-400, 400)
	var victim := _dummy(Vector2(350, 300), 1000.0, true)
	await _physics_frames(3)
	victim.status_component.apply(load("res://heroes/jose/data/jose_coin_mark.tres"), jose)
	_set_health(victim, 200.0)
	hits_log.clear()
	victim.hurtbox.take_hit(DamageInfo.create(150.0, partner, DamageInfo.Type.TRUE))
	await _physics_frames(2)
	_check("a teammate's hit below the threshold does NOT execute", not victim.health_component.is_dead()
		and _sum(victim, &"coin_execute") == 0.0, "hp %.1f" % victim.health_component.current_health)
	# Nor does Jose's hit on a target marked by nobody (his mark only).
	var unmarked := _dummy(Vector2(350, -300), 1000.0, true)
	await _physics_frames(2)
	_set_health(unmarked, 60.0)
	unmarked.hurtbox.take_hit(DamageInfo.create(10.0, jose, DamageInfo.Type.TRUE))
	await _physics_frames(2)
	_check("no mark, no execute", not unmarked.health_component.is_dead(), "")

	# Killed by a third party: Coin resets.
	coin.cooldown_remaining = 8.0
	cues.clear()
	var third := _dummy(Vector2(-600, -600))
	await _physics_frames(2)
	victim.hurtbox.take_hit(DamageInfo.create(99999.0, third, DamageInfo.Type.TRUE))
	await _physics_frames(2)
	_check("marked target killed by a third party resets Coin", victim.health_component.is_dead() and coin.is_ready(), "")
	_check("...with the coin_reset cue", not _cue_contexts(&"coin_reset").is_empty(), "")
	partner.queue_free()
	_clear_dummies()
	await _physics_frames(2)


# --- Weapons Free -----------------------------------------------------------

func _test_weapons_free() -> void:
	_reset(Vector2(0, 3000))
	var center := jose.global_position
	var east := _dummy(center + Vector2(300, 0))
	var south := _dummy(center + Vector2(0, 300))
	var west := _dummy(center + Vector2(-300, 0))
	var hidden := _dummy(center + Vector2(0, -380))
	var far := _dummy(center + Vector2(760, 0))
	var wall: Node2D = load(WALL).instantiate()
	wall.position = center + Vector2(0, -190)
	add_child(wall)
	dummies.append(wall)
	await _physics_frames(3)

	var ult = jose.get_ability(&"ultimate")    # untyped: Jose-specific script
	var gun := jose.get_ranged_ability()
	gun.reload_instantly()
	await _fire_one(east.global_position)
	var ammo := gun.get_ammo()
	hits_log.clear()
	cues.clear()
	_check("Weapons Free cast", jose.request_slot(&"ultimate", center + Vector2(300, 0)), "")
	await _seconds(0.25)    # windup
	_check("channel started (weapons_free_start)", ult.is_channeling()
		and not _cue_contexts(&"weapons_free_start").is_empty(), "")
	_check("the kill box follows Jose", is_instance_valid(ult.zone) and ult.zone.data.follow_owner
		and ult.zone.global_position.distance_to(jose.global_position) < 1.0, "")
	_check("walks at the channel multiplier", is_equal_approx(jose.movement_component.get_action_multiplier(), 0.6), "")

	var shots := [0]
	var count_shot := func(cue, _c): if cue == &"weapons_free_shot": shots[0] += 1
	jose.cue_triggered.connect(count_shot)
	await _seconds(1.0)
	jose.cue_triggered.disconnect(count_shot)
	# 3.5 shots/s x 2.
	_check("fires faster than the primary (x weapons_free_fire_rate)", shots[0] >= 6 and shots[0] <= 8, str(shots[0]))

	var order := _cue_contexts(&"weapons_free_shot").map(func(c): return c.target)
	var first_three := order.slice(0, 3)
	_check("rotates through targets shot by shot", first_three.size() == 3 and first_three.has(east)
		and first_three.has(south) and first_three.has(west), str(order.size()))
	for d in [east, south, west]:
		_check("hits every dummy in radius with LOS", _sum(d, &"weapons_free") > 0.0, "")
	_check("ignores a dummy behind a wall", _sum(hidden, &"weapons_free") == 0.0 and not order.has(hidden), "")
	_check("ignores a dummy outside the radius", _sum(far, &"weapons_free") == 0.0 and not order.has(far), "")
	_check("uses no ammo", gun.get_ammo() == ammo and not gun.is_reloading(), "%d vs %d" % [gun.get_ammo(), ammo])
	var fires := _cue_contexts(&"twin_longarms_fire").filter(func(c): return c.extra)
	_check("auto-shots alternate muzzles", fires.size() >= 2 and fires[0].muzzle_index != fires[1].muzzle_index, "")

	# Controls while channelling.
	cues.clear()
	_check("manual LMB is suppressed (silently)", not jose.request_slot(&"primary", east.global_position)
		and _cue_contexts(&"ability_failed").is_empty(), "")
	_check("other abilities are blocked", not jose.request_slot(&"cc", east.global_position)
		and not jose.request_slot(&"ability_1", east.global_position), "")
	_check("recasting Q doesn't end it", not jose.request_slot(&"ultimate", east.global_position) and ult.is_channeling(), "")
	jose.move_direction = Vector2.DOWN
	var flipped := jose.request_slot(&"movement", east.global_position)
	await _seconds(0.3)
	jose.move_direction = Vector2.ZERO
	_check("Flourish is allowed and keeps the channel going", flipped and ult.is_channeling()
		and not _cue_contexts(&"flourish_reload").is_empty(), "")
	_check("the kill box moved with the flip", ult.zone.global_position.distance_to(jose.global_position) < 1.0
		and jose.global_position.y > center.y + 150.0, "")

	# Auto-shots trigger the coin execute.
	var doomed := _dummy(jose.global_position + Vector2(-250, 150), 1000.0, true)
	await _physics_frames(2)
	doomed.status_component.apply(load("res://heroes/jose/data/jose_coin_mark.tres"), jose)
	_set_health(doomed, 150.0)
	hits_log.clear()
	await _seconds(1.0)
	_check("auto-shots can trigger the coin execute", doomed.health_component.is_dead()
		and _sum(doomed, &"coin_execute") > 0.0, "hp %.1f" % doomed.health_component.current_health)

	# A stun ends it.
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.2
	stun.stuns = true
	cues.clear()
	var zone: GroundZone = ult.zone
	jose.status_component.apply(stun)
	await _physics_frames(2)
	_check("a stun ends the channel", not ult.is_channeling() and (not is_instance_valid(zone) or zone.is_queued_for_deletion()), "")
	_check("weapons_free_end cue (interrupted)", not _cue_contexts(&"weapons_free_end").is_empty()
		and _cue_contexts(&"weapons_free_end")[0].interrupted, "")
	_check("abilities unlock and the slow clears", not jose.ability_controller.is_locked()
		and is_equal_approx(jose.movement_component.get_action_multiplier(), 1.0), "")
	await _seconds(0.3)

	# A silence ends it too; an uninterrupted channel ends on its own.
	ult.reset_cooldown()
	jose.request_slot(&"ultimate", east.global_position)
	await _seconds(0.3)
	var silence := StatusEffect.new()
	silence.id = &"test_silence"
	silence.duration = 0.2
	silence.silences = true
	jose.status_component.apply(silence)
	await _physics_frames(2)
	_check("a silence ends the channel", not ult.is_channeling(), "")
	await _seconds(0.3)
	ult.reset_cooldown()
	jose.request_slot(&"ultimate", east.global_position)
	await _seconds(5.4)
	_check("the channel ends after its duration", not ult.is_channeling() and not jose.ability_controller.is_locked(), "")
	_clear_dummies()
	await _physics_frames(2)


# --- Helpers ------------------------------------------------------------------

func _reset(at: Vector2) -> void:
	jose.ability_controller.interrupt()
	jose.status_component.clear()
	jose.movement_component.stop_forced_move()
	jose.global_position = at
	jose.velocity = Vector2.ZERO
	jose.move_direction = Vector2.ZERO
	jose.health_component.reset()
	for ability in jose.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	jose.get_ranged_ability().reload_instantly()


func _dummy(at: Vector2, hp: float = 5000.0, can_die: bool = false) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = can_die
	d.max_health = hp
	d.return_to_anchor = false
	add_child(d)
	dummies.append(d)
	return d


func _clear_dummies() -> void:
	for d in dummies:
		if is_instance_valid(d):
			d.queue_free()
	dummies.clear()


func _aim(at: Vector2) -> void:
	jose.aim_point = at
	jose.aim_direction = (at - jose.global_position).normalized()


func _set_health(d: TrainingDummy, hp: float) -> void:
	var health := d.health_component
	health.apply_damage(DamageInfo.create(health.current_health - hp, null, DamageInfo.Type.TRUE))


# One revolver shot at `at`, waiting out the fire interval first.
func _fire_one(at: Vector2) -> void:
	await _seconds(0.3)
	_aim(at)
	jose.request_slot(&"primary", at)
	await _seconds(0.3)


func _fire_until_empty(at: Vector2, timeout: float) -> void:
	var gun := jose.get_ranged_ability()
	_aim(at)
	var t := 0.0
	while gun.get_ammo() > 0 and t < timeout:
		jose.request_slot(&"primary", at)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


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
