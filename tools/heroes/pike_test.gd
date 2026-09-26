extends Node2D

# Headless checks for Pike's kit and the shared pieces it added
# (ContainmentRing on the BARRIERS layer, Actor.teleport_to).
#
#   godot --headless res://tools/heroes/pike_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const PIKE := "res://heroes/pike/pike_hero.tscn"
const OTHER := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"

var failures := 0
var pike: Hero
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	pike = load(PIKE).instantiate()
	pike.team = &"a"
	add_child(pike)
	await _physics_frames(3)
	_test_assembled()
	await _test_beloved()
	await _test_there_you_are()
	await _test_obsession()
	await _test_knives_and_dont_go()
	await _test_only_us()

	LocalView.clear_viewer()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, pike.get_ability(slot) != null, "")
	var definition := pike.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Pike"
		and definition.title == "The Beloved's Shadow" and definition.get_role_name() == "Tempo", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"pike"), "")
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 560.0) and _near(stats.health.value_at(10), 1050.0)
		and _near(stats.weapon.value_at(10), 95.0) and _near(stats.magic.value_at(10), 18.0)
		and _near(stats.armor.value_at(10), 34.0) and _near(stats.magic_resist.value_at(10), 28.0), "")
	var knives := pike.get_ranged_ability()
	_check("knives: 4/s, 5 rounds, regen 1 per 0.5 s", _near(knives.get_ranged_data().shots_per_second, 4.0)
		and knives.get_max_ammo() == 5 and knives.is_regen() and _near(knives.get_ranged_data().regen_interval, 0.5), "")


# --- Beloved ----------------------------------------------------------------------------------

func _mark(target: Node2D) -> void:
	var beloved := pike.get_ability(&"ability_1")
	beloved.cooldown_remaining = 0.0
	_aim(target.global_position)
	pike.request_slot(&"ability_1", target.global_position)
	await _seconds(0.5)


func _beloved() -> Node2D:
	return pike.get_ability(&"ability_1").get_beloved()


func _test_beloved() -> void:
	print("\n-- Beloved")
	_reset(Vector2(0, 0))
	var a := _dummy(Vector2(400, 0), &"b")
	var b := _dummy(Vector2(0, 400), &"b")
	await _physics_frames(2)
	await _mark(a)
	_check("the heart makes the enemy hit her Beloved", _beloved() == a and a.status_component.has_status(&"pike_beloved"), "")
	await _mark(b)
	_check("marking a second enemy clears Beloved from the first", _beloved() == b
		and not a.status_component.has_status(&"pike_beloved") and b.status_component.has_status(&"pike_beloved"), "")

	var heart = b.visuals.get_status_vfx(&"pike_beloved")
	_check("the Beloved wears the heart", heart != null and heart.has_method(&"get_size_for_viewer"), "")
	if heart != null:
		var teammate := _other(Vector2(0, 800), &"b")
		var stranger := _other(Vector2(0, 1200), &"c")
		await _physics_frames(2)
		LocalView.set_viewer(b)
		var for_beloved: float = heart.get_size_for_viewer()
		LocalView.set_viewer(pike)
		var for_pike: float = heart.get_size_for_viewer()
		LocalView.set_viewer(teammate)
		var for_ally: float = heart.get_size_for_viewer()
		LocalView.set_viewer(stranger)
		var for_other: float = heart.get_size_for_viewer()
		LocalView.clear_viewer()
		_check("big heart for the Beloved and Pike, small for the Beloved's allies, none for others",
			for_beloved == 1.0 and for_pike == 1.0 and for_ally == 0.5 and for_other == 0.0,
			"%.1f / %.1f / %.1f / %.1f" % [for_beloved, for_pike, for_ally, for_other])
	_clear()
	await _physics_frames(2)


# --- There You Are ------------------------------------------------------------------------

func _test_there_you_are() -> void:
	print("\n-- There You Are")
	_reset(Vector2(0, 3000))
	var target := _dummy(Vector2(600, 3000), &"b")
	await _physics_frames(2)
	await _mark(target)
	# Then a wall between them.
	var wall := _wall(Vector2(300, 3000))
	pike.global_position = Vector2(0, 3000)
	await _physics_frames(2)
	_check("(a wall blocks the line between them)", not CombatQueries.has_line_of_sight(pike, target), "")
	var there := pike.get_ability(&"movement")
	there.cooldown_remaining = 0.0
	pike.request_slot(&"movement", Vector2(600, 3000))
	await _seconds(0.2)
	_check("There You Are works behind a wall: she's right beside her Beloved",
		pike.global_position.distance_to(target.global_position) < 130.0 and pike.global_position.x > 330.0,
		str(pike.global_position))
	_check("...10 s cooldown", _near(there.cooldown_remaining, 10.0, 0.4), "%.1f" % there.cooldown_remaining)

	_reset(Vector2(-400, 3000))
	await _physics_frames(2)
	_check("(her Beloved is 1000 px away)", _beloved() == target, "")
	pike.request_slot(&"movement", Vector2(600, 3000))
	await _seconds(0.2)
	_check("it fails beyond 900 px (no move, no cooldown)", pike.global_position.distance_to(Vector2(-400, 3000)) < 1.0
		and there.cooldown_remaining == 0.0, str(pike.global_position))
	wall.queue_free()
	_clear()
	await _physics_frames(2)

	_reset(Vector2(0, 3600))
	await _physics_frames(2)
	_check("(no Beloved now)", _beloved() == null, "")
	_aim(Vector2(1000, 3600))
	pike.request_slot(&"movement", Vector2(1000, 3600))
	await _seconds(0.4)
	_check("with no Beloved it's a short dash (300 px)", absf(pike.global_position.x - 300.0) < 25.0, "%.0f" % pike.global_position.x)


# --- Obsession ---------------------------------------------------------------------------------

func _test_obsession() -> void:
	print("\n-- Obsession")
	_reset(Vector2(0, 6000))
	var target := _dummy(Vector2(500, 6000), &"b")
	await _physics_frames(2)
	await _mark(target)
	var obsession := pike.get_ability(&"passive")
	await _physics_frames(2)
	_check("seen: no bonus", not obsession.is_unseen() and not pike.status_component.has_status(&"pike_unseen"), "")
	var wall := _wall(Vector2(250, 6000))
	await _physics_frames(3)
	_check("Obsession's bonus is on while a wall blocks the Beloved's sight", obsession.is_unseen()
		and _near(pike.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.2)
		and pike.visuals.modulate.a < 0.5, "")
	wall.queue_free()
	await _physics_frames(3)
	_check("...and off as soon as they see her", not obsession.is_unseen()
		and not pike.status_component.has_status(&"pike_unseen"), "")
	_check("being seen again readies an ambush knife", obsession.is_ambush_ready(), "")

	hits_log.clear()
	_aim(target.global_position)
	pike.request_slot(&"primary", target.global_position)
	await _seconds(0.5)
	var hits := hits_log.filter(func(i): return i.target == target and i.label == &"juggled_knives")
	var single := _knife_damage(target)
	_check("the ambush knife deals double damage", not hits.is_empty() and _near(hits[0].amount, single * 2.0, 0.1),
		"%.1f vs %.1f" % [hits[0].amount if not hits.is_empty() else 0.0, single * 2.0])
	_check("...and roots for 0.75 s", target.status_component.has_status(&"pike_ambush_root"), "")
	_check("...only the first knife", hits.size() < 2 or _near(hits[1].amount, single, 0.1), "")

	var wall2 := _wall(Vector2(250, 6000))
	await _physics_frames(3)
	wall2.queue_free()
	await _physics_frames(3)
	_check("at most one ambush per 6 s", not obsession.is_ambush_ready(), "")
	_clear()
	await _physics_frames(2)


# 0.4 x Weapon + 0.5% of the target's max HP.
func _knife_damage(target: TrainingDummy) -> float:
	return 0.4 * pike.stats_component.get_stat(&"weapon") + 0.005 * target.health_component.max_health


# --- Knives and Don't Go -----------------------------------------------------------------------

func _test_knives_and_dont_go() -> void:
	print("\n-- Knives and Don't Go")
	_reset(Vector2(0, 9000))
	var target := _dummy(Vector2(400, 9000), &"b", 4000.0)
	await _physics_frames(2)
	hits_log.clear()
	_aim(target.global_position)
	for i in 3:
		pike.request_slot(&"primary", target.global_position)
		await get_tree().physics_frame
	await _seconds(0.5)
	var hits := hits_log.filter(func(i): return i.target == target and i.label == &"juggled_knives")
	_check("each knife: 0.4 x Weapon + 0.5% of max HP", not hits.is_empty() and _near(hits[0].amount, _knife_damage(target), 0.1),
		"%.1f vs %.1f" % [hits[0].amount if not hits.is_empty() else 0.0, _knife_damage(target)])

	var plain := _dummy(Vector2(400, 9400), &"b")
	var beloved := _dummy(Vector2(0, 9500), &"b")
	await _physics_frames(2)
	_aim(plain.global_position)
	pike.request_slot(&"cc", plain.global_position)
	var plain_root := await _root_time(plain)
	_check("Don't Go roots the first enemy hit for 1 s", _near(plain_root, 1.0, 0.05), "%.2f" % plain_root)
	await _mark(beloved)
	pike.get_ability(&"cc").cooldown_remaining = 0.0
	_aim(beloved.global_position)
	pike.request_slot(&"cc", beloved.global_position)
	var beloved_root := await _root_time(beloved)
	_check("...1.5 s if it's her Beloved", _near(beloved_root, 1.5, 0.05), "%.2f" % beloved_root)
	_clear()
	await _physics_frames(2)


func _root_time(target: TrainingDummy) -> float:
	var waited := 0.0
	while waited < 1.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if target.status_component.has_status(&"pike_dont_go"):
			await get_tree().physics_frame    # a Beloved's longer root lands right after
			return target.status_component.get_time_left(&"pike_dont_go") + get_physics_process_delta_time()
	return 0.0


# --- Only Us ------------------------------------------------------------------------------------

func _test_only_us() -> void:
	print("\n-- Only Us")
	_reset(Vector2(0, 12000))
	var target := _dummy(Vector2(400, 12000), &"b", 3000.0)
	target.can_die = true
	var stranger := _other(Vector2(200, 12150), &"c")
	var outsider := _other(Vector2(900, 12000), &"c")
	var shooter := _dummy(Vector2(-700, 12000), &"c")
	await _physics_frames(2)
	await _mark(target)
	var only_us := pike.get_ability(&"ultimate")
	pike.request_slot(&"ultimate", Vector2(400, 12000))
	await _physics_frames(3)
	var ring: ContainmentRing = only_us.ring
	_check("Only Us closes a 450 px ring around Pike and her Beloved", is_instance_valid(ring)
		and ring.radius == 450.0 and ring.global_position.distance_to(Vector2(200, 12000)) < 1.0
		and ring.is_inside(pike.global_position) and ring.is_inside(target.global_position), "")
	if not is_instance_valid(ring):
		return
	_check("...for 4 s", _near(ring.duration, 4.0), "")
	_check("anyone else inside is pushed out", not ring.is_inside(stranger.global_position), str(stranger.global_position))

	outsider.move_direction = Vector2.LEFT
	await _seconds(0.8)
	outsider.move_direction = Vector2.ZERO
	_check("walking in: stopped at the edge", not ring.is_inside(outsider.global_position), str(outsider.global_position))
	outsider.movement_component.displace(Vector2.LEFT, 600.0, 0.2)
	await _seconds(0.3)
	_check("a dash in: stopped", not ring.is_inside(outsider.global_position), str(outsider.global_position))
	outsider.launch(Vector2(200, 12000), 0.4)
	await _seconds(0.5)
	_check("a launch in: stopped", not ring.is_inside(outsider.global_position), str(outsider.global_position))
	var before := outsider.global_position
	_check("a teleport in: refused", not outsider.teleport_to(Vector2(200, 12000)) and outsider.global_position == before, "")
	_check("a teleport out: refused too", not pike.teleport_to(Vector2(200, 13000)), "")
	var hp := target.health_component.current_health
	var bolt := ProjectileData.new()
	bolt.speed = 2000.0
	bolt.lifetime = 0.8
	# Straight up at the Beloved from below: nobody else on the line.
	Projectile.fire(shooter, bolt, Vector2(400, 12800), Vector2.UP, DamageInfo.create(50.0, shooter))
	await _seconds(0.6)
	_check("a projectile in: stopped", target.health_component.current_health == hp, "")
	pike.movement_component.displace(Vector2.DOWN, 800.0, 0.3)
	await _seconds(0.4)
	_check("a dash out: stopped", ring.is_inside(pike.global_position), str(pike.global_position))
	_check("(sight isn't blocked: everyone sees in)", CombatQueries.has_line_of_sight(outsider, target), "")

	target.health_component.apply_damage(DamageInfo.create(999999.0, shooter))
	await _physics_frames(3)
	_check("the ring ends early if the Beloved dies", not is_instance_valid(ring) or ring.has_ended(), "")
	_check("...and the edge is open again", outsider.teleport_to(Vector2(200, 12000)), "")

	_reset(Vector2(0, 14000))
	var far := _dummy(Vector2(800, 14000), &"b")
	await _physics_frames(2)
	await _mark(far)
	only_us.cooldown_remaining = 0.0
	pike.request_slot(&"ultimate", Vector2(800, 14000))
	await _physics_frames(3)
	_check("it needs the Beloved within 600 px", only_us.cooldown_remaining == 0.0, "")
	_clear()


# --- Helpers ------------------------------------------------------------------------------------

func _reset(at: Vector2) -> void:
	pike.ability_controller.interrupt()
	pike.status_component.clear()
	pike.movement_component.stop_forced_move()
	pike.global_position = at
	pike.velocity = Vector2.ZERO
	pike.move_direction = Vector2.ZERO
	pike.health_component.reset()
	for ability in pike.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	pike.aim_point = at
	pike.aim_direction = (at - pike.global_position).normalized()


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


func _wall(at: Vector2) -> Node2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = MapLayers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 600)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = at
	add_child(wall)
	spawned.append(wall)
	return wall


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
