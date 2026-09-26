extends Node2D

# Headless checks for Nimbus's kit and the shared pieces it added
# (StatusEffect parry + camera_look_ahead, SelfStatusData.hold_to_keep,
# LaunchData/LaunchAbility + Actor.retarget_launch, Projectile.free_pierce,
# AimLaser).
#
#   godot --headless res://tools/heroes/nimbus_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const NIMBUS := "res://heroes/nimbus/nimbus_hero.tscn"
const AVERY := "res://heroes/avery/avery.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const CARRIES := ["res://heroes/jose/jose_definition.tres", "res://heroes/cosmo/cosmo_definition.tres",
	"res://heroes/rook/rook_definition.tres"]

var failures := 0
var nimbus: Hero
var hits_log: Array[DamageInfo] = []
var cues: Array = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	nimbus = load(NIMBUS).instantiate()
	nimbus.team = &"a"
	add_child(nimbus)
	nimbus.cue_triggered.connect(func(cue, context): cues.append([cue, context]))
	await _physics_frames(3)
	_test_assembled()
	await _test_rifle()
	await _test_steady_hand()
	await _test_scope()
	await _test_parry_projectile()
	await _test_parry_melee()
	await _test_descend()
	await _test_overcast()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, nimbus.get_ability(slot) != null, "")
	var definition := nimbus.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Nimbus"
		and definition.title == "The Gentleman Spy" and definition.get_role_name() == "Carry", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"nimbus"), "")
	var slowest := INF
	for path in CARRIES:
		slowest = minf(slowest, (load(path) as HeroDefinition).move_speed)
	_check("the lowest move speed of any Carry", definition.move_speed < slowest,
		"%d vs %d" % [definition.move_speed, slowest])
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 500.0) and _near(stats.health.value_at(10), 950.0)
		and _near(stats.weapon.value_at(10), 110.0) and _near(stats.magic.value_at(10), 18.0)
		and _near(stats.armor.value_at(10), 30.0) and _near(stats.magic_resist.value_at(10), 24.0), "")
	_check("Scope and Parry are the shared SelfStatusAbility", nimbus.get_ability(&"ability_1").get_script() == SelfStatusAbility
		and nimbus.get_ability(&"cc") is SelfStatusAbility, "")
	_check("Descend is the shared LaunchAbility (data only)", nimbus.get_ability(&"movement").get_script() == LaunchAbility, "")


# --- Umbrella Rifle ------------------------------------------------------------------

func _test_rifle() -> void:
	print("\n-- Umbrella Rifle")
	_reset(Vector2(0, 0))
	var a := _dummy(Vector2(400, 0))
	var b := _dummy(Vector2(600, 0))
	var c := _dummy(Vector2(800, 0))
	await _physics_frames(2)
	var rifle := nimbus.get_ranged_ability()
	_check("semi-auto, 1.1 shots/s, 5 rounds", rifle.get_ranged_data().fire_mode == RangedAttackData.FireMode.SEMI
		and _near(rifle.get_ranged_data().shots_per_second, 1.1) and rifle.get_max_ammo() == 5, "")
	hits_log.clear()
	await _shoot(Vector2(800, 0))
	var weapon := nimbus.stats_component.get_stat(&"weapon")
	_check("1.6 x Weapon per round", _near(_ratio(), 1.6) and not _hits(a).is_empty() and _near(_hits(a)[0].amount, _ratio() * weapon, 0.5),
		"%.1f vs %.1f" % [_hits(a)[0].amount if not _hits(a).is_empty() else 0.0, _ratio() * weapon])
	_check("pierces one target (hits two)", not _hits(b).is_empty() and _hits(c).is_empty(), "")
	_check("no crit without a reason", not _hits(a)[0].has_tag(&"crit") if not _hits(a).is_empty() else false, "")
	_clear()


func _shoot(at: Vector2) -> void:
	_aim(at)
	nimbus.get_ability(&"passive").consume()
	var rifle := nimbus.get_ranged_ability()
	rifle.cooldown_remaining = 0.0
	nimbus.request_slot(&"primary", at)
	await _seconds(0.45)


# --- Steady Hand ------------------------------------------------------------------------

func _test_steady_hand() -> void:
	print("\n-- Steady Hand")
	_reset(Vector2(0, 3000))
	var target := _dummy(Vector2(400, 3000))
	var passive := nimbus.get_ability(&"passive")
	passive.consume()
	await _seconds(4.15)
	_check("+40% after 4 s standing still", _near(passive.get_bonus(), 0.4) and passive.get_hud_pips() == Vector2i(4, 4),
		"%.2f" % passive.get_bonus())
	await _seconds(1.0)
	_check("...and no higher", _near(passive.get_bonus(), 0.4), "%.2f" % passive.get_bonus())
	hits_log.clear()
	_aim(target.global_position)
	nimbus.request_slot(&"primary", target.global_position)
	await _seconds(0.3)
	var weapon := nimbus.stats_component.get_stat(&"weapon")
	_check("the next shot deals +40%", not _hits(target).is_empty() and _near(_hits(target)[0].amount, _ratio() * weapon * 1.4, 0.5),
		"%.1f" % (_hits(target)[0].amount if not _hits(target).is_empty() else 0.0))
	_check("...and spends it", passive.get_bonus() < 0.11, "%.2f" % passive.get_bonus())
	await _seconds(2.1)
	_check("it builds again", passive.get_bonus() >= 0.2, "%.2f" % passive.get_bonus())
	nimbus.move_direction = Vector2.RIGHT
	await _seconds(0.3)
	nimbus.move_direction = Vector2.ZERO
	_check("moving resets it", passive.get_bonus() == 0.0, "%.2f" % passive.get_bonus())
	_clear()


# --- Scope --------------------------------------------------------------------------------

func _test_scope() -> void:
	print("\n-- Scope")
	_reset(Vector2(0, 6000))
	var camera := ShakeCamera.new()
	nimbus.add_child(camera)
	var target := _dummy(Vector2(500, 6000))
	await _physics_frames(2)
	_aim(Vector2(1000, 6000))
	var scope := nimbus.get_ability(&"ability_1")
	nimbus.request_slot(&"ability_1", Vector2(1000, 6000))
	await _seconds(0.15)
	var status := nimbus.status_component
	_check("holding Scope keeps its status on", scope.is_held() and status.has_status(&"nimbus_scoped"), "")
	_check("-40% move speed while scoped", _near(status.get_multiplier(StatusEffect.MOVE_SPEED), 0.6), "")
	_check("the aim laser shows (to everyone)", nimbus.visuals.get_status_vfx(&"nimbus_scoped") is AimLaser
		and (nimbus.get_ability(&"ability_1").data.self_status as StatusEffect).vfx_visible_to == StatusEffect.VfxVisibleTo.EVERYONE, "")
	await _seconds(1.2)
	_check("the camera looks 500 px ahead toward the cursor", camera.get_look_offset().distance_to(Vector2(500, 0)) < 15.0,
		str(camera.get_look_offset()))
	hits_log.clear()
	nimbus.get_ranged_ability().cooldown_remaining = 0.0
	nimbus.request_slot(&"primary", target.global_position)
	await _seconds(0.3)
	_check("he can shoot while scoped", not _hits(target).is_empty() and status.has_status(&"nimbus_scoped"), "")
	nimbus.release_slot(&"ability_1", Vector2(1000, 6000))
	await _physics_frames(1)
	_check("letting go ends it", not scope.is_held() and not status.has_status(&"nimbus_scoped")
		and _near(status.get_multiplier(StatusEffect.MOVE_SPEED), 1.0), "")
	await _seconds(1.2)
	_check("the camera eases back", camera.get_look_offset().length() < 15.0, str(camera.get_look_offset()))
	camera.queue_free()
	_clear()


# --- Parry ---------------------------------------------------------------------------------

func _test_parry_projectile() -> void:
	print("\n-- Parry (projectile)")
	_reset(Vector2(0, 9000))
	var shooter := _dummy(Vector2(260, 9000))
	shooter.team = &"b"
	await _physics_frames(2)
	var parry := nimbus.get_ability(&"cc")
	nimbus.request_slot(&"cc", Vector2(260, 9000))
	await _physics_frames(2)
	_check("Parry opens a 0.35 s window", nimbus.status_component.has_status(&"nimbus_parry")
		and nimbus.status_component.get_time_left(&"nimbus_parry") <= 0.35, "")
	hits_log.clear()
	var nimbus_hp := nimbus.health_component.current_health
	var template := DamageInfo.create(30.0, shooter)
	template.label = &"dummy_bolt"
	Projectile.fire(shooter, shooter.attack_projectile, shooter.global_position + Vector2.LEFT * 60.0, Vector2.LEFT, template)
	await _seconds(0.6)
	var back := hits_log.filter(func(i): return i.target == shooter and i.label == &"dummy_bolt")
	_check("a dummy's bolt reflected by Parry damages that dummy", back.size() == 1 and back[0].has_tag(Projectile.TAG_REFLECTED)
		and back[0].source == nimbus, "")
	_check("Nimbus takes nothing", nimbus.health_component.current_health == nimbus_hp, "")
	_check("the window closes on success", not nimbus.status_component.has_status(&"nimbus_parry"), "")
	_check("success refunds half the cooldown", parry.cooldown_remaining <= parry.get_cooldown() * 0.5 + 0.01,
		"%.2f of %.2f" % [parry.cooldown_remaining, parry.get_cooldown()])
	_check("...and makes the next shot a guaranteed crit", nimbus.get_ranged_ability().has_crit_ready(), "")

	var target := _dummy(Vector2(400, 9000))
	await _physics_frames(2)
	hits_log.clear()
	await _shoot(Vector2(400, 9000))
	var weapon := nimbus.stats_component.get_stat(&"weapon")
	var crit := _hits(target)
	_check("the next shot crits (1.75x)", not crit.is_empty() and crit[0].has_tag(&"crit")
		and _near(crit[0].amount, _ratio() * weapon * 1.75, 0.5), "%.1f" % (crit[0].amount if not crit.is_empty() else 0.0))
	hits_log.clear()
	await _seconds(0.6)    # the rifle's fire interval (1.1 shots/s)
	await _shoot(Vector2(400, 9000))
	_check("...only the next one", not _hits(target).is_empty() and not _hits(target)[0].has_tag(&"crit"), "")

	# No projectile inside the window: no refund.
	parry.cooldown_remaining = 0.0
	nimbus.request_slot(&"cc", Vector2(260, 9000))
	await _seconds(0.5)
	_check("a whiffed Parry keeps its full cooldown", parry.cooldown_remaining > parry.get_cooldown() * 0.9,
		"%.2f" % parry.cooldown_remaining)
	_clear()


func _test_parry_melee() -> void:
	print("\n-- Parry (melee)")
	_reset(Vector2(0, 12000))
	var avery: Hero = load(AVERY).instantiate()
	avery.team = &"b"
	add_child(avery)
	spawned.append(avery)
	avery.global_position = Vector2(110, 12000)
	await _physics_frames(3)
	nimbus.get_ability(&"cc").cooldown_remaining = 0.0
	nimbus.request_slot(&"cc", avery.global_position)
	await _physics_frames(2)
	hits_log.clear()
	avery.aim_direction = Vector2.LEFT
	avery.aim_point = nimbus.global_position
	avery.request_slot(&"primary", nimbus.global_position)
	await _seconds(0.35)
	# Her swing also throws a crescent (a projectile): only the blade is melee.
	var blade := hits_log.filter(func(i): return i.target == nimbus and i.has_tag(DamageInfo.TAG_MELEE))
	_check("a melee hit inside the window is stopped", blade.is_empty(), "%d melee hits" % blade.size())
	_check("...and the attacker is stunned 0.5 s", avery.status_component.has_status(&"nimbus_parry_stun"), "")
	_clear()


# --- Descend --------------------------------------------------------------------------------

func _test_descend() -> void:
	print("\n-- Descend")
	_reset(Vector2(0, 15000))
	var low := _low_cover(Vector2(300, 15000))
	await _physics_frames(2)
	var descend := nimbus.get_ability(&"movement")
	_aim(Vector2(900, 15000))
	nimbus.request_slot(&"movement", Vector2(900, 15000))
	await _physics_frames(3)
	_check("Descend launches him", nimbus.is_airborne(), "")
	await _seconds(1.7)
	_check("...over a ledge / low cover, landing on the cursor", not nimbus.is_airborne()
		and nimbus.global_position.distance_to(Vector2(900, 15000)) < 20.0, str(nimbus.global_position))
	_check("1.6 s in the air, 22 s cooldown", _near(descend.data.air_time, 1.6) and _near(descend.get_cooldown(), 22.0), "")

	# Steering: hold "down" in flight.
	_reset(Vector2(0, 15000))
	_aim(Vector2(900, 15000))
	nimbus.request_slot(&"movement", Vector2(900, 15000))
	await _physics_frames(3)
	nimbus.move_direction = Vector2.DOWN
	await _until(func(): return not nimbus.is_airborne(), 2.0)
	nimbus.move_direction = Vector2.ZERO
	var landed := nimbus.global_position
	_check("move input steers the landing point", landed.y - 15000.0 > 300.0, str(landed))
	_check("...never past 1100 px from take-off", landed.distance_to(Vector2(0, 15000)) <= 1101.0,
		"%.0f px" % landed.distance_to(Vector2(0, 15000)))

	_reset(Vector2(0, 15000))
	_aim(Vector2(3000, 15000))
	nimbus.request_slot(&"movement", Vector2(3000, 15000))
	await _until(func(): return nimbus.is_airborne(), 0.5)
	await _until(func(): return not nimbus.is_airborne(), 2.0)
	_check("a far cursor is clamped to 1100 px", absf(nimbus.global_position.x - 1100.0) < 20.0, str(nimbus.global_position))
	low.queue_free()


# --- Overcast ---------------------------------------------------------------------------------

func _test_overcast() -> void:
	print("\n-- Overcast")
	_reset(Vector2(0, 18000))
	var a := _dummy(Vector2(700, 18000))
	var b := _dummy(Vector2(900, 18000))
	var c := _dummy(Vector2(1100, 18000))
	a.team = &"b"
	b.team = &"b"
	c.team = &"b"
	var bush := Bush.new()
	bush.radius = 120.0
	bush.position = Vector2(900, 18000)
	add_child(bush)
	spawned.append(bush)
	await _physics_frames(3)
	_check("an enemy in a bush is hidden before Overcast", not CombatQueries.has_line_of_sight(nimbus, b), "")
	nimbus.request_slot(&"ultimate", Vector2(900, 18000))
	await _physics_frames(3)
	var cloud: GroundZone = nimbus.get_ability(&"ultimate").cloud
	_check("a 500 px cloud lands on the cursor for 6 s", is_instance_valid(cloud) and cloud.global_position.distance_to(Vector2(900, 18000)) < 1.0
		and cloud.data.shape.radius == 500.0 and _near(cloud.duration, 6.0), "")
	_check("enemies under it are revealed, even in a bush", CombatQueries.is_revealed(b) and CombatQueries.has_line_of_sight(nimbus, b), "")
	_check("...and slowed 15%", _near(a.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 0.85), "")
	hits_log.clear()
	await _shoot(Vector2(1100, 18000))
	var weapon := nimbus.stats_component.get_stat(&"weapon")
	var all_hit := [a, b, c].all(func(d): return _hits(d).size() == 1 and _hits(d)[0].has_tag(&"crit"))
	_check("shots into it crit and pierce everyone inside", all_hit,
		"hits %d/%d/%d" % [_hits(a).size(), _hits(b).size(), _hits(c).size()])
	_check("...at 1.75x", not _hits(a).is_empty() and _near(_hits(a)[0].amount, _ratio() * weapon * 1.75, 0.5), "")
	var far_cast := Vector2(10000, 18000)
	nimbus.get_ability(&"ultimate").cooldown_remaining = 0.0
	nimbus.request_slot(&"ultimate", far_cast)
	await _physics_frames(3)
	var far_cloud: GroundZone = nimbus.get_ability(&"ultimate").cloud
	_check("range: anywhere within two screens (3600 px)", is_instance_valid(far_cloud)
		and absf(far_cloud.global_position.distance_to(nimbus.global_position) - 3600.0) < 2.0, "")
	for zone in [cloud, far_cloud]:
		if is_instance_valid(zone):
			zone.end()
	_clear()


# --- Helpers -----------------------------------------------------------------------------------

# The rifle's Weapon ratio, from its data (1.6).
func _ratio() -> float:
	return nimbus.get_ranged_ability().data.damage.weapon_ratio


func _hits(target: Node) -> Array:
	return hits_log.filter(func(i): return i.target == target and i.label == &"umbrella_rifle")


func _low_cover(at: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = MapLayers.LOW_COVER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 800)
	shape.shape = rect
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _reset(at: Vector2) -> void:
	nimbus.ability_controller.interrupt()
	nimbus.status_component.clear()
	nimbus.movement_component.stop_forced_move()
	nimbus.global_position = at
	nimbus.velocity = Vector2.ZERO
	nimbus.move_direction = Vector2.ZERO
	nimbus.health_component.reset()
	nimbus.get_ranged_ability().reload_instantly()
	for ability in nimbus.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	nimbus.aim_point = at
	nimbus.aim_direction = (at - nimbus.global_position).normalized()


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
