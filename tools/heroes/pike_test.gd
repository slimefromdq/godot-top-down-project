extends Node2D

# Headless checks for Pike's kit and the shared pieces it added
# (ContainmentRing on the BARRIERS layer, Actor.teleport_to).
#
#   godot --headless res://tools/heroes/pike_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const PIKE := "res://heroes/pike/pike_hero.tscn"
const AUDIO_COVERAGE := preload("res://tools/heroes/audio_coverage.gd")
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
	var audio = AUDIO_COVERAGE.new(pike)
	await _physics_frames(3)
	_test_assembled()
	await _test_beloved()
	await _test_there_you_are()
	await _test_obsession()
	await _test_knives_and_bleed()
	await _test_crazed_devotion()
	await _test_only_us()
	_test_audio(audio)

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
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 480.0) and _near(stats.health.value_at(10), 894.0, 0.1)
		and _near(stats.weapon.value_at(10), 90.4) and _near(stats.magic.value_at(10), 18.0)
		and _near(stats.armor.value_at(10), 32.4) and _near(stats.magic_resist.value_at(10), 28.0), "")
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
	var bystander := _dummy(Vector2(-400, 6000), &"b")
	await _physics_frames(2)
	await _mark(target)
	var obsession := pike.get_ability(&"passive")
	var delay: float = obsession.data.get_value(&"restealth_delay", pike.stats_component)
	await _seconds(delay)    # earlier tests may have just revealed her
	_check("seen: no bonus", not obsession.is_unseen() and not pike.status_component.has_status(&"pike_unseen"), "")
	_check("seen: enemies can see her", CombatQueries.has_line_of_sight(bystander, pike)
		and not CombatQueries.is_invisible(pike), "")
	var wall := _wall(Vector2(250, 6000))
	await _physics_frames(3)
	_check("Obsession's bonus is on while a wall blocks the Beloved's sight", obsession.is_unseen()
		and _near(pike.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.2)
		and pike.visuals.modulate.a < 0.5, "")
	_check("hidden, she's invisible to every enemy, even one with a clear view",
		CombatQueries.is_invisible(pike) and not CombatQueries.has_line_of_sight(bystander, pike), "")
	LocalView.set_viewer(bystander)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("...and isn't drawn on an enemy's screen", not pike.visible, "")
	LocalView.set_viewer(pike)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("...but her own team still sees her", pike.visible, "")
	wall.queue_free()
	await _physics_frames(3)
	_check("she stays hidden when her Beloved could see her again", obsession.is_unseen()
		and pike.status_component.has_status(&"pike_unseen")
		and not CombatQueries.has_line_of_sight(target, pike), "")

	# There You Are keeps her hidden.
	pike.get_ability(&"movement").cooldown_remaining = 0.0
	pike.request_slot(&"movement", target.global_position)
	await _seconds(0.4)
	_check("There You Are doesn't reveal her", obsession.is_unseen(), "")

	hits_log.clear()
	_aim(target.global_position)
	pike.request_slot(&"primary", target.global_position)
	await _seconds(0.5)
	_check("a knife reveals her", not obsession.is_unseen() and not pike.status_component.has_status(&"pike_unseen")
		and CombatQueries.has_line_of_sight(target, pike), "")
	var hits := hits_log.filter(func(i): return i.target == target and i.label == &"juggled_knives")
	var single := _knife_damage(target)
	_check("the knife out of hiding is an ambush: double damage", not hits.is_empty() and _near(hits[0].amount, single * 2.0, 0.1),
		"%.1f vs %.1f" % [hits[0].amount if not hits.is_empty() else 0.0, single * 2.0])
	_check("...and roots for 0.75 s", target.status_component.has_status(&"pike_ambush_root"), "")
	_check("...only the first knife", hits.size() < 2 or _near(hits[1].amount, single, 0.1), "")
	pike.ability_controller.interrupt()

	# Breaking sight right away: she can't vanish again for restealth_delay.
	pike.global_position = target.global_position - Vector2(500, 0)
	var wall2 := _wall(pike.global_position.lerp(target.global_position, 0.5))
	await _physics_frames(3)
	_check("no vanishing again within restealth_delay", not obsession.is_unseen(), "")
	await _seconds(delay)
	_check("...then she vanishes again", obsession.is_unseen(), "")
	_check("the ambush is on cooldown (at most one per 6 s)", not obsession.is_ambush_ready(), "")
	pike.get_ability(&"cc").cooldown_remaining = 0.0
	pike.request_slot(&"cc", target.global_position)
	await _physics_frames(2)
	_check("casting another ability reveals her too", not obsession.is_unseen(), "")
	_check("...with no ambush while it's on cooldown", not obsession.is_ambush_ready(), "")
	wall2.queue_free()
	pike.ability_controller.interrupt()
	pike.movement_component.stop_forced_move()
	pike.global_position = target.global_position - Vector2(500, 0)    # the dash carried her past him

	# A reveals status beats the invisibility.
	await _seconds(delay + 0.1)
	var wall3 := _wall(pike.global_position.lerp(target.global_position, 0.5))
	await _physics_frames(3)
	var reveal := StatusEffect.new()
	reveal.id = &"test_reveal"
	reveal.duration = 1.0
	reveal.reveals = true
	pike.status_component.apply(reveal, target)
	_check("revealed, enemies see her", not CombatQueries.is_invisible(pike)
		and CombatQueries.has_line_of_sight(bystander, pike), "")
	wall3.queue_free()
	await _physics_frames(3)
	_check("revealed in her Beloved's view: she drops out of hiding", not obsession.is_unseen(), "")
	pike.status_component.remove(&"test_reveal")
	LocalView.clear_viewer()
	_clear()
	await _physics_frames(2)


# 0.4 x Weapon + 0.5% of the target's max HP.
func _knife_damage(target: TrainingDummy) -> float:
	return 0.4 * pike.stats_component.get_stat(&"weapon") + 0.005 * target.health_component.max_health


# --- Knives and Bleeding ------------------------------------------------------------------------

func _test_knives_and_bleed() -> void:
	print("\n-- Knives and Bleeding")
	_reset(Vector2(0, 9000))
	var target := _dummy(Vector2(400, 9000), &"b", 4000.0)
	await _physics_frames(2)
	hits_log.clear()
	_aim(target.global_position)
	for i in 40:    # held for ~0.65 s: three knives at 4/s
		pike.request_slot(&"primary", target.global_position)
		await get_tree().physics_frame
	await _seconds(0.5)
	var hits := hits_log.filter(func(i): return i.target == target and i.label == &"juggled_knives")
	_check("each knife: 0.4 x Weapon + 0.5% of max HP", not hits.is_empty() and _near(hits[0].amount, _knife_damage(target), 0.1),
		"%.1f vs %.1f" % [hits[0].amount if not hits.is_empty() else 0.0, _knife_damage(target)])
	var stacks := target.status_component.get_stacks(&"pike_bleed")
	_check("(three knives landed)", hits.size() >= 3, str(hits.size()))
	_check("every knife adds a stack of Bleeding", stacks == hits.size() and stacks >= 3, "%d stacks / %d knives" % [stacks, hits.size()])
	var bleed := hits_log.filter(func(i): return i.target == target and i.label == &"bleed")
	var tick := (1.0 + 0.08 * pike.stats_component.get_stat(&"weapon")) * stacks
	_check("bleed ticks are true damage: (1 + 8% Weapon) per stack", not bleed.is_empty()
		and bleed[0].type == DamageInfo.Type.TRUE and _near(bleed[0].final_amount, tick * GameRules.current().ttk_damage_multiplier, 0.2),
		"%s vs %.1f" % [str(bleed.map(func(i): return i.final_amount)), tick])
	for i in 12:
		pike.get_ranged_ability().add_ammo(5)
		pike.request_slot(&"primary", target.global_position)
		await _seconds(0.26)
	_check("bleed stacks cap at 8", target.status_component.get_stacks(&"pike_bleed") == 8,
		str(target.status_component.get_stacks(&"pike_bleed")))
	var before := hits_log.size()
	await _seconds(1.0)
	var later := hits_log.slice(before).filter(func(i): return i.target == target and i.label == &"bleed")
	var full := (1.0 + 0.08 * pike.stats_component.get_stat(&"weapon")) * 8.0 * GameRules.current().ttk_damage_multiplier
	_check("eight stacks tick for 8x", not later.is_empty() and _near(later[0].final_amount, full, 0.3),
		"%s vs %.1f" % [str(later.map(func(i): return i.final_amount)), full])
	_clear()
	await _physics_frames(2)


# --- Crazed Devotion -----------------------------------------------------------------------------

func _test_crazed_devotion() -> void:
	print("\n-- Crazed Devotion")
	_reset(Vector2(0, 10500))
	var cc := pike.get_ability(&"cc")
	var low := _dummy(Vector2(250, 10500), &"b")
	var healthy := _dummy(Vector2(450, 10500 + 40), &"b")
	low.can_die = true
	healthy.can_die = true
	await _physics_frames(2)
	low.health_component.current_health = low.health_component.max_health * 0.10
	hits_log.clear()
	_aim(Vector2(700, 10500))
	pike.request_slot(&"cc", Vector2(700, 10500))
	await _seconds(0.7)
	_check("the dash travels ~550 px", absf(pike.global_position.x - 550.0) < 40.0, str(pike.global_position))
	_check("it cuts everyone it runs through once", _sum(healthy, &"crazed_devotion") > 0.0
		and hits_log.filter(func(i): return i.target == healthy and i.label == &"crazed_devotion").size() == 1, "")
	_check("a target at 10% health is executed", low.health_component.is_dead(), str(low.health_component.current_health))
	var executes := hits_log.filter(func(i): return i.target == low and i.label == &"crazed_devotion_execute")
	_check("...by a true-damage execute", not executes.is_empty() and executes[0].type == DamageInfo.Type.TRUE, "")
	_check("a healthy target survives", not healthy.health_component.is_dead(), "")
	_check("a kill brings the dash back at once", cc.cooldown_remaining == 0.0, "%.1f" % cc.cooldown_remaining)

	# No kill: the cooldown stays.
	_reset(Vector2(0, 10500))
	await _physics_frames(2)
	pike.request_slot(&"cc", Vector2(700, 10500))
	await _seconds(0.7)
	_check("no kill: the cooldown is spent (14 s)", cc.cooldown_remaining > 12.0, "%.1f" % cc.cooldown_remaining)
	_clear()

	# Bleeding raises the threshold: 22% health is safe alone, dead with 4 stacks.
	_reset(Vector2(0, 11000))
	var plain := _dummy(Vector2(250, 11000), &"b")
	var bleeding := _dummy(Vector2(250, 11300), &"b")
	plain.can_die = true
	bleeding.can_die = true
	await _physics_frames(2)
	var bleed := load("res://heroes/pike/data/pike_bleed.tres") as StatusEffect
	for i in 4:
		bleeding.status_component.apply(bleed, pike)
	for d in [plain, bleeding]:
		d.health_component.current_health = d.health_component.max_health * 0.22
	pike.global_position = Vector2(0, 11000)
	_aim(Vector2(700, 11000))
	pike.request_slot(&"cc", Vector2(700, 11000))
	await _seconds(0.7)
	_check("22% health, no bleed: not executed", not plain.health_component.is_dead(), "")
	pike.global_position = Vector2(0, 11300)
	pike.get_ability(&"cc").cooldown_remaining = 0.0
	_aim(Vector2(700, 11300))
	pike.request_slot(&"cc", Vector2(700, 11300))
	await _seconds(0.7)
	_check("22% health with 4 stacks of bleed (15% + 8%): executed", bleeding.health_component.is_dead(), "")
	_clear()
	await _physics_frames(2)


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


func _sum(target: Node, label: StringName) -> float:
	var total := 0.0
	for info in hits_log:
		if info.target == target and info.label == label:
			total += info.final_amount
	return total


func _near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= maxf(tolerance, absf(b) * 0.001)


func _test_audio(audio) -> void:
	print("\n-- Audio")
	for c in audio.checks():
		_check(c[0], c[1], c[2])


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
