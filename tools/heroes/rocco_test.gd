extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for Rocco's kit, all generic data: a lunging jab combo, a
# charged dash punch, a leap with a landing slam (LaunchData
# landing_hit_shape), a lifesteal cheap shot and a map-crossing charge; every
# knockback is slam-capable (StatusEffect.slam_bonus_ratio, WallSlam).
#
#   godot --headless res://tools/heroes/rocco_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const ROCCO := "res://heroes/rocco/rocco_hero.tscn"


func _run() -> void:
	hero = spawn_hero(ROCCO)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Rocco", "The Heel", "Tempo")
	_check("the whole kit is generic (no Rocco scripts)",
		hero.get_ability(&"primary").get_script() == MeleeAttackAbility
		and hero.get_ability(&"ability_1").get_script() == ChargeAbility
		and hero.get_ability(&"movement").get_script() == LaunchAbility
		and hero.get_ability(&"cc").get_script() == MeleeAttackAbility
		and hero.get_ability(&"ultimate").get_script() == ChargeAbility)
	_check("passive: every knockback he has is slam-capable", _all_knocks_slam())
	await _test_jabs()
	await _test_haymaker()
	await _test_slam()
	await _test_cheap_shot()
	await _test_main_event()
	await _test_wall_slam()
	test_audio(audio)
	finish()


func _all_knocks_slam() -> bool:
	for slot in [&"primary", &"ability_1", &"cc", &"ultimate"]:
		var d: AbilityData = hero.get_ability(slot).data
		var knocks: Array = [d.on_hit_status]
		if d is MeleeAttackData:
			for step in d.combo_steps:
				knocks.append(step.on_hit_status)
		for k in knocks:
			if k != null and k.displace_distance > 0.0 and k.slam_bonus_ratio <= 0.0:
				return false
	return true


func _test_jabs() -> void:
	print("\n-- Jab combo")
	reset(Vector2(0, 0))
	var target := dummy(Vector2(140, 0))
	await frames(2)
	hits_log.clear()
	var start := hero.global_position.x
	await hold_slot(&"primary", target.global_position, 1.0)
	var jabs := hits(target, &"jab_combo")
	_check("a 3-hit combo lands", jabs.size() >= 3, "%d" % jabs.size())
	if not jabs.is_empty():
		_check("~18 damage a jab", jabs[0].amount > 15.0 and jabs[0].amount < 35.0, "%.1f" % jabs[0].amount)
	_check("each jab steps him forward", hero.global_position.x - start > 60.0, "%.0f px" % (hero.global_position.x - start))
	await clear()


func _test_haymaker() -> void:
	print("\n-- Haymaker")
	for full in [false, true]:
		reset(Vector2(0, 2000 + (500 if full else 0)))
		var y := hero.global_position.y
		var target := dummy(Vector2(250, y))
		await frames(2)
		hits_log.clear()
		press(&"ability_1", target.global_position)
		await seconds(1.25 if full else 0.1)
		hero.release_slot(&"ability_1", target.global_position)
		var start := target.global_position.x
		await seconds(0.8)
		var punch := total(target, &"haymaker")
		var pushed := target.global_position.x - start
		if full:
			_check("full charge: ~280+ damage", punch > 260.0, "%.0f" % punch)
			_check("and a 400 px knockback", pushed > 350.0, "%.0f px" % pushed)
		else:
			_check("tap: ~120 damage", punch > 100.0 and punch < 200.0, "%.0f" % punch)
		await clear()


func _test_slam() -> void:
	print("\n-- Top-Rope Slam")
	reset(Vector2(0, 4000))
	var landing := dummy(Vector2(500, 4000))
	await frames(2)
	hits_log.clear()
	press(&"movement", Vector2(420, 4000))
	await seconds(0.2)
	_check("airborne toward the cursor", hero.is_airborne())
	await seconds(0.6)
	_check("lands near the cursor (450 px range)", hero.global_position.distance_to(Vector2(420, 4000)) < 30.0)
	_check("the slam hits around him", not hits(landing, &"jumping_slam").is_empty())
	_check("and slows 40% for 1 s", near(landing.status_component.get_multiplier(&"move_speed"), 0.6))
	await clear()


func _test_cheap_shot() -> void:
	print("\n-- Cheap Shot")
	reset(Vector2(0, 6000))
	var target := dummy(Vector2(110, 6000))
	await frames(2)
	hero.health_component.current_health = 200.0
	hits_log.clear()
	var start := target.global_position.x
	press(&"cc", target.global_position)
	await seconds(0.4)
	var hit := hits(target, &"cheap_shot")
	_check("~50 damage", not hit.is_empty() and hit[0].amount > 45.0 and hit[0].amount < 80.0)
	if not hit.is_empty():
		_check("heals him for 40% of it", near(hero.health_component.current_health, 200.0 + hit[0].final_amount * 0.4, 0.5),
			"%.1f" % hero.health_component.current_health)
	_check("a small knockback", target.global_position.x - start > 100.0)
	await clear()


func _test_main_event() -> void:
	print("\n-- Main Event")
	reset(Vector2(0, 8000))
	var target := dummy(Vector2(900, 8000))
	await frames(2)
	hits_log.clear()
	press(&"ultimate", Vector2(2000, 8000))
	await seconds(1.4)
	_check("crosses ~1500 px", hero.global_position.x > 1350.0, "%.0f px" % hero.global_position.x)
	_check("300 damage to whoever he hits", total(target, &"main_event") > 290.0, "%.0f" % total(target, &"main_event"))
	_check("and knocks them very far", target.global_position.x > 1500.0, "%.0f" % target.global_position.x)
	await clear()


func _test_wall_slam() -> void:
	print("\n-- Wall slam (passive)")
	reset(Vector2(0, 10000))
	var target := dummy(Vector2(110, 10000))
	wall(Vector2(260, 10000))
	await frames(2)
	hits_log.clear()
	var slams: Array = []
	var record := func(victim, _source, bonus, _speed, _at): slams.append([victim, bonus])
	CombatEvents.wall_slammed.connect(record)
	press(&"cc", target.global_position)
	await seconds(0.5)
	var hit := hits(target, &"cheap_shot")
	var bonus := total(target, WallSlam.LABEL)
	_check("a knockback into a wall deals bonus damage", bonus > 0.0, "%.1f" % bonus)
	if not hit.is_empty():
		_check("up to +50% of the hit, by impact speed", bonus <= hit[0].final_amount * 0.5 + 0.1,
			"%.1f of %.1f" % [bonus, hit[0].final_amount])
	_check("reported for VFX and sound (CombatEvents.wall_slammed)", slams.size() == 1 and slams[0][0] == target)
	CombatEvents.wall_slammed.disconnect(record)
	await clear()
	# Open ground: no bonus.
	reset(Vector2(0, 11000))
	var free := dummy(Vector2(110, 11000))
	await frames(2)
	hits_log.clear()
	press(&"cc", free.global_position)
	await seconds(0.5)
	_check("no wall, no bonus", hits(free, WallSlam.LABEL).is_empty())
	await clear()
