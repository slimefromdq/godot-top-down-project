extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for Mochi's kit: Madness (StackCounter), Mercy's
# missing-health scaling, Slip's i-frames, the tentacle (a Deployable that
# mirrors her shots with its own Madness counter, and the swap), and the
# telegraphed Cone Stare (stun + Magic Resist shred).
#
#   godot --headless res://tools/heroes/mochi_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const MOCHI := "res://heroes/mochi/mochi_hero.tscn"


func _run() -> void:
	hero = spawn_hero(MOCHI)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Mochi", "The Sweet Thing", "Carry")
	_check("Slip is the generic dash (data only)", hero.get_ability(&"movement").get_script() == ChargeAbility)
	await _test_madness()
	await _test_mercy()
	await _test_slip()
	await _test_tentacle()
	await _test_cone_stare()
	test_audio(audio)
	finish()


func _bolt_until(target: Node, n: int, label: StringName = &"whisper_bolts") -> void:
	var t := 0.0
	while hits(target, label).size() < n and t < 5.0:
		aim(target.global_position)
		hero.request_slot(&"primary", target.global_position)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _test_madness() -> void:
	print("\n-- Madness")
	reset(Vector2(0, 0))
	hero.stats_component.level = 10
	hero.stats_component.stats_changed.emit()
	var target := dummy(Vector2(350, 0))
	await frames(2)
	hits_log.clear()
	await _bolt_until(target, 4)
	_check("4 hits: no burst yet", hits(target, &"madness_burst").is_empty())
	_check("the stacks can be read", StackCounter.get_stacks(hero, &"madness", target) == 4)
	await _bolt_until(target, 5)
	await frames(1)
	var bursts := hits(target, &"madness_burst")
	_check("the 5th hit explodes", bursts.size() == 1)
	if bursts.size() == 1:
		_check("~120 magic damage at level 10", bursts[0].type == DamageInfo.Type.MAGIC and bursts[0].amount > 100.0
			and bursts[0].amount < 140.0, "%.0f" % bursts[0].amount)
	_check("then immune for 1.5 s", StackCounter.is_immune(hero, &"madness", target))
	await _bolt_until(target, 10)
	_check("no chain-spam: hits during immunity build nothing", hits(target, &"madness_burst").size() == 1
		and StackCounter.get_stacks(hero, &"madness", target) <= 3)
	await seconds(1.6)
	var other := dummy(Vector2(350, 300))
	await frames(2)
	hits_log.clear()
	await _bolt_until(other, 3)
	await seconds(3.2)
	_check("madness decays after 3 s without hits", StackCounter.get_stacks(hero, &"madness", other, 3.0) == 0)
	hero.stats_component.level = 1
	hero.stats_component.stats_changed.emit()
	await clear()


func _test_mercy() -> void:
	print("\n-- Mercy")
	reset(Vector2(0, 2000))
	var healthy := dummy(Vector2(350, 2000))
	var hurt := dummy(Vector2(350, 2300))
	await frames(2)
	hurt.health_component.current_health = hurt.health_component.max_health * 0.01
	hits_log.clear()
	press(&"ability_1", healthy.global_position)
	await seconds(0.5)
	hero.get_ability(&"ability_1").cooldown_remaining = 0.0
	press(&"ability_1", hurt.global_position)
	await seconds(0.5)
	var a := total(healthy, &"mercy")
	var b := hits(hurt, &"mercy")
	var raw_b: float = b[0].amount if not b.is_empty() else 0.0
	var raw_a: float = hits(healthy, &"mercy")[0].amount if not hits(healthy, &"mercy").is_empty() else 0.0
	_check("~60 base damage", raw_a > 55.0 and raw_a < 80.0, "%.0f" % raw_a)
	_check("up to +100% on a nearly dead target", near(raw_b, raw_a * 1.99, 1.0), "%.0f vs %.0f" % [raw_b, raw_a])
	_check("4 s cooldown", near(hero.get_ability(&"ability_1").get_cooldown(), 4.0))
	await clear()


func _test_slip() -> void:
	print("\n-- Slip")
	reset(Vector2(0, 4000))
	hero.move_direction = Vector2.DOWN
	press(&"movement", Vector2(300, 4000))
	await frames(3)
	hero.move_direction = Vector2.ZERO
	_check("i-frames at the start", hero.health_component.is_invulnerable())
	await seconds(0.5)
	var moved := hero.global_position.distance_to(Vector2(0, 4000))
	_check("350 px the way she moves (plus the slide-out)", moved > 320.0 and moved < 420.0 and hero.global_position.y > 4300.0, "%.0f" % moved)
	_check("i-frames end", not hero.health_component.is_invulnerable())
	await clear()


func _test_tentacle() -> void:
	print("\n-- Tentacle")
	reset(Vector2(0, 6000))
	var target := dummy(Vector2(450, 6200))
	await frames(2)
	press(&"cc", Vector2(300, 6300))
	await seconds(0.4)
	var tentacles := Deployable.find_owned(hero, &"tentacle")
	_check("places one tentacle at the cursor", tentacles.size() == 1
		and tentacles[0].global_position.distance_to(Vector2(300, 6300)) < 5.0)
	if tentacles.is_empty():
		return
	var tentacle: Deployable = tentacles[0]
	_check("the tentacle can be hit (it has health)", tentacle.hurtbox != null and tentacle.health_component.max_health > 0.0)
	hits_log.clear()
	await _bolt_until(target, 2)
	await seconds(0.4)
	var copies := hits(target, &"whisper_bolts_tentacle").size()
	_check("it fires her bolts at her cursor", copies >= 1, "%d" % copies)
	_check("with its own Madness counter", StackCounter.get_stacks(tentacle, &"madness", target) >= 1
		and StackCounter.get_stacks(hero, &"madness", target) >= 1)
	press(&"ability_1", target.global_position)
	await seconds(0.6)
	_check("and her Mercy", not hits(target, &"mercy_tentacle").is_empty())
	var spot := tentacle.global_position
	var cd := hero.get_ability(&"cc").cooldown_remaining
	_check("placing it started the 12 s cooldown", cd > 8.0 and cd <= 12.0, "%.1f" % cd)
	press(&"cc", Vector2.ZERO)
	await seconds(0.3)
	_check("E again: swaps onto its spot", hero.global_position.distance_to(spot) < 5.0)
	_check("and it's gone", Deployable.find_owned(hero, &"tentacle").is_empty())
	_check("the swap didn't restart the cooldown", hero.get_ability(&"cc").cooldown_remaining < cd)
	# It expires after 8 s.
	hero.get_ability(&"cc").cooldown_remaining = 0.0
	press(&"cc", hero.global_position + Vector2(200, 0))
	await seconds(8.5)
	_check("lasts 8 s", Deployable.find_owned(hero, &"tentacle").is_empty())
	await clear()


func _test_cone_stare() -> void:
	print("\n-- Cone Stare")
	reset(Vector2(0, 8000))
	var inside := dummy(Vector2(250, 8000), 50000.0, &"b", 50.0)
	var edge := dummy(Vector2(200, 8120))
	var behind := dummy(Vector2(-250, 8000))
	await frames(2)
	var mr_before := inside.stats_component.get_stat(StatBlock.MAGIC_RESIST)
	cues.clear()
	press(&"ultimate", Vector2(400, 8000))
	await seconds(0.3)
	_check("telegraphed on the ground (cone warning)", cues.has(&"cone_stare_windup"))
	_check("nothing yet during the 0.6 s wind-up", not inside.status_component.has_status(&"mochi_stare"))
	await seconds(0.45)
	_check("stuns everyone in the cone", inside.status_component.has_status(&"mochi_stare")
		and inside.status_component.is_stunned())
	_check("stun lasts 1.5 s", near(inside.status_component.get_time_left(&"mochi_stare"), 1.5, 0.2),
		"%.2f" % inside.status_component.get_time_left(&"mochi_stare"))
	var mr := inside.stats_component.get_stat(StatBlock.MAGIC_RESIST)
	_check("shreds 30% Magic Resist for 5 s", inside.status_component.has_status(&"mochi_shred")
		and near(mr, mr_before * 0.7, 0.5) and near(inside.status_component.get_time_left(&"mochi_shred"), 5.0, 0.2),
		"%.1f -> %.1f" % [mr_before, mr])
	_check("a 90° cone: not behind her", not behind.status_component.has_status(&"mochi_stare"))
	await clear()
	# A stun during the wind-up cancels it.
	reset(Vector2(0, 9000))
	var victim := dummy(Vector2(250, 9000))
	await frames(2)
	press(&"ultimate", Vector2(400, 9000))
	await seconds(0.2)
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.5
	stun.stuns = true
	hero.status_component.apply(stun)
	await seconds(0.8)
	_check("a stun during the wind-up interrupts it", not victim.status_component.has_status(&"mochi_stare"))
	await clear()
