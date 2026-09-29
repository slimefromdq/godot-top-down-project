extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for the Biker's kit (and the shared pieces she uses:
# traction, SelfStatusData hold meter + trail, zone detonation and caps,
# contact ram, slam bonus, self_status_on_fire, spin spread).
#
#   godot --headless res://tools/heroes/biker_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const BIKER := "res://heroes/biker/biker_hero.tscn"


func _run() -> void:
	hero = spawn_hero(BIKER)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Biker", "The Hellrider", "Tempo")
	_check("every slot but the ultimate is data only (no Biker script)",
		hero.get_ability(&"primary").get_script() == RangedAttackAbility
		and hero.get_ability(&"ability_1").get_script() == SelfStatusAbility
		and hero.get_ability(&"movement").get_script() == SelfStatusAbility
		and hero.get_ability(&"cc").get_script() == RangedAttackAbility
		and hero.get_ability(&"ultimate").get_script() == RangedAttackAbility)
	await _test_drift()
	await _test_smg()
	await _test_burnout()
	await _test_oil()
	await _test_brake_ram()
	await _test_hellbound()
	test_audio(audio)
	finish()


func _test_drift() -> void:
	print("\n-- Traction (always mounted, drifty)")
	reset(Vector2(0, 0))
	_check("low traction", near(hero.movement_component.get_traction(), 0.5))
	hero.move_direction = Vector2.RIGHT
	await seconds(1.5)
	var top := hero.velocity.length()
	_check("very high top speed", top > 600.0, "%.0f" % top)
	hero.move_direction = Vector2.ZERO
	await seconds(0.25)
	_check("keeps sliding after letting go", hero.velocity.length() > top * 0.4, "%.0f" % hero.velocity.length())
	hero.move_direction = Vector2.LEFT
	await seconds(0.15)
	_check("turning around is slow (drift)", hero.velocity.x > 0.0, "vx %.0f" % hero.velocity.x)
	hero.move_direction = Vector2.ZERO


func _test_smg() -> void:
	print("\n-- Hellfire SMG")
	reset(Vector2(0, 2000))
	var target := dummy(Vector2(300, 2000))
	await frames(2)
	hits_log.clear()
	var gun := hero.get_ranged_ability()
	await hold_slot(&"primary", target.global_position, 1.0)
	var n := hits(target, &"hellfire_smg").size()
	_check("about 10 shots per second", n >= 7 and n <= 11, "%d hits in 1 s" % n)
	_check("spread grows with sustained fire", gun.get_spin() > 0.6, "spin %.2f" % gun.get_spin())
	await seconds(1.0)
	_check("and settles when released", gun.get_spin() < 0.1, "spin %.2f" % gun.get_spin())
	await clear()


func _test_burnout() -> void:
	print("\n-- Burnout")
	reset(Vector2(0, 4000))
	var burnout := hero.get_ability(&"ability_1") as SelfStatusAbility
	burnout.meter = 1.0
	press(&"ability_1", Vector2(400, 4000))
	await frames(2)
	_check("held: +40% top speed", near(hero.movement_component.get_move_speed(), hero.definition.move_speed * 1.4, 1.0),
		"%.0f" % hero.movement_component.get_move_speed())
	hero.move_direction = Vector2.RIGHT
	await seconds(1.0)
	_check("the meter drains (3 s of use)", burnout.meter > 0.55 and burnout.meter < 0.75, "%.2f" % burnout.meter)
	_check("leaves a flame trail", GroundZone.find_owned(get_tree(), hero, &"flame_trail").size() >= 3,
		"%d" % GroundZone.find_owned(get_tree(), hero, &"flame_trail").size())
	hero.release_slot(&"ability_1", hero.aim_point)
	await frames(2)
	_check("released: speed back to normal", not hero.status_component.has_status(&"burnout"))
	var before := burnout.meter
	await seconds(1.0)
	_check("recharges while released (5 s full)", burnout.meter > before + 0.15 and burnout.meter < before + 0.25,
		"%.2f -> %.2f" % [before, burnout.meter])
	burnout.meter = 0.2
	press(&"ability_1", Vector2(400, 4000))
	await seconds(1.0)
	_check("an empty meter ends the hold", not burnout.is_held() and not hero.status_component.has_status(&"burnout"))
	hero.move_direction = Vector2.ZERO
	# The trail burns enemies behind her.
	var chaser := dummy(hero.global_position + Vector2(-80, 0))
	hits_log.clear()
	burnout.meter = 1.0
	press(&"ability_1", hero.global_position + Vector2(400, 0))
	await seconds(1.2)
	hero.release_slot(&"ability_1", hero.aim_point)
	_check("the trail burns", not hits(chaser, &"biker_burn").is_empty())
	await clear()


func _test_oil() -> void:
	print("\n-- Hellfire Oil")
	reset(Vector2(0, 6000))
	var target := dummy(Vector2(400, 6000))
	await frames(2)
	hits_log.clear()
	press(&"cc", target.global_position)
	await until(func(): return find_zone(&"hellfire_oil") != null, 1.5)
	var pool := find_zone(&"hellfire_oil")
	_check("lobs a pool onto the cursor", pool != null and pool.global_position.distance_to(target.global_position) < 20.0)
	await seconds(0.6)
	_check("slows enemies inside (35%)", target.status_component.has_status(&"biker_oil_slow")
		and near(target.status_component.get_multiplier(&"move_speed"), 0.65, 0.01))
	_check("and burns them", not hits(target, &"biker_burn").is_empty())
	for i in 2:
		hero.get_ability(&"cc").cooldown_remaining = 0.0
		press(&"cc", Vector2(400, 6300 + i * 300))
		await seconds(1.0)
	_check("at most 2 pools", GroundZone.find_owned(get_tree(), hero, &"hellfire_oil").size() == 2,
		"%d" % GroundZone.find_owned(get_tree(), hero, &"hellfire_oil").size())
	_check("the oldest went first", not is_instance_valid(pool) or pool.is_queued_for_deletion())
	# Drive over one with Burnout: it detonates.
	await clear()
	reset(Vector2(0, 8000))
	target = dummy(Vector2(400, 8000))
	await frames(2)
	press(&"cc", target.global_position)
	await until(func(): return find_zone(&"hellfire_oil") != null, 1.5)
	hits_log.clear()
	hero.global_position = Vector2(250, 8000)
	await frames(3)
	_check("driving over it without Burnout does nothing", find_zone(&"hellfire_oil") != null)
	press(&"ability_1", Vector2(800, 8000))
	hero.move_direction = Vector2.RIGHT
	await until(func(): return find_zone(&"hellfire_oil") == null, 1.0)
	hero.move_direction = Vector2.ZERO
	hero.release_slot(&"ability_1", hero.aim_point)
	await frames(2)
	_check("Burnout detonates it (the pool is consumed)", find_zone(&"hellfire_oil") == null)
	var blast := total(target, &"oil_detonation")
	_check("the blast hits hard (~150)", blast > 100.0 and blast < 250.0, "%.0f" % blast)
	_check("and leaves a strong 3 s burn", target.status_component.has_status(&"biker_hellburn"))
	_check("the detonate cue fires", cues.has(&"hellfire_oil_detonate"))
	await clear()


func _test_brake_ram() -> void:
	print("\n-- Brake (drift ram)")
	reset(Vector2(0, 10000))
	press(&"movement", Vector2(300, 10000))
	await frames(2)
	_check("braking grips hard (4x)", near(hero.movement_component.get_traction(), 2.0), "%.2f" % hero.movement_component.get_traction())
	var target := dummy(Vector2(160, 10000))
	await frames(2)
	hits_log.clear()
	var start := target.global_position
	hero.velocity = Vector2(500, 0)
	hero.move_direction = Vector2.RIGHT
	await seconds(0.3)
	var rams := hits(target, &"bike_ram")
	_check("sliding into an enemy hits it", rams.size() == 1, "%d hits" % rams.size())
	_check("and knocks it away", target.global_position.distance_to(start) > 120.0,
		"%.0f px" % target.global_position.distance_to(start))
	hero.global_position = target.global_position - Vector2(80, 0)
	hero.velocity = Vector2(500, 0)
	await seconds(0.2)
	_check("once per second per target", hits(target, &"bike_ram").size() == 1)
	hero.move_direction = Vector2.ZERO
	hero.release_slot(&"movement", hero.aim_point)
	await frames(2)
	_check("not while stopped or not braking", not hero.status_component.has_status(&"brake"))
	await clear()
	# Into a wall: the shared slam bonus.
	reset(Vector2(0, 12000))
	var pinned := dummy(Vector2(160, 12000))
	wall(Vector2(290, 12000))
	await frames(2)
	hits_log.clear()
	press(&"movement", Vector2(300, 12000))
	hero.velocity = Vector2(500, 0)
	hero.move_direction = Vector2.RIGHT
	await seconds(0.4)
	hero.move_direction = Vector2.ZERO
	hero.release_slot(&"movement", hero.aim_point)
	_check("a ram into a wall slams (bonus damage)", not hits(pinned, WallSlam.LABEL).is_empty(),
		"%d" % hits(pinned, WallSlam.LABEL).size())
	await clear()


func _test_hellbound() -> void:
	print("\n-- Hellbound")
	reset(Vector2(0, 14000))
	var target := dummy(Vector2(700, 14000))
	await frames(2)
	hits_log.clear()
	press(&"ultimate", target.global_position)
	await seconds(0.3)
	_check("a wind-up first", not hero.status_component.has_status(&"biker_bailed"))
	await until(func(): return hero.status_component.has_status(&"biker_bailed"), 1.0)
	_check("launch: she bails out", hero.status_component.has_status(&"biker_bailed"))
	_check("bailed: slow and on foot", hero.movement_component.get_move_speed() < hero.definition.move_speed * 0.5)
	_check("bailed: bike abilities off, gun still works", hero.get_ability(&"ability_1").get_block_reason() == "Silenced"
		and hero.get_ability(&"primary").get_block_reason() == "")
	await until(func(): return not hits(target, &"hellbound").is_empty(), 2.0)
	var boom := total(target, &"hellbound")
	_check("the bike explodes at the end point for big damage", boom > 300.0, "%.0f" % boom)
	await seconds(1.6)
	_check("a new bike after a short delay", not hero.status_component.has_status(&"biker_bailed"))
	await clear()
