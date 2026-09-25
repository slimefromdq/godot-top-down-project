extends Node

# Headless checks for the hero infrastructure (stats, damage pipeline, hitbox,
# projectiles, statuses, ability state machine, hooks).
#
#   godot --headless res://tools/heroes/infrastructure_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const TEMPLATE_HERO := "res://heroes/_template/template_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var hero: Hero
var dummy: TrainingDummy


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_stat_scaling()
	_test_resistances()
	await _setup_arena()
	await _test_hero_assembled()
	await _test_melee_hits_once_per_swing()
	await _test_combo_buffer_and_cancel()
	await _test_hooks_and_about_to_die()
	await _test_level_up_updates_health()
	await _test_statuses()
	await _test_projectile_pierce()
	await _test_team_filter()
	_test_validation()
	await _test_scaffold()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- Pure data -------------------------------------------------------------

func _test_stat_scaling() -> void:
	var linear := StatScaling.make(100.0, 10.0)
	_check("linear stat L1", is_equal_approx(linear.value_at(1), 100.0), str(linear.value_at(1)))
	_check("linear stat L10", is_equal_approx(linear.value_at(10), 190.0), str(linear.value_at(10)))
	_check("linear stat clamps above 20", is_equal_approx(linear.value_at(25), 290.0), str(linear.value_at(25)))

	var spike := StatScaling.make(100.0, 10.0)
	spike.curve = Curve.new()
	spike.curve.add_point(Vector2(0, 0))
	spike.curve.add_point(Vector2(0.5, 0.1))
	spike.curve.add_point(Vector2(1, 1))
	_check("curve: same value at L20 as linear", is_equal_approx(spike.value_at(20), linear.value_at(20)),
		"%.1f vs %.1f" % [spike.value_at(20), linear.value_at(20)])
	_check("curve: late spike is weaker mid-game", spike.value_at(10) < linear.value_at(10),
		"%.1f vs %.1f" % [spike.value_at(10), linear.value_at(10)])

	var value := ScalingValue.make(10.0, 0.5, 0.25, 2.0)
	_check("ScalingValue formula", is_equal_approx(value.evaluate_at(3, 40.0, 20.0), 10.0 + 4.0 + 20.0 + 5.0),
		str(value.evaluate_at(3, 40.0, 20.0)))


func _test_resistances() -> void:
	var rules := GameRules.current()
	_check("100 resist halves damage", is_equal_approx(rules.resistance_multiplier(100.0), 0.5), "")
	_check("0 resist = full damage", is_equal_approx(rules.resistance_multiplier(0.0), 1.0), "")
	_check("negative resist amplifies", rules.resistance_multiplier(-50.0) > 1.0, "")


# --- Arena ------------------------------------------------------------------

func _setup_arena() -> void:
	hero = load(TEMPLATE_HERO).instantiate()
	hero.team = &"a"
	add_child(hero)
	hero.global_position = Vector2.ZERO
	dummy = _spawn_dummy(Vector2(120, 0))
	await _frames(3)


func _spawn_dummy(at: Vector2) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	add_child(d)
	return d


func _test_hero_assembled() -> void:
	_check("hero built its primary", hero.get_ability(&"primary") is MeleeAttackAbility, "")
	_check("hero HP comes from stats", is_equal_approx(hero.health_component.max_health, 600.0),
		str(hero.health_component.max_health))
	_check("ability runs on a copy of its data",
		hero.get_ability(&"primary").data != hero.definition.get_ability(&"primary"), "")


func _test_melee_hits_once_per_swing() -> void:
	var hp_before := dummy.health_component.current_health
	var hits := [0]
	var count_hit := func(info: DamageInfo): if info.target == dummy: hits[0] += 1
	CombatEvents.damage_dealt.connect(count_hit)
	hero.aim_point = dummy.global_position
	var started := hero.request_slot(&"primary", dummy.global_position)
	await _seconds(0.6)
	CombatEvents.damage_dealt.disconnect(count_hit)
	# 20 + 0.6 * 40 Weapon = 44, no armor.
	var dealt := hp_before - dummy.health_component.current_health
	_check("swing started", started, "")
	_check("swing hits exactly once over its active frames", hits[0] == 1, "%d hits" % hits[0])
	_check("swing damage = base + weapon ratio", is_equal_approx(dealt, 44.0), "%.1f" % dealt)
	_check("knockback moved the dummy", dummy.global_position.x > 121.0 or dummy.velocity.length() > 0.0,
		"x=%.1f" % dummy.global_position.x)


func _test_combo_buffer_and_cancel() -> void:
	# Press during windup: can't start now, so it's buffered, then fires on its own.
	var primary := hero.get_ability(&"primary")
	await _seconds(1.0)
	hero.request_slot(&"primary", dummy.global_position)
	await _physics_frames(2)
	var second_accepted := hero.request_slot(&"primary", dummy.global_position)
	_check("press during windup is not started immediately", not second_accepted, "")
	var casts := [0]
	var on_act := func(): casts[0] += 1
	primary.activated.connect(on_act)
	await _seconds(0.7)
	primary.activated.disconnect(on_act)
	_check("buffered press fires after the window opens", casts[0] == 1, "%d" % casts[0])

	# Commitment slow while casting.
	await _seconds(1.0)
	hero.request_slot(&"primary", dummy.global_position)
	await _physics_frames(2)
	_check("walking is slowed while swinging", hero.movement_component.get_action_multiplier() < 1.0, "")
	hero.ability_controller.interrupt()
	_check("interrupt clears the slow", is_equal_approx(hero.movement_component.get_action_multiplier(), 1.0), "")


func _test_hooks_and_about_to_die() -> void:
	var dealt := [0]
	var on_hit := func(_info, _target): dealt[0] += 1
	hero.combat_hooks.hit_dealt.connect(on_hit)
	var info := DamageInfo.create(10.0, hero)
	dummy.hurtbox.take_hit(info)
	hero.combat_hooks.hit_dealt.disconnect(on_hit)
	_check("hit_dealt fires on the attacker", dealt[0] == 1, "")

	# A revive-like listener cancels the hero's death.
	var cancel := func(event: DeathEvent): event.cancel(hero.health_component.max_health * 0.5)
	hero.health_component.about_to_die.connect(cancel)
	var died := [false]
	var on_died := func(): died[0] = true
	hero.health_component.died.connect(on_died)
	hero.health_component.apply_damage(DamageInfo.create(99999.0, dummy, DamageInfo.Type.TRUE))
	_check("about_to_die can cancel death", not died[0] and not hero.health_component.is_dead(), "")
	_check("cancelled death restores chosen HP",
		is_equal_approx(hero.health_component.current_health, hero.health_component.max_health * 0.5),
		str(hero.health_component.current_health))
	hero.health_component.about_to_die.disconnect(cancel)
	hero.health_component.died.disconnect(on_died)
	hero.health_component.reset()

	# Kill credit reaches the attacker's hooks.
	var kills := [0]
	var on_kill := func(_victim, _info): kills[0] += 1
	hero.combat_hooks.kill.connect(on_kill)
	var victim := _spawn_dummy(Vector2(-600, 400))
	await _frames(2)
	victim.hurtbox.take_hit(DamageInfo.create(99999.0, hero, DamageInfo.Type.TRUE))
	hero.combat_hooks.kill.disconnect(on_kill)
	_check("kill hook fires on the attacker", kills[0] == 1, "")
	victim.queue_free()


func _test_level_up_updates_health() -> void:
	var levels := [0]
	var on_level := func(lvl): levels[0] = lvl
	hero.combat_hooks.level_up.connect(on_level)
	var hp_before := hero.health_component.current_health
	hero.stats_component.set_level(5)
	_check("level_up hook fires", levels[0] == 5, str(levels[0]))
	_check("max HP follows level", is_equal_approx(hero.health_component.max_health, 600.0 + 60.0 * 4), "")
	_check("current HP gains the difference", is_equal_approx(hero.health_component.current_health, hp_before + 240.0), "")
	hero.stats_component.set_level(99)
	_check("level clamps to the match cap", hero.stats_component.level == GameRules.current().max_level, "")
	hero.stats_component.add_modifier(StatModifier.make(StatBlock.WEAPON, 10.0, 0.5, &"test_item"))
	var expected := (40.0 + 4.0 * (hero.stats_component.level - 1) + 10.0) * 1.5
	_check("flat + percent modifiers", is_equal_approx(hero.stats_component.get_weapon(), expected),
		"%.1f vs %.1f" % [hero.stats_component.get_weapon(), expected])
	hero.stats_component.remove_modifiers_from(&"test_item")
	hero.stats_component.set_level(1)
	hero.health_component.reset()


func _test_statuses() -> void:
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 0.3
	stun.stuns = true
	hero.request_slot(&"primary", dummy.global_position)
	await _physics_frames(1)
	hero.status_component.apply(stun, dummy)
	_check("stun interrupts the current cast", not hero.ability_controller.is_busy(), "")
	_check("can't cast while stunned", not hero.request_slot(&"primary", dummy.global_position), "")
	await _seconds(0.4)
	_check("stun wears off", not hero.status_component.is_stunned(), "")

	var burn := StatusEffect.new()
	burn.id = &"test_burn"
	burn.duration = 1.0
	burn.tick_interval = 0.25
	burn.tick_damage = ScalingValue.make(5.0)
	burn.tick_damage_type = DamageInfo.Type.TRUE
	burn.tick_label = &"burn"
	var hp := dummy.health_component.current_health
	dummy.status_component.apply(burn, hero)
	await _seconds(1.1)
	_check("burn ticks 4 times for 5", is_equal_approx(hp - dummy.health_component.current_health, 20.0),
		"%.1f" % (hp - dummy.health_component.current_health))

	var knock := StatusEffect.new()
	knock.id = &"test_knock"
	knock.duration = 0.1
	knock.displace_distance = 100.0
	knock.displace_duration = 0.1
	knock.displace_direction = StatusEffect.DisplaceDirection.AWAY_FROM_SOURCE
	dummy.return_to_anchor = false
	var x_before := dummy.global_position.x
	dummy.status_component.apply(knock, hero)
	await _seconds(0.2)
	var pushed := dummy.global_position.x - x_before
	_check("knockback status pushes ~100px away", pushed > 85.0 and pushed < 115.0, "%.1f" % pushed)
	dummy.return_to_anchor = true

	var slow := StatusEffect.new()
	slow.id = &"test_slow"
	slow.stat_multipliers = {StatusEffect.MOVE_SPEED: 0.5}
	slow.stack_rule = StatusEffect.StackRule.STACK
	slow.max_stacks = 2
	var base_speed := hero.movement_component.get_move_speed()
	hero.status_component.apply(slow)
	hero.status_component.apply(slow)
	hero.status_component.apply(slow)
	_check("stacking caps at max_stacks", hero.status_component.get_stacks(&"test_slow") == 2, "")
	_check("stacked slow multiplies", is_equal_approx(hero.movement_component.get_move_speed(), base_speed * 0.25), "")
	hero.status_component.clear()


func _test_projectile_pierce() -> void:
	var a := _spawn_dummy(Vector2(0, 600))
	var b := _spawn_dummy(Vector2(0, 750))
	var c := _spawn_dummy(Vector2(0, 900))
	await _frames(2)
	var data := ProjectileData.new()
	data.speed = 3000.0
	data.lifetime = 1.0
	data.pierce = 1
	var template := DamageInfo.create(10.0, hero, DamageInfo.Type.TRUE)
	Projectile.fire(hero, data, Vector2(0, 450), Vector2.DOWN, template)
	await _seconds(0.5)
	_check("projectile hits first target", a.health_component.current_health < a.health_component.max_health, "")
	_check("projectile pierces once", b.health_component.current_health < b.health_component.max_health, "")
	_check("projectile stops after pierce", is_equal_approx(c.health_component.current_health, c.health_component.max_health), "")
	for d in [a, b, c]:
		d.queue_free()


func _test_team_filter() -> void:
	var ally := _spawn_dummy(Vector2(-120, 0))
	ally.team = &"a"
	await _frames(2)
	hero.status_component.clear()
	hero.ability_controller.interrupt()
	hero.request_slot(&"primary", ally.global_position)
	await _seconds(0.5)
	_check("melee ignores teammates", is_equal_approx(ally.health_component.current_health, ally.health_component.max_health), "")
	ally.queue_free()


func _test_validation() -> void:
	var def: HeroDefinition = load("res://heroes/_template/template_definition.tres")
	var problems := def.validate()
	var only_missing_slots := problems.size() > 0
	for p in problems:
		if not p.begins_with("missing required slot"):
			only_missing_slots = false
	_check("template only warns about unfilled slots", only_missing_slots, "\n  ".join(problems))
	var broken: HeroDefinition = def.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.stats.health.base = -5.0
	broken.abilities[&"primary"].damage.base = -1.0
	broken.abilities[&"bogus"] = null
	var broken_problems := broken.validate()
	_check("validation catches negatives and bad slots", broken_problems.size() >= 4, "\n  ".join(broken_problems))


func _test_scaffold() -> void:
	var dir := "res://heroes/scaffold_probe/"
	_remove_dir(dir)
	var error := HeroScaffold.create("Scaffold Probe")
	_check("scaffold creates a hero folder", error == "" and DirAccess.dir_exists_absolute(dir), error)
	if error != "":
		return
	var def_text := FileAccess.get_file_as_string(dir + "scaffold_probe_definition.tres")
	_check("scaffold rewrites paths away from _template", not def_text.contains("_template"), "")
	var probe: Hero = load(HeroScaffold.scene_path("Scaffold Probe")).instantiate()
	add_child(probe)
	probe.global_position = Vector2(-400, -400)
	await _frames(2)
	_check("scaffolded hero has its own basic attack",
		probe.get_ability(&"primary") != null
			and probe.get_ability(&"primary").get_script().resource_path == dir + "scaffold_probe_basic_attack.gd",
		"")
	_check("scaffolded hero id", probe.definition.hero_id == &"scaffold_probe", str(probe.definition.hero_id))
	probe.queue_free()
	await _frames(2)
	_remove_dir(dir)


func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file)
	DirAccess.remove_absolute(dir)


# --- Helpers ------------------------------------------------------------------

func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
