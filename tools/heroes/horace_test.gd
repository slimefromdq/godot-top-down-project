extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for Horace's kit, all generic data: the spin-up minigun,
# PlacedBarrier (Shield Wall), a ChargeData ride, the TURN_RATE / SPREAD
# Overdrive and a lobbed fire zone.
#
#   godot --headless res://tools/heroes/horace_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HORACE := "res://heroes/horace/horace_hero.tscn"


func _run() -> void:
	hero = spawn_hero(HORACE)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Horace", "The Knight with the Minigun", "Carry")
	_check("the whole kit is generic (no Horace scripts)",
		hero.get_ability(&"primary").get_script() == RangedAttackAbility
		and hero.get_ability(&"ability_1").get_script() == PlaceBarrierAbility
		and hero.get_ability(&"movement").get_script() == ChargeAbility
		and hero.get_ability(&"cc").get_script() == SelfStatusAbility
		and hero.get_ability(&"ultimate").get_script() == RangedAttackAbility)
	await _test_minigun()
	await _test_shield_wall()
	await _test_steed()
	await _test_overdrive()
	await _test_dragonfire()
	test_audio(audio)
	finish()


func _test_minigun() -> void:
	print("\n-- Minigun")
	reset(Vector2(0, 0))
	var target := dummy(Vector2(350, 0))
	await frames(2)
	hits_log.clear()
	var gun := hero.get_ranged_ability()
	_check("cold: 3 shots per second", near(1.0 / gun.get_fire_interval(), 3.0, 0.05))
	await hold_slot(&"primary", target.global_position, 0.5)
	var early := hits(target, &"minigun").size()
	await hold_slot(&"primary", target.global_position, 2.0)
	hits_log.clear()
	await hold_slot(&"primary", target.global_position, 1.0)
	var late := hits(target, &"minigun").size()
	_check("spins up to about 20 shots per second after 2 s", late >= 17 and late <= 21, "%d/s (first 0.5 s: %d)" % [late, early])
	_check("full spin is shown on the bar", gun.get_hud_meter() > 0.99)
	await seconds(1.5)
	_check("spins down when released", gun.get_spin() < 0.1, "%.2f" % gun.get_spin())
	await clear()


func _test_shield_wall() -> void:
	print("\n-- Shield Wall")
	reset(Vector2(0, 2000))
	var shooter := spawn_hero(HORACE, &"b", Vector2(800, 2000))
	spawned.append(shooter)
	await frames(2)
	press(&"ability_1", Vector2(300, 2000))
	await seconds(0.3)
	var walls := get_tree().get_nodes_in_group(FrontalBlocker.GROUP).filter(func(b): return b is PlacedBarrier)
	_check("places a barrier toward the aim", walls.size() == 1)
	if walls.is_empty():
		return
	var barrier: PlacedBarrier = walls[0]
	_check("3 charges", barrier.charges == 3)
	hits_log.clear()
	var gun := shooter.get_ranged_ability()
	for i in 2:
		gun.fire_extra_shot(Vector2.LEFT)
		await seconds(0.5)
	_check("each blocked projectile uses a charge", barrier.charges == 1, "%d left" % barrier.charges)
	_check("blocked shots don't reach him", hits(hero, &"minigun").is_empty())
	gun.fire_extra_shot(Vector2.LEFT)
	await seconds(0.5)
	gun.fire_extra_shot(Vector2.LEFT)
	await seconds(0.5)
	_check("empty: shots get through", not hits(hero, &"minigun").is_empty())
	await seconds(2.5)
	_check("lasts 4 s", not is_instance_valid(barrier))
	shooter.queue_free()
	await clear()


func _test_steed() -> void:
	print("\n-- Steed")
	reset(Vector2(0, 4000))
	await frames(2)
	press(&"movement", Vector2(2000, 4000))
	await frames(3)
	_check("no shooting while mounted", not hero.request_slot(&"primary", Vector2(2000, 4000)))
	await seconds(0.8)
	var travelled := hero.global_position.x
	_check("a ~700 px reposition", travelled > 650.0 and travelled < 760.0, "%.0f px" % travelled)
	_check("long cooldown", hero.get_ability(&"movement").get_cooldown() >= 20.0)
	await clear()


func _test_overdrive() -> void:
	print("\n-- Overdrive")
	reset(Vector2(0, 6000))
	var gun := hero.get_ranged_ability()
	var interval := gun.get_fire_interval()
	press(&"cc", Vector2(300, 6000))
	await frames(2)
	var s := hero.status_component
	_check("+30% power, +25% fire rate, twice as accurate", near(s.get_multiplier(&"damage"), 1.3)
		and near(gun.get_fire_interval(), interval / 1.25, 0.001) and near(s.get_multiplier(&"spread"), 0.5))
	# The turn slow: aim straight behind him and see how long it takes.
	hero.aim_direction = Vector2.RIGHT
	await frames(2)
	var turned := 0.0
	for i in 10:
		hero.aim_direction = Vector2.LEFT
		hero.aim_point = hero.global_position + Vector2(-300, 0)
		await get_tree().physics_frame
	turned = rad_to_deg(Vector2.RIGHT.angle_to(hero.aim_direction))
	var expected := GameRules.current().limited_turn_rate_degrees * 0.5 * 10.0 / Engine.physics_ticks_per_second
	_check("turns at half speed (flankers can exploit it)", absf(absf(turned) - expected) < 5.0,
		"%.0f° in 10 ticks, expected %.0f°" % [absf(turned), expected])
	await seconds(6.2)
	hero.aim_direction = Vector2.LEFT
	await frames(2)
	_check("after 6 s he turns freely again", hero.aim_direction.is_equal_approx(Vector2.LEFT))
	await clear()


func _test_dragonfire() -> void:
	print("\n-- Dragonfire")
	reset(Vector2(0, 8000))
	var target := dummy(Vector2(700, 8000))
	var outside := dummy(Vector2(700, 8400))
	await frames(2)
	hits_log.clear()
	press(&"ultimate", target.global_position)
	await until(func(): return find_zone(&"dragonfire") != null, 1.5)
	var zone := find_zone(&"dragonfire")
	_check("fire rains on the cursor", zone != null and zone.global_position.distance_to(target.global_position) < 20.0)
	var at := zone.global_position if zone != null else Vector2.ZERO
	hero.global_position = Vector2(-500, 8000)
	await seconds(2.0)
	_check("and doesn't move", zone != null and is_instance_valid(zone) and zone.global_position == at)
	var dps := total(target, &"dragonfire") / 2.0
	_check("about 40 damage per second", dps > 25.0 and dps < 60.0, "%.0f/s" % dps)
	_check("plus a burn", target.status_component.has_status(&"horace_burn"))
	_check("220 px: nothing outside", hits(outside, &"dragonfire").is_empty())
	await seconds(3.2)
	_check("lasts 5 s", find_zone(&"dragonfire") == null)
	await clear()
