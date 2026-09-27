extends Node2D

# Ultimate charge (UltimateCharge, MatchRules > Ultimate), headless:
#   godot --headless res://tools/match/ultimate_test.tscn
# Uses the data-only Ranged Test hero, whose ultimate is a cone gun.

const HERO := preload("res://scenes/heroes/hero_base.tscn")
const TEST_HERO := preload("res://tools/heroes/ranged_test/ranged_test_definition.tres")
const AVERY := preload("res://heroes/avery/avery_definition.tres")

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Off the match, the ultimate keeps its cooldown (training maps, hero tests).
	var loose := _hero(&"a", Vector2(0, -2000))
	await _frames(3)
	_check("no charge off the match", UltimateCharge.find_on(loose) == null
		and loose.get_ability(&"ultimate").get_ultimate_charge() < 0.0)
	_check("ultimate casts off the match", loose.request_slot(&"ultimate", loose.global_position + Vector2.RIGHT * 300))
	_check("and spends its cooldown", loose.get_ability(&"ultimate").cooldown_remaining > 0.0)
	loose.queue_free()

	var manager := MatchManager.new()
	manager.auto_start = false
	add_child(manager)
	var rules := manager.get_rules()
	var hero := _hero(&"a", Vector2.ZERO)
	var enemy := _hero(&"b", Vector2(400, 0))
	var ally := _hero(&"a", Vector2(0, 400))
	await _frames(3)
	var charge := UltimateCharge.find_on(hero)
	var ultimate := hero.get_ability(&"ultimate")
	_check("every match hero gets an UltimateCharge", charge != null and UltimateCharge.find_on(enemy) != null)
	_check("heroes start with no ultimate", charge.charge == 0.0 and not ultimate.is_ready())
	_check("the ultimate can't be cast empty", not hero.request_slot(&"ultimate", enemy.global_position))
	_check("other slots aren't gated", UltimateCharge.for_ability(hero.get_ability(&"primary")) == null)
	_check("the HUD reads the charge", is_equal_approx(ultimate.get_ultimate_charge(), 0.0)
		and is_equal_approx(ultimate.get_cooldown_ratio(), 1.0))

	manager.start_warmup()
	await _seconds(1.2)
	_check("nothing charges during the warmup", charge.charge == 0.0)
	manager.start_playing()
	await _seconds(2.2)
	_check("time charges it while playing", charge.charge >= rules.ult_charge_per_second * 1.5)

	var before := charge.charge
	enemy.health_component.apply_damage(DamageInfo.create(200.0, hero))
	var dealt := charge.charge - before
	_check("damage dealt to enemy heroes charges it (%.2f)" % dealt, dealt > 0.0)
	before = UltimateCharge.find_on(enemy).charge
	hero.health_component.apply_damage(DamageInfo.create(100.0, enemy))
	_check("damage taken charges the victim", UltimateCharge.find_on(hero).charge > 0.0)
	before = charge.charge
	ally.health_component.apply_damage(DamageInfo.create(150.0, enemy))
	ally.health_component.heal(100.0, hero)
	_check("healing a teammate charges the healer", charge.charge > before)
	before = charge.charge
	enemy.health_component.kill(hero)
	_check("a kill charges the killer", charge.charge - before >= rules.ult_charge_kill - 0.01)

	charge.set_charge(charge.maximum)
	_check("full charge readies the ultimate", ultimate.is_ready()
		and is_equal_approx(ultimate.get_ultimate_charge(), 1.0))
	await _frames(2)
	_check("a full ultimate casts", hero.request_slot(&"ultimate", hero.global_position + Vector2.RIGHT * 300))
	_check("casting spends all the charge, no cooldown", charge.charge == 0.0 and ultimate.cooldown_remaining == 0.0)

	# Avery's passive ultimate (a revive) spends the charge too.
	var avery := _hero(&"a", Vector2(-600, 0), AVERY)
	await _frames(3)
	var avery_charge := UltimateCharge.find_on(avery)
	avery.health_component.kill(null)
	_check("an empty passive ultimate doesn't revive", avery.health_component.is_dead())
	manager.respawn_now(avery)
	avery_charge.set_charge(avery_charge.maximum)
	avery.health_component.apply_damage(DamageInfo.create(1.0e6, null, DamageInfo.Type.TRUE))
	_check("a charged revive triggers and spends the charge",
		not avery.health_component.is_dead() and avery_charge.charge == 0.0)

	# Deposits charge the depositor.
	var dreamer := Dreamer.new()
	dreamer.team = &"b"
	dreamer.position = Vector2(0, 1200)
	add_child(dreamer)
	await _frames(2)
	before = charge.charge
	var carrier := MoteCarrier.find_on(hero)
	for i in 4:
		carrier.add_mote(MoteDirector.find(get_tree()).small_data, 1)
	hero.global_position = dreamer.global_position + Vector2(0, 230)
	await _seconds(1.5)
	_check("depositing Motes charges the depositor", charge.charge - before >= rules.ult_charge_per_mote_value * 3.0)

	# Turning the rule off: new heroes use cooldowns.
	rules.ultimate_charge_enabled = false
	var late := _hero(&"b", Vector2(0, -600))
	await _frames(3)
	_check("the rule off gives no charge", UltimateCharge.find_on(late) == null)
	for node in [hero, enemy, ally, avery, late, dreamer, manager]:
		node.queue_free()
	await _frames(2)
	print("ULTIMATE TEST: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)


func _hero(team: StringName, at: Vector2, definition: HeroDefinition = TEST_HERO) -> Hero:
	var hero: Hero = HERO.instantiate()
	hero.definition = definition
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures += 1
