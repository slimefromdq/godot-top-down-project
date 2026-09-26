extends Node2D

# Headless checks for Butler's kit and the shared pieces it added
# (AbilityController.swap_slot / restore_slot, FrontalBlocker + BlockerData /
# BlockerAbility, AbilityData.lifesteal, ChargeData.dash_status,
# AllyTargeting.optional, Ability.get_hud_meter).
#
#   godot --headless res://tools/heroes/butler_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const BUTLER := "res://heroes/butler/butler_hero.tscn"
const ALLY := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var butler: Hero
var hunger: Node
var hits_log: Array[DamageInfo] = []
var spawned: Array[Node] = []


func _ready() -> void:
	CombatEvents.damage_dealt.connect(func(info: DamageInfo): hits_log.append(info))
	_run.call_deferred()


func _run() -> void:
	butler = load(BUTLER).instantiate()
	butler.team = &"a"
	add_child(butler)
	await _physics_frames(3)
	hunger = butler.get_ability(&"passive")
	_test_assembled()
	await _test_hunger_to_starving()
	await _test_cooldowns_survive_swaps()
	await _test_bites()
	await _test_cloak()
	await _test_dinner_is_served()
	await _test_at_your_service()
	await _test_other_moves()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_assembled() -> void:
	print("\n-- Assembly")
	for slot in [&"primary", &"ability_1", &"movement", &"cc", &"ultimate", &"passive"]:
		_check("slot %s filled" % slot, butler.get_ability(slot) != null, "")
	var definition := butler.definition
	_check("definition validates", definition.validate().is_empty(), "\n".join(definition.validate()))
	_check("name, title and role", definition.display_name == "Butler"
		and definition.title == "The Composed" and definition.get_role_name() == "Tank", "")
	_check("listed in hero selection (F1 > Play as)",
		HeroScaffold.find_definitions().any(func(d): return d.hero_id == &"butler"), "")
	var stats := definition.stats
	_check("L1 -> L10 stats match the design", _near(stats.health.value_at(1), 900.0) and _near(stats.health.value_at(10), 1750.0)
		and _near(stats.weapon.value_at(10), 78.0) and _near(stats.magic.value_at(10), 45.0)
		and _near(stats.armor.value_at(10), 70.0) and _near(stats.magic_resist.value_at(10), 52.0), "")
	_check("Composed kit: Cane, Vampiric Cloak, At Your Service, Polite Refusal", _ids() == [&"cane", &"vampiric_cloak",
		&"at_your_service", &"polite_refusal"], str(_ids()))
	_check("the cloak is the shared BlockerAbility (data only)", butler.get_ability(&"ability_1").get_script() == BlockerAbility, "")
	_check("Hunger shows as a meter on the ability bar", hunger.get_hud_meter() == 0.0, "")


func _ids() -> Array:
	return [&"primary", &"ability_1", &"movement", &"cc"].map(func(s): return butler.get_ability(s).ability_id)


# --- Hunger -----------------------------------------------------------------------------

func _test_hunger_to_starving() -> void:
	print("\n-- Hunger")
	_reset(Vector2(0, 0))
	var enemy := _dummy(Vector2(0, 600))
	await _physics_frames(2)
	var max_hp := butler.health_component.max_health
	butler.hurtbox.take_hit(DamageInfo.create(max_hp * 0.1 * _armor_factor(), enemy))
	_check("+1 Hunger per 1% of max HP lost", absf(hunger.hunger - 10.0) < 0.5, "%.2f" % hunger.hunger)
	butler.health_component.reset()
	await _seconds(1.0)
	_check("+1 per second in combat", absf(hunger.hunger - 11.0) < 0.3, "%.2f" % hunger.hunger)
	await _seconds(3.2)
	var idle: float = hunger.hunger
	await _seconds(1.0)
	_check("...not out of combat (3 s after the last hit)", absf(hunger.hunger - idle) < 0.01, "%.2f" % hunger.hunger)

	hunger.recover()
	hunger._set_hunger(0.0)
	var events := 0
	while not hunger.is_starving() and events < 12:
		butler.hurtbox.take_hit(DamageInfo.create(max_hp * 0.1 * _armor_factor(), enemy))
		butler.health_component.reset()
		events += 1
	_check("losing 100% of max HP in damage triggers Starving", hunger.is_starving() and events <= 10, "%d hits" % events)
	_check("Starving swaps the kit: Claws, Bite, Pounce, Hiss", _ids() == [&"claws", &"bite", &"pounce", &"hiss"], str(_ids()))
	_check("...the ultimate stays", butler.get_ability(&"ultimate").ability_id == &"dinner_is_served", "")
	_check("...for up to 8 s", _near(hunger.get_starving_time_left(), 8.0, 0.1), "%.2f" % hunger.get_starving_time_left())
	var level: float = hunger.hunger
	butler.hurtbox.take_hit(DamageInfo.create(max_hp * 0.1 * _armor_factor(), enemy))
	butler.health_component.reset()
	_check("damage doesn't add Hunger while Starving", hunger.hunger == level, "")
	await _seconds(8.2)
	_check("after 8 s he recovers on his own", not hunger.is_starving() and _ids()[0] == &"cane", str(_ids()))
	_clear()


func _armor_factor() -> float:
	# Damage is PHYSICAL: undo the armor so final damage is the % we want.
	return 1.0 / GameRules.current().resistance_multiplier(butler.stats_component.get_stat(&"armor"))


func _test_cooldowns_survive_swaps() -> void:
	print("\n-- Forms keep their cooldowns")
	_reset(Vector2(0, 3000))
	var refusal := butler.get_ability(&"cc")
	refusal.cooldown_remaining = 6.0
	hunger.start_starving()
	await _physics_frames(1)
	var hiss := butler.get_ability(&"cc")
	_check("swap_slot puts a different ability in the slot", hiss != refusal and hiss.ability_id == &"hiss", "")
	_check("the swapped-in form has its own (ready) cooldown", hiss.is_ready(), "")
	_check("the swapped-out one is dormant and not castable", refusal.is_dormant() and refusal.get_block_reason() == "Dormant", "")
	hiss.cooldown_remaining = 5.0
	await _seconds(1.0)
	_check("the dormant cooldown keeps ticking", _near(refusal.cooldown_remaining, 5.0, 0.05), "%.2f" % refusal.cooldown_remaining)
	hunger.recover()
	await _physics_frames(1)
	_check("restore_slot brings back the same ability, cooldown intact", butler.get_ability(&"cc") == refusal
		and _near(refusal.cooldown_remaining, 5.0, 0.05), "%.2f" % refusal.cooldown_remaining)
	await _seconds(0.5)
	hunger.start_starving()
	await _physics_frames(1)
	_check("swapping back reuses the same Starving ability, cooldown intact", butler.get_ability(&"cc") == hiss
		and _near(hiss.cooldown_remaining, 3.5, 0.05), "%.2f" % hiss.cooldown_remaining)
	hunger.recover()
	_check("is_slot_swapped follows", not butler.ability_controller.is_slot_swapped(&"cc"), "")
	_clear()


func _test_bites() -> void:
	print("\n-- Bite")
	_reset(Vector2(0, 6000))
	var enemy := _dummy(Vector2(110, 6000))
	enemy.team = &"b"
	await _physics_frames(2)
	hunger.start_starving()
	await _physics_frames(1)
	var bite := butler.get_ability(&"ability_1")
	butler.health_component.apply_damage(DamageInfo.create(300.0, enemy))
	var hp_before := butler.health_component.current_health
	hits_log.clear()
	for i in 2:
		await _bite(bite, enemy)
	_check("two Bites bring Hunger from 100 to 30", _near(hunger.hunger, 30.0, 0.01) and hunger.is_starving(), "%.2f" % hunger.hunger)
	var bitten := hits_log.filter(func(i): return i.target == enemy and i.label == &"bite")
	_check("Bite stuns 0.5 s", enemy.status_component.has_status(&"butler_bite"), "")
	_check("...and drains: Butler heals the damage dealt", bitten.size() == 2
		and butler.health_component.current_health > hp_before, "%.0f -> %.0f" % [hp_before, butler.health_component.current_health])
	await _bite(bite, enemy)
	_check("three return him to Composed", not hunger.is_starving() and _ids()[0] == &"cane", str(_ids()))
	_check("...rooted 0.6 s while he straightens his tie", butler.status_component.has_status(&"butler_straighten_tie")
		and butler.status_component.is_rooted(), "")
	await _seconds(0.75)
	_check("...then bonus armor for 3 s", butler.status_component.has_status(&"butler_composed"), "")
	_clear()


func _bite(bite: Ability, enemy: Node2D) -> void:
	bite.cooldown_remaining = 0.0
	enemy.status_component.clear()
	_aim(enemy.global_position)
	butler.request_slot(&"ability_1", enemy.global_position)
	await _seconds(0.45)


# --- Vampiric Cloak --------------------------------------------------------------------

func _test_cloak() -> void:
	print("\n-- Vampiric Cloak")
	_reset(Vector2(0, 9000))
	var shooter := _dummy(Vector2(500, 9000))
	shooter.team = &"b"
	await _physics_frames(2)
	var cloak := butler.get_ability(&"ability_1") as BlockerAbility
	_aim(Vector2(500, 9000))
	butler.request_slot(&"ability_1", Vector2(500, 9000))
	await _physics_frames(3)
	var blocker := cloak.blocker
	_check("holding raises the cloak", cloak.is_held() and blocker.is_raised(), "")
	_check("its HP is 400 at level 1", _near(blocker.max_hp, 400.0) and _near(blocker.hp, 400.0), "%.0f" % blocker.max_hp)
	_check("-30% move speed while raised", _near(butler.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 0.7), "")
	_check("the cane can't swing while it's up", butler.get_ability(&"primary").get_block_reason() != "", butler.get_ability(&"primary").get_block_reason())
	var hp := butler.health_component.current_health
	var absorbed := [0.0]
	blocker.absorbed.connect(func(amount, _info): absorbed[0] += amount)
	var broke := [false]
	blocker.broken.connect(func(): broke[0] = true)
	for i in 4:
		_bolt(shooter, 100.0)
		await _seconds(0.3)
	_check("the cloak absorbs exactly its HP", _near(absorbed[0], 400.0) and butler.health_component.current_health == hp,
		"%.0f absorbed, HP %.0f -> %.0f" % [absorbed[0], hp, butler.health_component.current_health])
	_check("...and then breaks", broke[0] and not blocker.is_raised() and blocker.is_broken(), "")
	_check("breaking drops the lock and the slow", butler.get_ability(&"primary").get_block_reason() == ""
		and _near(butler.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.0), "")
	_bolt(shooter, 100.0)
	await _seconds(0.3)
	_check("the next shot reaches Butler", butler.health_component.current_health < hp, "")
	_check("a broken cloak can't go straight back up", not blocker.can_raise(), "")
	await _seconds(1.5 + 0.25 / 0.15 + 0.1)
	_check("it regenerates while lowered and can be raised again", blocker.can_raise() and blocker.hp > 100.0, "%.0f" % blocker.hp)

	butler.health_component.reset()
	cloak.cooldown_remaining = 0.0
	butler.request_slot(&"ability_1", Vector2(500, 9000))
	await _physics_frames(3)
	_aim(Vector2(-500, 9000))
	hp = butler.health_component.current_health
	_bolt(shooter, 100.0)
	await _seconds(0.3)
	_check("it only covers the front: turned away, shots get through", butler.health_component.current_health < hp, "")
	butler.release_slot(&"ability_1", Vector2.ZERO)
	await _physics_frames(1)
	_check("letting go lowers it with a +20% speed flourish", not blocker.is_raised()
		and _near(butler.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.2), "")
	_clear()


func _bolt(shooter: Node2D, damage: float) -> void:
	var bolt := ProjectileData.new()
	bolt.speed = 2000.0
	bolt.lifetime = 0.5
	bolt.radius = 10.0
	var dir := (butler.global_position - shooter.global_position).normalized()
	Projectile.fire(shooter, bolt, shooter.global_position + dir * 40.0, dir, DamageInfo.create(damage, shooter))


# --- Dinner Is Served ------------------------------------------------------------------------

func _test_dinner_is_served() -> void:
	print("\n-- Dinner Is Served")
	_reset(Vector2(0, 12000))
	var on_path := _dummy(Vector2(400, 12000))
	on_path.team = &"b"
	await _physics_frames(2)
	butler.health_component.apply_damage(DamageInfo.create(400.0, on_path))
	var hp := butler.health_component.current_health
	hits_log.clear()
	_aim(Vector2(1200, 12000))
	butler.request_slot(&"ultimate", Vector2(1200, 12000))
	await _physics_frames(4)
	_check("he flies as a bat swarm: untargetable", butler.status_component.is_untargetable(), "")
	await _seconds(0.9)
	_check("900 px", absf(butler.global_position.x - 900.0) < 30.0, "%.0f" % butler.global_position.x)
	_check("...draining every enemy he passes", hits_log.any(func(i): return i.target == on_path and i.label == &"dinner_is_served")
		and butler.health_component.current_health > hp, "")
	_check("Dinner Is Served leaves him Starving with a full 8 s", hunger.is_starving()
		and hunger.get_starving_time_left() > 7.0, "%.2f s" % hunger.get_starving_time_left())
	_check("...and targetable again after the flight", not butler.status_component.is_untargetable(), "")
	hunger.recover()
	_clear()


# --- At Your Service --------------------------------------------------------------------------

func _test_at_your_service() -> void:
	print("\n-- At Your Service")
	_reset(Vector2(0, 15000))
	var ally: Hero = load(ALLY).instantiate()
	ally.team = &"a"
	add_child(ally)
	spawned.append(ally)
	ally.global_position = Vector2(600, 15000)
	await _physics_frames(2)
	_aim(Vector2(600, 15000))
	butler.request_slot(&"movement", Vector2(600, 15000))
	await _seconds(0.6)
	_check("dashes to an ally near the cursor", butler.global_position.distance_to(ally.global_position) < 120.0,
		"%.0f px" % butler.global_position.distance_to(ally.global_position))
	var expected := 150.0 + 0.6 * butler.stats_component.get_stat(&"magic")
	_check("...and shields them for 150 + 60% Magic", _near(ally.status_component.get_shield_total(), expected, 1.0),
		"%.0f vs %.0f" % [ally.status_component.get_shield_total(), expected])

	_reset(Vector2(0, 15500))
	_aim(Vector2(0, 16500))
	butler.request_slot(&"movement", Vector2(0, 16500))
	await _seconds(0.5)
	_check("with no ally: a short dash (250 px)", absf(butler.global_position.y - 15750.0) < 20.0, "%.0f" % (butler.global_position.y - 15500.0))
	_clear()


# --- The rest ----------------------------------------------------------------------------------

func _test_other_moves() -> void:
	print("\n-- Polite Refusal, Claws, Pounce, Hiss")
	_reset(Vector2(0, 18000))
	var near := _dummy(Vector2(120, 18000))
	near.team = &"b"
	await _physics_frames(2)
	_aim(near.global_position)
	butler.request_slot(&"cc", near.global_position)
	await _seconds(0.6)
	_check("Polite Refusal knocks enemies back ~250 px", near.global_position.x > 330.0, "%.0f" % near.global_position.x)

	_reset(Vector2(0, 21000))
	var prey := _dummy(Vector2(500, 21100))
	prey.team = &"b"
	var other := _dummy(Vector2(500, 20500))
	other.team = &"b"
	await _physics_frames(2)
	hunger.start_starving()
	await _physics_frames(1)
	_aim(Vector2(520, 21150))
	butler.request_slot(&"movement", Vector2(520, 21150))
	await _seconds(0.5)
	_check("Pounce dashes to the enemy nearest the cursor", butler.global_position.distance_to(prey.global_position) < 120.0,
		"%.0f px" % butler.global_position.distance_to(prey.global_position))
	var hp := butler.health_component.current_health
	butler.health_component.apply_damage(DamageInfo.create(200.0, prey))
	hp = butler.health_component.current_health
	hits_log.clear()
	_aim(prey.global_position)
	for i in 3:
		butler.request_slot(&"primary", prey.global_position)
		await _seconds(0.2)
	var claws := hits_log.filter(func(i): return i.target == prey and i.label == &"claws")
	var dealt: float = claws.reduce(func(sum, i): return sum + i.final_amount, 0.0)
	_check("Claws heal 25% of their damage", not claws.is_empty()
		and _near(butler.health_component.current_health - hp, dealt * 0.25, 0.5),
		"healed %.1f of %.1f" % [butler.health_component.current_health - hp, dealt])
	butler.get_ability(&"cc").cooldown_remaining = 0.0
	butler.request_slot(&"cc", prey.global_position)
	await _seconds(0.3)
	_check("Hiss slows 40% and silences", prey.status_component.has_status(&"butler_hiss")
		and _near(prey.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 0.6)
		and prey.status_component.is_silenced(), "")
	hunger.recover()
	_clear()


# --- Helpers -------------------------------------------------------------------------------------

func _reset(at: Vector2) -> void:
	if hunger.is_starving():
		hunger.recover()
	hunger._set_hunger(0.0)
	hunger._last_combat = -INF
	butler.ability_controller.interrupt()
	butler.ability_controller.unlock_abilities(butler.get_ability(&"ability_1"))
	butler.status_component.clear()
	butler.movement_component.stop_forced_move()
	butler.global_position = at
	butler.velocity = Vector2.ZERO
	butler.move_direction = Vector2.ZERO
	butler.health_component.reset()
	for ability in butler.ability_controller.abilities:
		ability.cooldown_remaining = 0.0
	_aim(at + Vector2(300, 0))


func _aim(at: Vector2) -> void:
	butler.aim_point = at
	butler.aim_direction = (at - butler.global_position).normalized()


func _dummy(at: Vector2, hp: float = 50000.0) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = hp
	add_child(d)
	spawned.append(d)
	return d


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
