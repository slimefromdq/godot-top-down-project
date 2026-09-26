extends Node2D

# Headless checks for Tilly's kit and the shared pieces it added (placed
# JumpPads + PlacePadData/PlacePadAbility, GroundZoneData death intercept,
# ZoneAbilityData.instant, AbilityData.max_charges, ProjectileData.wall_bounces,
# StatusEffect.DISPLACEMENT_TAKEN).
#
#   godot --headless res://tools/heroes/tilly_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const TILLY := "res://heroes/tilly/tilly_hero.tscn"
const AUDIO_COVERAGE := preload("res://tools/heroes/audio_coverage.gd")
const ALLY := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const MELODY_DEF := "res://heroes/melody/melody_definition.tres"

var failures := 0
var tilly: Hero
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	tilly = load(TILLY).instantiate()
	tilly.team = &"a"
	add_child(tilly)
	var audio = AUDIO_COVERAGE.new(tilly)
	await _physics_frames(3)
	_test_assembled()
	await _test_trampoline_ally()
	await _test_trampoline_expires_and_charges()
	await _test_trampoline_enemy()
	await _test_cartwheel()
	await _test_safety_net()
	await _test_crumple_zone()
	await _test_bouncy_balls()
	await _test_all_eyes()
	_test_audio(audio)

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, tilly.get_ability(slot) != null, "")
	var definition := tilly.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Tilly"
		and definition.title == "The Crash Test Acrobat" and definition.get_role_name() == "Flex", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"tilly"), "")
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 580.0) and _near(stats.health.value_at(10), 1120.0)
		and _near(stats.weapon.value_at(10), 60.0) and _near(stats.magic.value_at(10), 100.0)
		and _near(stats.armor.value_at(10), 38.0) and _near(stats.magic_resist.value_at(10), 40.0), "")
	_check("Trampoline is the shared PlacePadAbility, Safety Net the generic ZoneAbility (data only)",
		tilly.get_ability(&"ability_1").get_script() == PlacePadAbility
		and tilly.get_ability(&"ultimate").get_script() == ZoneAbility, "")
	_check("Bouncy Balls is the generic gun (data only)", tilly.get_ability(&"primary").get_script() == RangedAttackAbility, "")


# --- Trampoline -----------------------------------------------------------------------

# Press at `at`, drag, release at `landing`. Returns the new pad.
func _place_pad(at: Vector2, landing: Vector2) -> JumpPad:
	var trampoline := tilly.get_ability(&"ability_1") as PlacePadAbility
	var before := trampoline.pads.size()
	_aim(at)
	tilly.request_slot(&"ability_1", at)
	await _physics_frames(3)
	_aim(landing)
	tilly.release_slot(&"ability_1", landing)
	await _physics_frames(3)
	return trampoline.pads.back() if trampoline.pads.size() > before else null


func _test_trampoline_ally() -> void:
	print("\n-- Trampoline (ally)")
	_reset(Vector2(0, 0))
	var ally := _ally(Vector2(-300, 0))
	await _physics_frames(2)
	var pad := await _place_pad(Vector2(300, 0), Vector2(800, 400))
	_check("press + drag + release places a pad at the press point", pad != null
		and pad.global_position.distance_to(Vector2(300, 0)) < 1.0, "")
	if pad == null:
		return
	_check("...landing on the dragged spot", pad.get_landing_position().distance_to(Vector2(800, 400)) < 1.0,
		str(pad.get_landing_position()))
	ally.global_position = Vector2(300, 0)
	await _physics_frames(3)
	_check("an ally stepping on it is launched", ally.is_airborne(), "")
	await _until(func(): return not ally.is_airborne(), 1.5)
	_check("...and lands on the dragged spot", ally.global_position.distance_to(Vector2(800, 400)) < 20.0,
		str(ally.global_position))

	var far := await _place_pad(Vector2(-300, 0), Vector2(-300, -3000))
	_check("the landing is clamped to 700 px", far != null
		and absf(far.get_landing_position().distance_to(far.global_position) - 700.0) < 1.0, "")
	var short := await _place_pad(Vector2(0, 300), Vector2(0, 310))
	_check("a short drag lands min_offset along the aim", short == null or short.landing_offset.length() >= 199.0, "")
	_clear_pads()
	_clear()


func _test_trampoline_expires_and_charges() -> void:
	print("\n-- Trampoline (limits)")
	_reset(Vector2(0, 3000))
	var trampoline := tilly.get_ability(&"ability_1") as PlacePadAbility
	_check("2 charges", trampoline.get_max_charges() == 2 and trampoline.get_charges() == 2
		and tilly.get_ability(&"ability_1").get_hud_pips() == Vector2i(2, 2), "")
	var ally := _ally(Vector2(-300, 3000))
	var pad := await _place_pad(Vector2(300, 3000), Vector2(800, 3000))
	_check("placing spends a charge and starts the 16 s recharge", trampoline.get_charges() == 1
		and trampoline.cooldown_remaining > 15.0 and trampoline.is_ready(), "")
	for i in 4:
		if not is_instance_valid(pad):
			break
		ally.global_position = Vector2(300, 3000)
		await _physics_frames(3)
		await _until(func(): return not ally.is_airborne(), 1.5)
		await _physics_frames(2)
	_check("a trampoline expires after 4 launches", not is_instance_valid(pad) or pad.is_queued_for_deletion(), "")
	var second := await _place_pad(Vector2(300, 3000), Vector2(800, 3000))
	_check("the second charge places another", second != null and trampoline.get_charges() == 0, "")
	var third := await _place_pad(Vector2(300, 3100), Vector2(800, 3100))
	_check("no charges left: no third pad", third == null, "")
	trampoline.reduce_cooldown(trampoline.cooldown_remaining - 0.05)
	await _physics_frames(6)
	_check("the recharge brings back one charge and keeps going", trampoline.get_charges() == 1
		and trampoline.cooldown_remaining > 15.0, "%d, %.1f s" % [trampoline.get_charges(), trampoline.cooldown_remaining])
	await _seconds(0.2)
	var lifetime_pad := second
	_check("pads also expire on their own after 10 s", is_instance_valid(lifetime_pad) and _near(lifetime_pad.lifetime, 10.0), "")
	_clear_pads()
	_clear()


func _test_trampoline_enemy() -> void:
	print("\n-- Trampoline (enemy)")
	_reset(Vector2(0, 6000))
	var pad := await _place_pad(Vector2(300, 6000), Vector2(900, 6000))
	var enemy := _ally(Vector2(300, 5750))
	enemy.team = &"b"
	await _physics_frames(2)
	enemy.move_direction = Vector2.DOWN    # walks onto the pad from above
	await _until(func(): return enemy.status_component.has_status(&"tilly_bounce_back"), 1.0)
	enemy.move_direction = Vector2.ZERO
	_check("an enemy stepping on it isn't launched", not enemy.is_airborne(), "")
	_check("...it's bounced back the way it came", enemy.status_component.has_status(&"tilly_bounce_back"), "")
	await _seconds(0.3)
	_check("...ending up back above the pad", enemy.global_position.y < 6000.0 - 100.0, str(enemy.global_position))
	_check("enemy bounces don't use up launches", is_instance_valid(pad) and pad.launches == 0, "")
	_clear_pads()
	_clear()


# --- Cartwheel -------------------------------------------------------------------------------

func _test_cartwheel() -> void:
	print("\n-- Cartwheel")
	_reset(Vector2(0, 9000))
	var cartwheel := tilly.get_ability(&"movement")
	_aim(Vector2(1000, 9000))
	tilly.request_slot(&"movement", Vector2(1000, 9000))
	await _seconds(0.5)
	_check("a 350 px dash", absf(tilly.global_position.x - 350.0) < 25.0, "%.0f" % tilly.global_position.x)
	_check("...with an 8 s cooldown", cartwheel.cooldown_remaining > 7.0, "%.1f" % cartwheel.cooldown_remaining)

	_reset(Vector2(0, 9000))
	await _place_pad(Vector2(330, 9000), Vector2(900, 9000))
	tilly.global_position = Vector2(0, 9000)
	await _physics_frames(2)
	_aim(Vector2(1000, 9000))
	tilly.request_slot(&"movement", Vector2(1000, 9000))
	await _until(func(): return tilly.is_airborne(), 0.8)
	await _physics_frames(2)    # the pad fires first; the dash ends a tick later
	_check("Cartwheel onto her own trampoline launches her", tilly.is_airborne(), "")
	_check("...and resets the cooldown", cartwheel.cooldown_remaining <= 0.0, "%.1f" % cartwheel.cooldown_remaining)
	await _until(func(): return not tilly.is_airborne(), 1.5)
	_check("...landing on the pad's spot", tilly.global_position.distance_to(Vector2(900, 9000)) < 25.0, str(tilly.global_position))
	_clear_pads()


# --- Safety Net ------------------------------------------------------------------------------

func _test_safety_net() -> void:
	print("\n-- Safety Net")
	_reset(Vector2(0, 12000))
	var ally := _ally(Vector2(450, 12000))
	var outside := _ally(Vector2(900, 12000))
	var enemy := _dummy(Vector2(0, 12400))
	enemy.team = &"b"
	await _physics_frames(2)
	tilly.request_slot(&"ultimate", Vector2(300, 12000))
	await _seconds(0.2)    # past the cast's short recovery
	var net: GroundZone = tilly.get_ability(&"ultimate").zone
	_check("Safety Net: a 600 px net around her for 6 s", is_instance_valid(net) and net.data.shape.radius == 600.0
		and _near(net.duration, 6.0), "")
	_check("...cast instantly: she isn't channelling", not tilly.ability_controller.is_busy(), "")
	var saves := []
	if is_instance_valid(net):
		net.death_intercepted.connect(func(h): saves.append(h.owner))
	ally.hurtbox.take_hit(DamageInfo.create(999999.0, enemy))
	var max_hp := ally.health_component.max_health
	_check("a lethal hit on an ally inside leaves them alive", not ally.health_component.is_dead(), "")
	_check("...at 15% health", _near(ally.health_component.current_health, max_hp * 0.15, 1.0),
		"%.0f of %.0f" % [ally.health_component.current_health, max_hp])
	_check("...beside Tilly", ally.global_position.distance_to(tilly.global_position) < 120.0,
		"%.0f px" % ally.global_position.distance_to(tilly.global_position))
	_check("...untargetable for 1 s", ally.status_component.is_untargetable()
		and _near(ally.status_component.get_time_left(&"tilly_saved"), 1.0, 0.05), "")
	_check("the net reports the save", saves == [ally], "")
	ally.status_component.remove(&"tilly_saved")
	ally.hurtbox.take_hit(DamageInfo.create(999999.0, enemy))
	_check("a second lethal hit on the same ally is not intercepted", ally.health_component.is_dead(), "")
	outside.hurtbox.take_hit(DamageInfo.create(999999.0, enemy))
	_check("an ally outside the net isn't saved", outside.health_component.is_dead(), "")
	await _seconds(0.2)
	_clear()


# --- Crumple Zone -----------------------------------------------------------------------------

func _test_crumple_zone() -> void:
	print("\n-- Crumple Zone")
	_reset(Vector2(0, 15000))
	await _physics_frames(2)
	_check("displacements on her are 40% shorter (always on)",
		_near(tilly.status_component.get_multiplier(StatusEffect.DISPLACEMENT_TAKEN), 0.6), "")
	var push := StatusEffect.new()
	push.id = &"test_push"
	push.duration = 0.3
	push.displace_distance = 300.0
	push.displace_duration = 0.2
	tilly.status_component.apply(push, null, Vector2.RIGHT)
	await _seconds(0.4)
	_check("a 300 px knockback moves her 180 px", absf(tilly.global_position.x - 180.0) < 12.0, "%.0f" % tilly.global_position.x)
	tilly.status_component.clear()
	await _physics_frames(2)
	_check("...and it comes back after a cleanse", tilly.status_component.has_status(&"tilly_crumple"), "")

	tilly.launch(tilly.global_position + Vector2(400, 0), 0.5)
	await _until(func(): return not tilly.is_airborne(), 1.0)
	await _physics_frames(1)
	_check("landing from a launch gives +25% move speed", tilly.status_component.has_status(&"tilly_landing")
		and _near(tilly.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.25), "")
	await _seconds(1.6)
	_check("...for 1.5 s", not tilly.status_component.has_status(&"tilly_landing"), "")


# --- Bouncy Balls -----------------------------------------------------------------------------

func _test_bouncy_balls() -> void:
	print("\n-- Bouncy Balls")
	_reset(Vector2(0, 18000))
	var wall := StaticBody2D.new()
	wall.collision_layer = MapLayers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 1200)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(350, 18000)
	add_child(wall)
	spawned.append(wall)
	# Off the straight line: only a ball that bounces off the wall reaches it.
	var target := _dummy(Vector2(180, 18460))
	await _physics_frames(2)
	hits_log.clear()
	_aim(Vector2(300, 18300))
	for i in 3:
		tilly.request_slot(&"primary", Vector2(300, 18300))
		await get_tree().physics_frame
	await _seconds(0.8)
	var hit := hits_log.filter(func(i): return i.target == target and i.label == &"bouncy_balls")
	_check("balls ricochet off walls", not hit.is_empty(), "%d hits" % hit.size())
	_check("2.5 shots/s, two bounces", _near(tilly.get_ranged_ability().get_ranged_data().shots_per_second, 2.5)
		and tilly.get_ranged_ability().get_ranged_data().projectile.wall_bounces == 2, "")
	_clear()


# --- All Eyes on Me ---------------------------------------------------------------------------

func _test_all_eyes() -> void:
	print("\n-- All Eyes on Me")
	_reset(Vector2(0, 21000))
	var enemy := _ally(Vector2(260, 21000))
	enemy.team = &"b"
	var far := _ally(Vector2(0, 21400))
	far.team = &"b"
	await _physics_frames(2)
	tilly.request_slot(&"cc", Vector2(260, 21000))
	await _seconds(0.25)
	_check("enemies within 300 px are taunted toward her", enemy.status_component.is_compelled()
		and enemy.status_component.get_compel_source() == tilly, "")
	_check("...for 1.25 s", enemy.status_component.get_time_left(&"tilly_taunt") <= 1.25
		and enemy.status_component.get_time_left(&"tilly_taunt") > 1.0, "%.2f" % enemy.status_component.get_time_left(&"tilly_taunt"))
	_check("enemies further out aren't", not far.status_component.is_compelled(), "")
	_check("she takes 40% less damage meanwhile", _near(tilly.status_component.get_multiplier(StatusEffect.DAMAGE_TAKEN_PHYSICAL), 0.6)
		and _near(tilly.status_component.get_multiplier(StatusEffect.DAMAGE_TAKEN_MAGIC), 0.6), "")
	var start := enemy.global_position.distance_to(tilly.global_position)
	await _seconds(0.4)
	_check("...and they walk to her", enemy.global_position.distance_to(tilly.global_position) < start - 60.0,
		"%.0f -> %.0f" % [start, enemy.global_position.distance_to(tilly.global_position)])
	_clear()


# --- Helpers ------------------------------------------------------------------------------------

func _reset(at: Vector2) -> void:
	tilly.ability_controller.interrupt()
	tilly.status_component.clear()
	tilly.movement_component.stop_forced_move()
	tilly.global_position = at
	tilly.velocity = Vector2.ZERO
	tilly.move_direction = Vector2.ZERO
	tilly.health_component.reset()
	for ability in tilly.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
		ability._charges = -1
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	tilly.aim_point = at
	tilly.aim_direction = (at - tilly.global_position).normalized()


func _ally(at: Vector2) -> Hero:
	var h: Hero = load(ALLY).instantiate()
	h.team = &"a"
	add_child(h)
	h.global_position = at
	spawned.append(h)
	return h


func _dummy(at: Vector2, hp: float = 50000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	spawned.append(d)
	return d


func _clear_pads() -> void:
	for node in get_tree().get_nodes_in_group(JumpPad.GROUP):
		node.queue_free()


func _clear() -> void:
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	spawned.clear()


func _near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= maxf(tolerance, absf(b) * 0.001)


func _test_audio(audio) -> void:
	print("\n-- Audio")
	for c in audio.checks():
		_check(c[0], c[1], c[2])


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
