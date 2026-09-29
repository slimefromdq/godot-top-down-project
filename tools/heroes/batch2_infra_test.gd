extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for the shared pieces added with hero batch 2 (Biker,
# Horace, Mochi, Computer, Catgirl, Rocco), each built in code on the plain
# Ranged Test hero so they are tested apart from any hero's data:
#
#   traction (MovementComponent.traction, StatusEffect.TRACTION), the wall
#   slam bonus (slam_bonus_ratio, WallSlam), StackCounter, Deployable +
#   DeployData/DeployAbility (and cleanup), zone detonation / owner trigger
#   / per-owner cap, spin-up guns and SPREAD, PlacedBarrier, Mote steal and
#   agent pickup, contact ram, the SelfStatusData hold meter + trail,
#   LaunchData landing slam, TURN_RATE, silence_spares_primary, `harmful`,
#   self_status_on_fire and HeroDefinition.ult_charge_rate.
#
#   godot --headless res://tools/heroes/batch2_infra_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO_SCENE := preload("res://scenes/heroes/hero_base.tscn")
const TEST_HERO := preload("res://tools/heroes/ranged_test/ranged_test_definition.tres")
const SMALL_MOTE := "res://resources/match/small_mote.tres"


func _run() -> void:
	hero = _plain(&"a", Vector2.ZERO)
	await frames(3)
	await _test_traction()
	await _test_wall_slam()
	_test_stack_counter()
	await _test_deployable()
	await _test_zone_detonation()
	await _test_spin_up()
	await _test_barrier()
	await _test_motes()
	await _test_contact_ram()
	await _test_hold_meter()
	await _test_launch_slam()
	await _test_turn_rate()
	await _test_silence_and_harmful()
	await _test_ult_charge_rate()
	await _test_gadgets_hero()
	finish()


func _plain(team: StringName, at: Vector2, definition: HeroDefinition = TEST_HERO) -> Hero:
	var h: Hero = HERO_SCENE.instantiate()
	h.definition = definition
	h.team = team
	h.position = at
	add_child(h)
	return h


func _status(id: StringName, props: Dictionary) -> StatusEffect:
	var s := StatusEffect.new()
	s.id = id
	for k in props:
		if k == "stat_multipliers":
			var typed: Dictionary[StringName, float] = {}
			for key in props[k]:
				typed[key] = props[k][key]
			s.stat_multipliers = typed
		else:
			s.set(k, props[k])
	return s


func _test_traction() -> void:
	print("\n-- Traction")
	reset(Vector2.ZERO)
	var movement := hero.movement_component
	_check("default grip is 1 (heroes that don't opt in are unchanged)", near(movement.get_traction(), 1.0))
	hero.move_direction = Vector2.RIGHT
	await seconds(0.1)
	var normal := hero.velocity.length()
	reset(Vector2.ZERO)
	hero.status_component.apply(_status(&"ice", {"duration": 5.0, "stat_multipliers": {&"traction": 0.25}}))
	hero.move_direction = Vector2.RIGHT
	await seconds(0.1)
	var slippery := hero.velocity.length()
	_check("a TRACTION 0.25 status: velocity follows input 4x slower", near(slippery, normal * 0.25, normal * 0.05),
		"%.0f vs %.0f" % [slippery, normal])
	await seconds(1.5)
	var top := hero.velocity.length()
	hero.move_direction = Vector2.ZERO
	await seconds(0.1)
	_check("and slides on after letting go", hero.velocity.length() > top * 0.75, "%.0f of %.0f" % [hero.velocity.length(), top])
	movement.traction = 0.5
	_check("a hero's own traction stacks with it", near(movement.get_traction(), 0.125))
	movement.traction = 1.0
	hero.status_component.clear()


func _test_wall_slam() -> void:
	print("\n-- Wall slam bonus")
	for flagged in [false, true]:
		reset(Vector2(0, 2000 + (400 if flagged else 0)))
		var y := hero.global_position.y
		var target := dummy(Vector2(100, y))
		wall(Vector2(260, y))
		await frames(2)
		hits_log.clear()
		var push := _status(&"push", {"duration": 0.2, "displace_distance": 300.0, "displace_duration": 0.15,
			"displace_direction": StatusEffect.DisplaceDirection.AWAY_FROM_SOURCE, "slam_bonus_ratio": 0.5 if flagged else 0.0})
		var info := DamageInfo.create(100.0, hero)
		info.direction = Vector2.RIGHT
		info.add_status(push)
		target.hurtbox.take_hit(info)
		await seconds(0.3)
		var slams := hits(target, WallSlam.LABEL)
		var bonus: float = slams[0].amount if not slams.is_empty() else 0.0
		if flagged:
			var speed := 300.0 / 0.15
			var expected := WallSlam.bonus_for(50.0, speed)
			_check("slam-capable push into a wall: bonus scaled by impact speed", near(bonus, expected, 2.0),
				"%.1f vs %.1f (impact %.0f px/s of %.0f)" % [bonus, expected, speed, GameRules.current().wall_slam_full_speed])
		else:
			_check("an unflagged push slams for nothing extra", bonus == 0.0)
		await clear()
	_check("full bonus at full speed", near(WallSlam.bonus_for(50.0, 99999.0), 50.0))


func _test_stack_counter() -> void:
	print("\n-- StackCounter")
	var a := Node.new()
	var b := Node.new()
	var victim := Node.new()
	for i in 4:
		StackCounter.add(a, &"k", victim, 5, 3.0, 1.5)
	_check("stacks count up", StackCounter.get_stacks(a, &"k", victim) == 4)
	_check("per source: another owner has its own", StackCounter.get_stacks(b, &"k", victim) == 0)
	_check("the 5th fills it", StackCounter.add(a, &"k", victim, 5, 3.0, 1.5))
	_check("then it's empty and immune", StackCounter.get_stacks(a, &"k", victim) == 0 and StackCounter.is_immune(a, &"k", victim))
	_check("adds during immunity do nothing", not StackCounter.add(a, &"k", victim, 1, 3.0, 1.5))
	StackCounter.add(b, &"k", victim, 5, 0.0, 0.0)
	_check("decay (0 s here): stale stacks read 0", StackCounter.get_stacks(b, &"k", victim, 0.0) <= 1)
	for n in [a, b, victim]:
		n.free()


func _test_deployable() -> void:
	print("\n-- Deployable")
	reset(Vector2(0, 4000))
	var data := DeployData.new()
	data.id = &"test_turret"
	data.ability_script = DeployAbility
	data.deployable_script = TurretDeployable
	data.deploy_health = ScalingValue.new()
	data.deploy_health.base = 150.0
	data.lifetime = 1.0
	data.max_per_owner = 2
	data.projectile = load("res://tools/heroes/ranged_test/data/ranged_test_bullet.tres")
	data.damage = ScalingValue.new()
	data.damage.base = 5.0
	data.values = {&"range": _sv(500.0), &"fire_rate": _sv(5.0)} as Dictionary[StringName, ScalingValue]
	var enemy := dummy(Vector2(300, 4000))
	var turrets: Array[Deployable] = []
	for i in 3:
		turrets.append(Deployable.spawn(hero, data, Vector2(0, 4100 + i * 50), &"test_turret"))
	await frames(2)
	_check("owner, team and health", turrets[2].owner_actor == hero and turrets[2].team == &"a"
		and near(turrets[2].health_component.max_health, 150.0))
	_check("find_owned lists them, oldest first", Deployable.find_owned(hero, &"test_turret")[0] == turrets[0])
	hits_log.clear()
	await seconds(0.5)
	_check("a TurretDeployable shoots enemies in range as its owner",
		hits_log.any(func(i): return i.target == enemy and i.source == hero))
	await seconds(0.6)
	_check("lifetime ends it", Deployable.find_owned(hero, &"test_turret").is_empty())
	# DeployAbility enforces the cap.
	var ability: DeployAbility = DeployAbility.new()
	ability.set_data(data)
	hero.ability_controller.add_ability(ability, &"")
	data.lifetime = 0.0
	ability.set_data(data)
	for i in 3:
		ability.cooldown_remaining = 0.0
		ability.start_cast(Vector2(100, 4000))
		await seconds(0.3)
	_check("DeployAbility keeps max_per_owner (oldest replaced)", ability.get_deployed().size() == 2)
	hero.ability_controller.remove_ability(ability)
	ability.queue_free()
	for d in Deployable.find_owned(hero):
		d.remove()
	await clear()


func _sv(v: float) -> ScalingValue:
	var s := ScalingValue.new()
	s.base = v
	return s


func _test_zone_detonation() -> void:
	print("\n-- Zone detonation")
	reset(Vector2(0, 6000))
	var blast := ProjectileData.new()
	blast.explosion_shape = HitShape.circle(120.0)
	blast.explosion_damage = _sv(77.0)
	var pool := GroundZoneData.new()
	pool.shape = HitShape.circle(80.0)
	pool.duration = 10.0
	pool.meter_label = &"test_pool"
	pool.detonation = blast
	pool.detonated_by_owner_status = &"test_trigger"
	pool.max_per_owner = 2
	var target := dummy(Vector2(400, 6000))
	await frames(2)
	var zones: Array[GroundZone] = []
	for i in 3:
		zones.append(GroundZone.spawn(hero, pool, Vector2(400 + i, 6000), Vector2.RIGHT, hero))
	await frames(1)
	_check("max_per_owner ends the oldest", not is_instance_valid(zones[0]) or zones[0].is_queued_for_deletion())
	hits_log.clear()
	zones[1].detonate()
	await frames(1)
	var blasts := hits(target, &"test_pool_detonation")
	_check("detonate(): the template explodes as the owner's hit", blasts.size() == 1 and near(blasts[0].amount, 77.0, 0.5)
		and blasts[0].source == hero)
	_check("and consumes the zone", not is_instance_valid(zones[1]) or zones[1].is_queued_for_deletion())
	hero.global_position = Vector2(402, 6000)
	await frames(2)
	_check("the owner standing in it does nothing without the status", is_instance_valid(zones[2]) and not zones[2].is_queued_for_deletion())
	hero.status_component.apply(_status(&"test_trigger", {"duration": 1.0}))
	await frames(2)
	_check("with the status it detonates", not is_instance_valid(zones[2]) or zones[2].is_queued_for_deletion())
	await clear()


func _test_spin_up() -> void:
	print("\n-- Spin up")
	reset(Vector2(0, 8000))
	var gun := hero.get_ranged_ability()
	var ranged := gun.get_ranged_data()
	var saved := [ranged.spin_up_time, ranged.spin_start_rate, ranged.spin_cold_spread_degrees, ranged.spin_down_time]
	ranged.spin_up_time = 1.0
	ranged.spin_start_rate = 0.25
	ranged.spin_down_time = 0.5
	var full_interval := ranged.get_fire_interval()
	_check("cold: spin_start_rate of the fire rate", near(gun.get_fire_interval(), full_interval * 4.0, 0.001))
	await hold_slot(&"primary", Vector2(400, 8000), 1.3)
	_check("held: spins up to full rate", near(gun.get_fire_interval(), full_interval, 0.001) and near(gun.get_spin(), 1.0))
	var hold := 1.0 / (ranged.shots_per_second * ranged.spin_start_rate) + 0.1
	await seconds(hold + 0.6)
	_check("released: spins down", gun.get_spin() == 0.0, "%.2f" % gun.get_spin())
	hero.status_component.apply(_status(&"steady", {"duration": 1.0, "stat_multipliers": {&"spread": 0.0}}))
	var angles := []
	for i in 5:
		angles.append(gun._spread_angle(0, 1))
	_check("SPREAD 0: dead accurate", angles.all(func(a): return a == 0.0) or ranged.spread_degrees == 0.0)
	ranged.spin_up_time = saved[0]
	ranged.spin_start_rate = saved[1]
	ranged.spin_cold_spread_degrees = saved[2]
	ranged.spin_down_time = saved[3]
	hero.status_component.clear()
	await clear()


func _test_barrier() -> void:
	print("\n-- PlacedBarrier")
	reset(Vector2(0, 10000))
	var enemy := _plain(&"b", Vector2(700, 10000))
	spawned.append(enemy)
	await frames(2)
	var barrier := PlacedBarrier.place(hero, Vector2(200, 10000), Vector2.RIGHT, {"radius": 100.0, "arc_degrees": 120.0,
		"max_charges": 2, "recharge_time": 0.5, "lifetime": 3.0})
	hits_log.clear()
	var gun := enemy.get_ranged_ability()
	gun.fire_extra_shot(Vector2.LEFT)
	await seconds(0.5)
	_check("an enemy projectile uses a charge instead of hitting", barrier.charges == 1 and hits(hero, gun.data.get_label()).is_empty())
	await seconds(0.6)
	_check("charges come back", barrier.charges == 2)
	var own := hero.get_ranged_ability()
	hits_log.clear()
	own.fire_extra_shot(Vector2.RIGHT)
	await seconds(0.5)
	_check("the owner's side shoots through it", not hits(enemy, own.data.get_label()).is_empty() and barrier.charges == 2)
	await seconds(2.0)
	_check("lifetime ends it", not is_instance_valid(barrier))
	await clear()


func _test_motes() -> void:
	print("\n-- Mote steal and agent pickup")
	reset(Vector2(0, 12000))
	var other := _plain(&"b", Vector2(0, 12400))
	spawned.append(other)
	await frames(2)
	var data: MoteData = load(SMALL_MOTE)
	var thief := MoteCarrier.find_on(hero)
	var victim := MoteCarrier.find_on(other)
	thief.clear()
	victim.clear()
	for i in 3:
		victim.add_mote(data, i + 1)
	_check("steal_from moves Motes between carriers", thief.steal_from(victim, 2) == 2 and thief.get_mote_count() == 2
		and victim.get_mote_count() == 1)
	_check("the last picked up go first", thief.get_mote_value() == 5)
	var mote := Mote.spawn(self, data, Vector2(3000, 12000))
	await frames(1)
	_check("an agent can take an idle Mote", mote.can_be_taken_by_agent(&"a"))
	var taken := mote.take_by_agent(&"a")
	_check("take_by_agent hands its data over and removes it", taken.get("value", 0) == data.value and mote.is_queued_for_deletion())
	thief.clear()
	victim.clear()
	await clear()


func _test_contact_ram() -> void:
	print("\n-- Contact ram")
	reset(Vector2(0, 14000))
	var target := dummy(Vector2(120, 14000))
	await frames(2)
	hits_log.clear()
	var ram := _status(&"ram", {"duration": 2.0, "contact_radius": 80.0, "contact_damage": _sv(30.0),
		"contact_min_speed": 100.0, "contact_rehit_time": 1.0, "contact_label": &"test_ram"})
	hero.status_component.apply(ram, hero)
	await frames(3)
	_check("standing still: no ram", hits(target, &"test_ram").is_empty())
	hero.move_direction = Vector2.RIGHT
	await seconds(0.4)
	_check("moving into an enemy: one ram", hits(target, &"test_ram").size() == 1 and near(hits(target, &"test_ram")[0].amount, 30.0))
	await seconds(0.3)
	_check("once per rehit time", hits(target, &"test_ram").size() == 1)
	hero.move_direction = Vector2.ZERO
	await clear()


func _test_hold_meter() -> void:
	print("\n-- Hold meter and trail")
	reset(Vector2(0, 16000))
	var data := SelfStatusData.new()
	data.id = &"test_hold"
	data.ability_script = SelfStatusAbility
	data.cooldown = 0.0
	data.self_status = _status(&"test_hold", {"duration": 10.0})
	data.hold_to_keep = true
	data.hold_meter_seconds = 1.0
	data.hold_meter_recharge_seconds = 2.0
	data.hold_trail_zone = GroundZoneData.new()
	data.hold_trail_zone.shape = HitShape.circle(30.0)
	data.hold_trail_zone.meter_label = &"test_trail"
	data.hold_trail_spacing = 40.0
	data.feel_override = AttackFeel.new()
	data.feel_override.windup = 0.0
	var ability := SelfStatusAbility.new()
	ability.set_data(data)
	hero.ability_controller.add_ability(ability, &"")
	await frames(1)
	ability.start_cast(hero.global_position)
	await frames(1)
	hero.move_direction = Vector2.RIGHT
	await seconds(0.5)
	_check("held: the meter drains", ability.is_held() and near(ability.meter, 0.5, 0.05), "%.2f" % ability.meter)
	_check("the trail is laid while moving", GroundZone.find_owned(get_tree(), hero, &"test_trail").size() >= 3)
	await seconds(0.6)
	_check("empty: the hold ends", not ability.is_held() and not hero.status_component.has_status(&"test_hold"))
	_check("can't start empty", ability.get_block_reason() == "Empty")
	await seconds(1.0)
	_check("refills while released", near(ability.meter, 0.5, 0.1), "%.2f" % ability.meter)
	hero.move_direction = Vector2.ZERO
	hero.ability_controller.remove_ability(ability)
	ability.queue_free()
	await clear()


func _test_launch_slam() -> void:
	print("\n-- LaunchData landing slam")
	reset(Vector2(0, 18000))
	var data := LaunchData.new()
	data.id = &"test_leap"
	data.ability_script = LaunchAbility
	data.max_distance = 300.0
	data.air_time = 0.3
	data.landing_hit_shape = HitShape.circle(120.0)
	data.damage = _sv(25.0)
	data.on_hit_status = _status(&"test_slow", {"duration": 1.0, "stat_multipliers": {&"move_speed": 0.5}})
	data.feel_override = AttackFeel.new()
	data.feel_override.windup = 0.0
	var ability := LaunchAbility.new()
	ability.set_data(data)
	hero.ability_controller.add_ability(ability, &"")
	var near_target := dummy(Vector2(300, 18080))
	var far_target := dummy(Vector2(300, 18300))
	await frames(2)
	hits_log.clear()
	ability.start_cast(Vector2(300, 18000))
	await seconds(0.5)
	var slam := hits(near_target, &"test_leap")
	_check("the landing hits and applies on_hit_status around it", slam.size() == 1 and near(slam[0].amount, 25.0)
		and near_target.status_component.has_status(&"test_slow"))
	_check("only inside the landing shape", hits(far_target, &"test_leap").is_empty())
	hero.ability_controller.remove_ability(ability)
	ability.queue_free()
	await clear()


func _test_turn_rate() -> void:
	print("\n-- TURN_RATE")
	reset(Vector2(0, 20000))
	hero.aim_direction = Vector2.RIGHT
	await frames(1)
	hero.status_component.apply(_status(&"heavy", {"duration": 2.0, "stat_multipliers": {&"turn_rate": 0.5}}))
	for i in 6:
		hero.aim_direction = Vector2.LEFT
		await get_tree().physics_frame
	var turned := absf(rad_to_deg(Vector2.RIGHT.angle_to(hero.aim_direction)))
	var expected := GameRules.current().limited_turn_rate_degrees * 0.5 * 6.0 / Engine.physics_ticks_per_second
	_check("the aim turns no faster than the rate", near(turned, expected, 3.0), "%.0f° vs %.0f°" % [turned, expected])
	_check("casts use the turned aim", hero.limit_aim_point(hero.global_position + Vector2(-300, 0)).x > hero.global_position.x - 300.0 + 1.0)
	hero.status_component.clear()
	hero.aim_direction = Vector2.LEFT
	await frames(2)
	_check("unlimited again once it ends", hero.aim_direction.is_equal_approx(Vector2.LEFT))


func _test_silence_and_harmful() -> void:
	print("\n-- Silence that spares basic fire, harmful, self_status_on_fire")
	reset(Vector2(0, 22000))
	hero.status_component.apply(_status(&"emp", {"duration": 1.0, "silences": true, "silence_spares_primary": true}))
	_check("abilities are silenced", hero.get_ability(&"ability_1").get_block_reason() == "Silenced")
	_check("the primary still fires", hero.get_ability(&"primary").get_block_reason() == "")
	hero.status_component.clear()
	hero.status_component.apply(_status(&"classic", {"duration": 1.0, "silences": true}))
	_check("a classic silence still blocks everything", hero.get_ability(&"primary").get_block_reason() == "Silenced")
	hero.status_component.clear()
	var mark := _status(&"mark", {"duration": 3.0, "harmful": true})
	_check("a harmful mark is a debuff", mark.is_debuff())
	hero.status_component.apply(mark)
	hero.status_component.cleanse()
	_check("and is cleansed", not hero.status_component.has_status(&"mark"))
	var gun := hero.get_ranged_ability()
	gun.get_ranged_data().self_status_on_fire = _status(&"recoil", {"duration": 0.5})
	gun.reload_instantly()
	await hold_slot(&"primary", Vector2(400, 22000), 0.1)
	_check("self_status_on_fire lands on the shooter", hero.status_component.has_status(&"recoil"))
	gun.get_ranged_data().self_status_on_fire = null
	hero.status_component.clear()


func _test_ult_charge_rate() -> void:
	print("\n-- Ultimate charge rate")
	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	var fast_def: HeroDefinition = TEST_HERO.duplicate()
	fast_def.ult_charge_rate = 2.0
	var normal := _plain(&"a", Vector2(0, 24000))
	var fast := _plain(&"b", Vector2(0, 24400), fast_def)
	await frames(3)
	manager.start_playing()
	var a := UltimateCharge.find_on(normal)
	var b := UltimateCharge.find_on(fast)
	a.set_charge(0.0)
	b.set_charge(0.0)
	manager.add_ultimate_charge(normal, 10.0)
	manager.add_ultimate_charge(fast, 10.0)
	_check("ult_charge_rate 2: twice the charge from the same event", near(a.charge, 10.0) and near(b.charge, 20.0),
		"%.1f vs %.1f" % [a.charge, b.charge])
	normal.queue_free()
	fast.queue_free()
	manager.queue_free()
	await frames(2)


# The data-only test hero that plays every piece above (F1 > Play as >
# Ranged Test (gadgets)).
func _test_gadgets_hero() -> void:
	print("\n-- Ranged Test (gadgets)")
	var def: HeroDefinition = load("res://tools/heroes/ranged_test/ranged_test_gadgets_definition.tres")
	_check("validates", def.validate().is_empty(), "\n".join(def.validate()))
	_check("listed under F1 > Play as", HeroScaffold.find_dev_definitions().any(func(d): return d.hero_id == &"ranged_test_gadgets"))
	var saved := hero
	hero = _plain(&"a", Vector2(0, 26000), def)
	var target := dummy(Vector2(400, 26000))
	await frames(3)
	var cast := {}
	for slot in [&"primary", &"ability_1", &"ability_2", &"movement", &"cc", &"ultimate", &"item"]:
		reset(Vector2(0, 26000))
		await frames(2)
		cast[slot] = press(slot, target.global_position)
		await seconds(0.6)
		hero.release_slot(slot, target.global_position)
	var failed := cast.keys().filter(func(s): return not cast[s])
	_check("every slot casts", failed.is_empty(), "failed: %s" % [failed])
	hero.queue_free()
	hero = saved
	await clear()
