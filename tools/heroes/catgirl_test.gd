extends "res://tools/heroes/hero_test_base.gd"

# Headless checks for Catgirl's kit: 4-charge dash, Mote-stealing Swipe
# (MoteCarrier.steal_from), marbles (a TRACTION zone), the sticky bomb, and
# her fast-charging ultimate (HeroDefinition.ult_charge_rate).
#
#   godot --headless res://tools/heroes/catgirl_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const CATGIRL := "res://heroes/catgirl/catgirl_hero.tscn"
const SMALL_MOTE := "res://resources/match/small_mote.tres"


func _run() -> void:
	hero = spawn_hero(CATGIRL)
	var audio = AUDIO_COVERAGE.new(hero)
	await frames(3)
	check_assembly("Catgirl", "The Broke Thief", "Tempo")
	# The Biker's bike is faster flat out, but she can't stop or turn: on foot
	# nobody outruns Catgirl.
	var fastest := true
	for d in HeroScaffold.find_definitions():
		if d.hero_id not in [&"catgirl", &"biker"] and d.move_speed >= hero.definition.move_speed:
			fastest = false
	_check("the fastest hero on foot", fastest)
	await _test_smg()
	await _test_scamper()
	await _test_swipe()
	await _test_marbles()
	await _test_sticky_bomb()
	_test_ult_rate()
	test_audio(audio)
	finish()


func _test_smg() -> void:
	print("\n-- SMG")
	reset(Vector2(0, 0))
	var close := dummy(Vector2(200, 0))
	await frames(2)
	hits_log.clear()
	await hold_slot(&"primary", close.global_position, 1.0)
	var n := hits(close, &"smg").size()
	_check("~12 shots per second, wide spread", n >= 6 and n <= 12, "%d hits in 1 s at 200 px" % n)
	await clear()


func _test_scamper() -> void:
	print("\n-- Scamper")
	reset(Vector2(0, 2000))
	var dash := hero.get_ability(&"movement")
	_check("4 charges", dash.get_max_charges() == 4 and dash.get_charges() == 4)
	hero.move_direction = Vector2.RIGHT
	for i in 4:
		press(&"movement", Vector2(300, 2000))
		await seconds(0.2)
	hero.move_direction = Vector2.ZERO
	_check("all four used back to back", dash.get_charges() == 0)
	_check("constant hypermobility (~800 px in under a second)", hero.global_position.x > 700.0, "%.0f" % hero.global_position.x)
	await seconds(3.1)
	_check("one comes back every 3 s", dash.get_charges() == 1)
	await clear()


func _test_swipe() -> void:
	print("\n-- Swipe")
	reset(Vector2(0, 4000))
	var victim := spawn_hero(CATGIRL, &"b", Vector2(100, 4000))
	spawned.append(victim)
	await frames(3)
	var data: MoteData = load(SMALL_MOTE)
	var theirs := MoteCarrier.find_on(victim)
	var mine := MoteCarrier.find_on(hero)
	mine.clear()
	for i in 7:
		theirs.add_mote(data, 1)
	press(&"ability_1", victim.global_position)
	await seconds(0.4)
	_check("steals 5 Motes from the target", mine.get_mote_count() == 5 and theirs.get_mote_count() == 2,
		"%d / %d" % [mine.get_mote_count(), theirs.get_mote_count()])
	# The carry cap still applies.
	var cap := mine.get_max()
	for i in cap - mine.get_mote_count() - 1:
		mine.add_mote(data, 1)
	for i in 5:
		theirs.add_mote(data, 1)
	var before := theirs.get_mote_count()
	hero.get_ability(&"ability_1").cooldown_remaining = 0.0
	press(&"ability_1", victim.global_position)
	await seconds(0.4)
	_check("only as many as she has room for (the hit may shake one more loose)", mine.get_mote_count() == cap and theirs.get_mote_count() <= before - 1 and theirs.get_mote_count() >= before - 2,
		"%d/%d, victim %d" % [mine.get_mote_count(), cap, theirs.get_mote_count()])
	_check("5 s cooldown", near(hero.get_ability(&"ability_1").get_cooldown(), 5.0))
	mine.clear()
	await clear()


func _test_marbles() -> void:
	print("\n-- Marbles")
	reset(Vector2(0, 6000))
	var target := dummy(Vector2(400, 6000))
	await frames(2)
	press(&"cc", target.global_position)
	await until(func(): return find_zone(&"marbles") != null, 1.5)
	await seconds(0.3)
	var s := target.status_component
	_check("40% slow", near(s.get_multiplier(&"move_speed"), 0.6))
	_check("60% less traction: they slide", near(target.movement_component.get_traction(), 0.4))
	# It stacks with a hero's own low traction (the Biker's 0.5).
	var biker := spawn_hero("res://heroes/biker/biker_hero.tscn", &"b", target.global_position + Vector2(0, 30))
	spawned.append(biker)
	await seconds(0.3)
	_check("stacks with the Biker's own low traction (0.5 x 0.4)", near(biker.movement_component.get_traction(), 0.2),
		"%.2f" % biker.movement_component.get_traction())
	await seconds(4.0)
	_check("4 s", find_zone(&"marbles") == null)
	await clear()


func _test_sticky_bomb() -> void:
	print("\n-- Sticky Bomb")
	reset(Vector2(0, 8000))
	var target := dummy(Vector2(400, 8000))
	var bystander := dummy(Vector2(450, 8000))
	await frames(2)
	hits_log.clear()
	press(&"ultimate", target.global_position)
	await until(func(): return target.status_component.has_status(&"catgirl_sticky_bomb"), 1.0)
	var bomb: StatusEffect = hero.get_ability(&"ultimate").data.on_hit_status
	_check("sticks to the target, visible to all", target.status_component.has_status(&"catgirl_sticky_bomb")
		and bomb.attached_vfx != null and bomb.vfx_visible_to == StatusEffect.VfxVisibleTo.EVERYONE)
	await seconds(1.5)
	_check("nothing for 2 s", hits(target, &"sticky_bomb_boom").is_empty())
	await seconds(0.7)
	var boom := total(target, &"sticky_bomb_boom")
	_check("then high single-target damage (~350 at level 10)", boom > 200.0, "%.0f at level 1" % boom)
	_check("only the target", hits(bystander, &"sticky_bomb_boom").is_empty())
	# Cleansed: defused.
	await clear()
	reset(Vector2(0, 9000))
	var clean := dummy(Vector2(400, 9000))
	await frames(2)
	hits_log.clear()
	hero.get_ability(&"ultimate").cooldown_remaining = 0.0
	press(&"ultimate", clean.global_position)
	await until(func(): return clean.status_component.has_status(&"catgirl_sticky_bomb"), 1.0)
	clean.status_component.cleanse()
	await seconds(2.3)
	_check("a cleanse defuses it", hits(clean, &"sticky_bomb_boom").is_empty())
	await clear()


func _test_ult_rate() -> void:
	print("\n-- Ultimate charge")
	_check("charges twice as fast", near(hero.definition.ult_charge_rate, 2.0))
	# MatchManager.add_ultimate_charge applies it: see batch2_infra_test.
