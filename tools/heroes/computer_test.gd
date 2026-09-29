extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for the Computer's kit: fused grenades, the three
# Deployables (TurretDeployable, AuraDeployable, MoteDrone through
# DeployData / DeployAbility) and the EMP (a silence that spares basic fire).
#
#   godot --headless res://tools/heroes/computer_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const COMPUTER := "res://heroes/computer/computer_hero.tscn"
const SMALL_MOTE := "res://resources/match/small_mote.tres"


func _run() -> void:
	hero = spawn_hero(COMPUTER)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Computer", "The Sentient Beige Box", "Flex")
	_check("the whole kit is generic (no Computer scripts)",
		hero.get_ability(&"primary").get_script() == RangedAttackAbility
		and hero.get_ability(&"ability_1").get_script() == DeployAbility
		and hero.get_ability(&"cc").get_script() == DeployAbility
		and hero.get_ability(&"movement").get_script() == DeployAbility
		and hero.get_ability(&"ultimate").get_script() == MeleeAttackAbility)
	await _test_grenades()
	await _test_gun_turret()
	await _test_repair_turret()
	await _test_drone()
	await _test_emp()
	await _test_owner_death()
	test_audio(audio)
	finish()


func _test_grenades() -> void:
	print("\n-- Grenades")
	reset(Vector2(0, 0))
	hero.stats_component.level = 10
	hero.stats_component.stats_changed.emit()
	var target := dummy(Vector2(300, 0))
	var splash := dummy(Vector2(300, 70))
	var far := dummy(Vector2(300, 300))
	await frames(2)
	hits_log.clear()
	press(&"primary", target.global_position)
	await until(func(): return not hits(target, &"grenade").is_empty(), 1.5)
	var hit := hits(target, &"grenade")
	_check("explodes on contact", not hit.is_empty())
	if not hit.is_empty():
		_check("~50 damage at level 10", hit[0].amount > 40.0 and hit[0].amount < 65.0, "%.0f" % hit[0].amount)
	_check("80 px blast", not hits(splash, &"grenade").is_empty() and hits(far, &"grenade").is_empty())
	await clear()
	# Nothing to hit: it bursts after the fuse.
	reset(Vector2(0, 1000))
	var fused := dummy(Vector2(900, 1000) + Vector2(30, 60))
	await frames(2)
	hits_log.clear()
	await seconds(0.3)
	press(&"primary", Vector2(900, 1000))
	await seconds(1.2)
	_check("no blast before the 1.5 s fuse", hits(fused, &"grenade").is_empty())
	await seconds(0.5)
	_check("bursts when the fuse runs out", not hits(fused, &"grenade").is_empty())
	hero.stats_component.level = 1
	hero.stats_component.stats_changed.emit()
	await clear()


func _test_gun_turret() -> void:
	print("\n-- Gun Turret")
	reset(Vector2(0, 2000))
	var enemy := dummy(Vector2(500, 2000))
	var ally := dummy(Vector2(-300, 2000), 50000.0, &"a")
	await frames(2)
	press(&"ability_1", Vector2(100, 2000))
	await seconds(0.3)
	var turrets := Deployable.find_owned(hero, &"gun_turret")
	_check("deploys a turret", turrets.size() == 1 and turrets[0] is TurretDeployable)
	if turrets.is_empty():
		return
	var turret: Deployable = turrets[0]
	_check("300 health", near(turret.health_component.max_health, 300.0))
	hits_log.clear()
	await seconds(1.0)
	var shots := hits(enemy, &"gun_turret")
	_check("shoots the enemy in range ~4 times a second", shots.size() >= 3 and shots.size() <= 5, "%d" % shots.size())
	if not shots.is_empty():
		_check("~12 damage a shot at most", shots[0].amount > 6.0 and shots[0].amount < 16.0, "%.1f" % shots[0].amount)
	_check("never its own team", hits_log.filter(func(i): return i.target == ally).is_empty())
	hero.get_ability(&"ability_1").cooldown_remaining = 0.0
	press(&"ability_1", Vector2(100, 2100))
	await seconds(0.3)
	_check("one at a time: a new one replaces it", Deployable.find_owned(hero, &"gun_turret").size() == 1
		and not is_instance_valid(turret))
	turret = Deployable.find_owned(hero, &"gun_turret")[0]
	var info := DamageInfo.create(400.0, enemy, DamageInfo.Type.TRUE)
	turret.hurtbox.take_hit(info)
	await frames(2)
	_check("enemies can destroy it", not is_instance_valid(turret))
	hero.get_ability(&"ability_1").cooldown_remaining = 0.0
	press(&"ability_1", Vector2(100, 2000))
	await seconds(0.3)
	turret = Deployable.find_owned(hero, &"gun_turret")[0]
	await seconds(12.2)
	_check("lasts 12 s", not is_instance_valid(turret))
	await clear()


func _test_repair_turret() -> void:
	print("\n-- Repair Turret")
	reset(Vector2(0, 4000))
	var friend := spawn_hero(COMPUTER, &"a", Vector2(150, 4000))
	var foe := spawn_hero(COMPUTER, &"b", Vector2(-150, 4000))
	spawned.append_array([friend, foe])
	await frames(3)
	friend.health_component.current_health = 100.0
	foe.health_component.current_health = 100.0
	press(&"cc", Vector2(0, 4050))
	await seconds(0.3)
	var before := friend.health_component.current_health
	await seconds(2.0)
	var per_second := (friend.health_component.current_health - before) / 2.0
	_check("heals allies in range ~20/s", per_second > 12.0 and per_second < 30.0, "%.1f/s" % per_second)
	_check("not enemies", near(foe.health_component.current_health, 100.0))
	await seconds(8.2)
	_check("lasts 10 s", Deployable.find_owned(hero, &"repair_turret").is_empty())
	await clear()


func _test_drone() -> void:
	print("\n-- Mote Drone")
	reset(Vector2(0, 6000))
	var carrier := MoteCarrier.find_on(hero)
	carrier.clear()
	var data: MoteData = load(SMALL_MOTE)
	# Out of the Computer's own pickup reach, within the drone's sight.
	for i in 2:
		spawned.append(Mote.spawn(self, data, Vector2(350, 6000 + i * 60)))
	press(&"movement", hero.global_position)
	await seconds(0.3)
	var drones := Deployable.find_owned(hero, &"mote_drone")
	_check("launches a drone", drones.size() == 1 and drones[0] is MoteDrone)
	if drones.is_empty():
		return
	var drone: MoteDrone = drones[0]
	press(&"movement", hero.global_position)
	await seconds(0.3)
	_check("one at a time", Deployable.find_owned(hero, &"mote_drone").size() == 1)
	await until(func(): return carrier.get_mote_count() == 2, 8.0)
	_check("it fetches loose Motes and brings them back", carrier.get_mote_count() == 2, "%d" % carrier.get_mote_count())
	# Shot while carrying: drops them and flees.
	spawned.append(Mote.spawn(self, data, drone.global_position + Vector2(0, 150)))
	await until(func(): return drone.get_carried_count() == 1, 6.0)
	_check("picks up another", drone.get_carried_count() == 1)
	var shooter := dummy(drone.global_position + Vector2(100, 0))
	drone.hurtbox.take_hit(DamageInfo.create(10.0, shooter))
	await frames(2)
	_check("hit: drops what it carries", drone.get_carried_count() == 0
		and get_tree().get_nodes_in_group(Mote.GROUP).size() >= 1)
	_check("and flees", drone.state == MoteDrone.State.FLEE)
	var ability := hero.get_ability(&"movement")
	_check("no cooldown while it's alive", ability.cooldown_remaining == 0.0)
	drone.hurtbox.take_hit(DamageInfo.create(500.0, shooter, DamageInfo.Type.TRUE))
	await frames(2)
	_check("shot down: 20 s cooldown starts", near(ability.cooldown_remaining, 20.0, 0.2), "%.1f" % ability.cooldown_remaining)
	carrier.clear()
	await clear()


func _test_emp() -> void:
	print("\n-- EMP")
	reset(Vector2(0, 8000))
	var near_foe := spawn_hero(COMPUTER, &"b", Vector2(250, 8000))
	var far_foe := spawn_hero(COMPUTER, &"b", Vector2(450, 8000))
	spawned.append_array([near_foe, far_foe])
	await frames(3)
	press(&"ultimate", Vector2(300, 8000))
	await seconds(0.4)
	_check("silences enemies within 300 px", near_foe.get_ability(&"ability_1").get_block_reason() == "Silenced")
	_check("they can still shoot", near_foe.get_ability(&"primary").get_block_reason() == "")
	_check("3 s", near(near_foe.status_component.get_time_left(&"computer_emp"), 2.8, 0.25))
	_check("not beyond 300 px", far_foe.get_ability(&"ability_1").get_block_reason() == "")
	await clear()


func _test_owner_death() -> void:
	print("\n-- Cleanup")
	var owner_hero := spawn_hero(COMPUTER, &"a", Vector2(0, 10000))
	await frames(3)
	var saved := hero
	hero = owner_hero
	press(&"ability_1", Vector2(100, 10000))
	await seconds(0.3)
	hero.get_ability(&"cc").cooldown_remaining = 0.0
	press(&"cc", Vector2(-100, 10000))
	await seconds(0.3)
	_check("two deployables out", Deployable.find_owned(owner_hero).size() == 2)
	var mine := Deployable.find_owned(owner_hero)
	owner_hero.health_component.kill()
	await frames(2)
	_check("all removed when their owner dies", mine.all(func(d): return not is_instance_valid(d)))
	hero = saved
	await clear()
