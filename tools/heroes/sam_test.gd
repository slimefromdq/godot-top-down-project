extends Node2D

# Headless checks for Sam's kit (either-team Hug, Tractor Beam and Bracelet,
# the Close Encounter abduction on the airlock maze).
#
#   godot --headless res://tools/heroes/sam_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const SAM := "res://heroes/sam/sam_hero.tscn"
const OTHER := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var sam: Hero
var spawned: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	sam = load(SAM).instantiate()
	sam.team = &"a"
	add_child(sam)
	await _physics_frames(3)
	_test_assembled()
	await _test_hello()
	await _test_hug()
	await _test_tractor_beam()
	await _test_bracelet()
	await _test_close_encounter()

	LocalView.clear_viewer()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate"]:
		_check("slot %s filled" % slot, sam.get_ability(slot) != null, "")
	var definition := sam.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Sam"
		and definition.title == "The Visitor" and definition.get_role_name() == "Tempo", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"sam"), "")
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 620.0) and _near(stats.health.value_at(10), 1150.0)
		and _near(stats.weapon.value_at(10), 45.0) and _near(stats.magic.value_at(1), 40.0) and _near(stats.magic.value_at(10), 110.0)
		and _near(stats.armor.value_at(10), 38.0) and _near(stats.magic_resist.value_at(10), 40.0), "")
	var cooldowns := [[&"ability_1", 9.0], [&"movement", 14.0], [&"cc", 12.0], [&"ultimate", 80.0]]
	var ok := true
	for pair in cooldowns:
		ok = ok and _near(sam.get_ability(pair[0]).data.cooldown, pair[1])
	_check("cooldowns 9 / 14 / 12 / 80 s", ok, "")


# --- Hello! ------------------------------------------------------------------------------------

func _test_hello() -> void:
	print("\n-- Hello!")
	var hello := sam.get_ranged_ability()
	var data := hello.get_ranged_data()
	_check("3 shots/s of magic orbs that bounce off walls once", _near(data.shots_per_second, 3.0)
		and data.damage_type == DamageInfo.Type.MAGIC and data.projectile.wall_bounces == 1, "")
	_reset(Vector2(0, 0))
	var target := _dummy(Vector2(300, 0), &"b")
	await _physics_frames(2)
	var before := target.health_component.current_health
	sam.request_slot(&"primary", target.global_position)
	await _seconds(0.5)
	_check("...and they hit", target.health_component.current_health < before,
		"%.1f -> %.1f" % [before, target.health_component.current_health])
	_clear()
	await _physics_frames(2)


# --- Hug ---------------------------------------------------------------------------------------

func _test_hug() -> void:
	print("\n-- Hug")
	_reset(Vector2(0, 1000))
	var enemy := _other(Vector2(400, 1000), &"b")
	await _physics_frames(2)
	sam.request_slot(&"ability_1", enemy.global_position)
	await _seconds(0.5)
	_check("Hug roots the first enemy it reaches for 1 s", enemy.status_component.has_status(&"sam_hug")
		and enemy.status_component.is_rooted(), "")
	_check("...9 s cooldown", _near(sam.get_ability(&"ability_1").cooldown_remaining, 9.0, 0.6),
		"%.2f" % sam.get_ability(&"ability_1").cooldown_remaining)
	_clear()
	await _physics_frames(2)

	_reset(Vector2(0, 1000))
	var friend := _other(Vector2(400, 1000), &"a")
	await _physics_frames(2)
	sam.request_slot(&"ability_1", friend.global_position)
	await _seconds(0.5)
	var magic := sam.stats_component.get_stat(StatBlock.MAGIC)
	var expected := 120.0 + 0.5 * magic
	_check("...and shields an ally (120 + 50% Magic), no root", friend.status_component.has_status(&"sam_hug_shield")
		and _near(friend.status_component.get_shield_total(), expected, 0.5)
		and not friend.status_component.is_rooted(), "%.1f (expected %.1f)" % [friend.status_component.get_shield_total(), expected])

	_reset(Vector2(0, 1000))
	var far := _other(Vector2(0, 1700), &"b")
	await _physics_frames(2)
	sam.request_slot(&"ability_1", Vector2(0, 1700))
	await _seconds(0.8)
	_check("...650 px reach (an enemy at 700 px is out of reach)", not far.status_component.has_status(&"sam_hug"), "")
	_clear()
	await _physics_frames(2)


# --- Tractor Beam ------------------------------------------------------------------------------

func _hurt(target: Node, amount: float) -> void:
	for hurtbox in target.find_children("*", "HurtboxComponent", true, false):
		hurtbox.take_hit(DamageInfo.create(amount, null))
		return


func _beam(at: Vector2) -> void:
	var beam := sam.get_ability(&"movement")
	beam.cooldown_remaining = 0.0
	sam.request_slot(&"movement", at)
	sam.release_slot(&"movement", at)


func _test_tractor_beam() -> void:
	print("\n-- Tractor Beam")
	_reset(Vector2(0, 2000))
	var friend := _other(Vector2(150, 2000), &"a")
	await _physics_frames(2)
	var start := friend.global_position
	var hp := friend.health_component.current_health
	_aim(Vector2(1000, 2000))
	_beam(friend.global_position)
	var carried := false
	var untargetable := false
	for i in 40:
		await get_tree().physics_frame
		if friend.status_component.has_status(&"sam_beam_ally"):
			carried = true
			untargetable = untargetable or friend.status_component.is_untargetable()
			_hurt(friend, 100.0)
	await _seconds(0.3)
	var moved := friend.global_position.x - start.x
	_check("Tractor Beam lifts an ally (carried, untargetable)", carried and untargetable, "")
	_check("...carries them about 400 px along the aim", moved > 340.0 and moved < 460.0, "%.0f px" % moved)
	_check("...and they take no damage meanwhile", _near(friend.health_component.current_health, hp), "%.1f / %.1f" % [friend.health_component.current_health, hp])
	_check("...released on arrival", not friend.status_component.has_status(&"sam_beam_ally"), "")
	_check("...14 s cooldown", _near(sam.get_ability(&"movement").cooldown_remaining, 14.0, 1.0),
		"%.2f" % sam.get_ability(&"movement").cooldown_remaining)
	_clear()
	await _physics_frames(2)

	_reset(Vector2(0, 2600))
	var enemy := _other(Vector2(150, 2600), &"b")
	await _physics_frames(2)
	start = enemy.global_position
	_aim(Vector2(1000, 2600))
	_beam(enemy.global_position)
	var stunned := false
	for i in 40:
		await get_tree().physics_frame
		if enemy.status_component.has_status(&"sam_beam_enemy"):
			stunned = stunned or enemy.status_component.is_stunned()
	await _seconds(0.3)
	moved = enemy.global_position.x - start.x
	_check("an enemy is stunned while carried", stunned, "")
	_check("...and carried about 400 px", moved > 340.0 and moved < 460.0, "%.0f px" % moved)
	_check("...still targetable (it's a disable, not a rescue)", not enemy.status_component.has_status(&"sam_beam_ally"), "")
	_clear()
	await _physics_frames(2)

	_reset(Vector2(0, 3200))
	await _physics_frames(2)
	_aim(Vector2(1000, 3200))
	_beam(Vector2(1000, 3200))
	await _seconds(0.8)
	var dash := sam.global_position.x
	_check("with no one there, a short hover-dash (220 px)", dash > 180.0 and dash < 260.0, "%.0f px" % dash)


# --- Friendship Bracelet -----------------------------------------------------------------------

func _test_bracelet() -> void:
	print("\n-- Friendship Bracelet")
	_reset(Vector2(0, 4000))
	var first := _other(Vector2(300, 4000), &"b")
	var second := _other(Vector2(300, 4250), &"b")
	var bystander := _other(Vector2(300, 3500), &"b")
	await _physics_frames(2)
	var bracelet := sam.get_ability(&"cc")
	sam.request_slot(&"cc", first.global_position)
	await _seconds(0.4)
	var link: ActorLink = bracelet.link
	_check("the bracelet links the enemy it hits to their nearest teammate", is_instance_valid(link)
		and ((link.a == first and link.b == second) or (link.a == second and link.b == first)), "")
	_check("...both wear the bracelet", first.status_component.has_status(&"sam_linked")
		and second.status_component.has_status(&"sam_linked") and not bystander.status_component.has_status(&"sam_linked"), "")
	# Both run apart for 1.5 s.
	var widest := 0.0
	first.move_direction = Vector2.UP
	second.move_direction = Vector2.DOWN
	for i in 90:
		await get_tree().physics_frame
		widest = maxf(widest, first.global_position.distance_to(second.global_position))
	first.move_direction = Vector2.ZERO
	second.move_direction = Vector2.ZERO
	_check("two leashed enemies can't get more than 300 px apart", widest <= 301.0 and widest > 290.0, "%.1f px" % widest)
	await _seconds(3.0)
	_check("...the link ends after 4 s", not is_instance_valid(link) or link.has_ended(), "")
	first.move_direction = Vector2.UP
	await _seconds(0.5)
	first.move_direction = Vector2.ZERO
	_check("...and then they're free", first.global_position.distance_to(second.global_position) > 320.0, "")
	_clear()
	await _physics_frames(2)

	_reset(Vector2(0, 5000))
	var ally_a := _other(Vector2(300, 5000), &"a")
	var ally_b := _other(Vector2(300, 5200), &"a")
	await _physics_frames(2)
	bracelet.cooldown_remaining = 0.0
	ally_a.health_component.current_health = 100.0
	ally_b.health_component.current_health = 100.0
	sam.request_slot(&"cc", ally_a.global_position)
	await _seconds(0.4)
	link = bracelet.link
	_check("on allies it links two allies", is_instance_valid(link) and not link.has_ended()
		and link.get_other(ally_a) == ally_b and link.leash_distance == 0.0, "")
	ally_a.health_component.heal(100.0)
	_check("...and 50% of healing on one is shared with the other",
		_near(ally_b.health_component.current_health, 150.0, 0.5) and _near(ally_a.health_component.current_health, 200.0, 0.5),
		"%.1f / %.1f" % [ally_a.health_component.current_health, ally_b.health_component.current_health])
	_clear()
	await _physics_frames(2)


# --- Close Encounter ---------------------------------------------------------------------------

func _ult(target: Vector2) -> Ability:
	var ult := sam.get_ability(&"ultimate")
	ult.cooldown_remaining = 0.0
	sam.request_slot(&"ultimate", target)
	return ult


func _test_close_encounter() -> void:
	print("\n-- Close Encounter")
	_reset(Vector2(0, 6000))
	var victim := _other(Vector2(500, 6000), &"b")
	var ult_data: SamEncounterData = sam.get_ability(&"ultimate").data
	_check("the ultimate plays the airlock maze", ult_data.minigame is AirlockData and ult_data.validate().is_empty(), "")
	await _physics_frames(2)
	var hp := victim.health_component.current_health
	# Sam steers toward his cursor, 1500 px up.
	var cursor := Vector2(500, 4500)
	_aim(cursor)
	var ult := _ult(victim.global_position)
	var host := MinigameHost.find_or_create(victim)
	_check("the beam telegraph lands after 0.4 s", ult.state == ult.State.TELEGRAPH and not host.is_playing(), "")
	await _seconds(0.5)
	_check("a hit abducts them: the minigame plays", ult.is_abducting() and host.is_playing()
		and victim.status_component.has_status(&"sam_abducted"), "")
	_check("...80 s cooldown", _near(ult.cooldown_remaining, 80.0, 1.0), "%.1f" % ult.cooldown_remaining)
	var shooter := sam.get_ability(&"primary")
	var bracelet := sam.get_ability(&"cc")
	bracelet.cooldown_remaining = 0.0
	_check("Sam can still shoot but can't cast other abilities",
		shooter.get_block_reason() == "" and bracelet.get_block_reason() == "Channeling", bracelet.get_block_reason())

	# Hit the victim every way we can while they're up there.
	_hurt(victim, 200.0)
	victim.health_component.apply_damage(DamageInfo.create(200.0, sam))
	_check("the victim can't be damaged (untargetable and immune)", _near(victim.health_component.current_health, hp),
		"%.1f / %.1f" % [victim.health_component.current_health, hp])

	var last_ufo := victim.global_position
	var flew := 0.0
	var waited := 0.0
	while host.is_playing() and waited < 5.0:
		_aim(cursor)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		flew = victim.global_position.distance_to(Vector2(500, 6000))
		last_ufo = victim.global_position
	await get_tree().physics_frame
	var speed := flew / waited if waited > 0.0 else 0.0
	_check("the UFO flies toward Sam's cursor at about 350 px/s", last_ufo.y < 6000.0 - 300.0 and absf(last_ufo.x - 500.0) < 5.0
		and speed > 280.0 and speed < 360.0, "%.0f px in %.2f s (%.0f px/s)" % [flew, waited, speed])
	_check("an AI victim finds their way out in about 2 s", waited > 1.6 and waited < 4.0, "%.2f s" % waited)
	var landing := victim.global_position
	await _seconds(0.1)
	_check("the victim lands where the UFO was", landing.distance_to(last_ufo) < 12.0
		and victim.global_position.distance_to(landing) < 2.0, "%s vs %s" % [landing, last_ufo])
	_check("...no longer abducted, and dazed", not victim.status_component.has_status(&"sam_abducted")
		and victim.status_component.has_status(&"sam_daze") and victim.status_component.is_stunned(), "")
	_check("...Sam can cast again", bracelet.get_block_reason() == "" and not ult.is_abducting(), bracelet.get_block_reason())

	await _until(func(): return not victim.status_component.has_status(&"sam_daze"), 1.0)
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.stuns = true
	stun.duration = 1.0
	victim.status_component.apply(stun, sam)
	_check("Resolve halves a stun applied right after the landing daze",
		_near(victim.status_component.get_time_left(&"test_stun"), 0.5, 0.05),
		"%.2f s" % victim.status_component.get_time_left(&"test_stun"))
	_clear()
	await _physics_frames(2)

	# The beam can be dodged.
	_reset(Vector2(0, 7000))
	var dodger := _other(Vector2(500, 7000), &"b")
	await _physics_frames(2)
	ult = _ult(dodger.global_position)
	await _seconds(0.1)
	dodger.global_position += Vector2(0, 200)
	await _seconds(0.5)
	_check("stepping out of the beam during the telegraph dodges it", not ult.is_abducting()
		and not MinigameHost.find_or_create(dodger).is_playing() and not dodger.status_component.has_status(&"sam_abducted"), "")
	_check("the UFO can be seen by everyone while it flies (shadow + name tag)",
		load("res://heroes/sam/data/sam_abducted.tres").attached_vfx != null, "")
	_clear()
	await _physics_frames(2)

	# Sam dying ends it early; the victim still drops.
	_reset(Vector2(0, 8000))
	var second := _other(Vector2(500, 8000), &"b")
	await _physics_frames(2)
	ult = _ult(second.global_position)
	await _seconds(0.6)
	var host2 := MinigameHost.find_or_create(second)
	_check("(abducted again)", host2.is_playing(), "")
	sam.health_component.apply_damage(DamageInfo.create(99999.0, null, DamageInfo.Type.TRUE))
	await _physics_frames(3)
	_check("if Sam dies, the victim drops at once", not host2.is_playing()
		and not second.status_component.has_status(&"sam_abducted"), "")
	_clear()


func _reset(at: Vector2) -> void:
	sam.ability_controller.interrupt()
	sam.status_component.clear()
	sam.movement_component.stop_forced_move()
	sam.global_position = at
	sam.velocity = Vector2.ZERO
	sam.move_direction = Vector2.ZERO
	sam.health_component.reset()
	for ability in sam.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	sam.aim_point = at
	sam.aim_direction = (at - sam.global_position).normalized()


func _dummy(at: Vector2, team: StringName, hp: float = 2000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	d.team = team
	spawned.append(d)
	return d


func _other(at: Vector2, team: StringName) -> Hero:
	var h: Hero = load(OTHER).instantiate()
	h.team = team
	add_child(h)
	h.global_position = at
	spawned.append(h)
	return h


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
