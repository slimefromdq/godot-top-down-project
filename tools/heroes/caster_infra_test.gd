extends Node2D

# Headless checks for the shared caster additions:
#   A1 per-type incoming damage multipliers (+ untargetable, body_alpha)
#   A2 returning / curving projectiles, explode_at
#   A3 REGEN ammo, set_max_ammo, set_regen_interval
#   A4 blend compel with a zone as the pull source
#   ChargeData stop_at_target + self_status
#
#   godot --headless res://tools/heroes/caster_infra_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"
const WALL := "res://scenes/wall.tscn"

var failures := 0
var hero: Hero
var spawned: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	hero = load(HERO).instantiate()
	hero.team = &"a"
	add_child(hero)
	await _physics_frames(3)

	await _test_damage_type_multipliers()
	await _test_untargetable()
	await _test_returning_projectile()
	await _test_explode_at()
	await _test_regen_ammo()
	await _test_zone_blend_pull()
	await _test_blink_stop_and_self_status()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- A1 -----------------------------------------------------------------------

func _status(id: StringName, physical: float, magic: float) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = 5.0
	effect.incoming_physical_multiplier = physical
	effect.incoming_magic_multiplier = magic
	return effect


func _hit(d: TrainingDummy, amount: float, type: DamageInfo.Type) -> float:
	var info := DamageInfo.create(amount, hero, type)
	d.hurtbox.take_hit(info)
	return info.final_amount


func _test_damage_type_multipliers() -> void:
	var d := _dummy(Vector2(0, 400))
	await _physics_frames(2)
	var status := d.status_component
	status.apply(_status(&"test_moonlit", 1.0, 1.5), hero)
	_check("a magic amp amplifies magic", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 150.0), "")
	_check("...not physical", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.PHYSICAL), 100.0), "")
	_check("...nor true damage", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.TRUE), 100.0), "")
	status.apply(_status(&"test_second_amp", 1.0, 1.2), hero)
	_check("multiple statuses multiply (1.5 x 1.2)", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 180.0), "")
	status.clear()
	status.apply(_status(&"test_weapon_resist", 0.5, 1.0), hero)
	_check("a weapon resist halves physical", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.PHYSICAL), 50.0), "")
	_check("...but not magic", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 100.0), "")
	var shocked := StatusEffect.new()
	shocked.id = &"test_all_types"
	shocked.duration = 5.0
	shocked.stat_multipliers = {StatusEffect.DAMAGE_TAKEN: 1.2}
	status.apply(shocked, hero)
	_check("all-types damage_taken still stacks with per-type", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.PHYSICAL), 60.0), "")
	status.clear()

	# The meter logs the final amount.
	DebugTools.meter.tracked = hero
	DebugTools.meter.reset()
	status.apply(_status(&"test_moonlit", 1.0, 1.5), hero)
	_hit(d, 100.0, DamageInfo.Type.MAGIC)
	_check("the meter logs the amplified amount", is_equal_approx(DebugTools.meter.get_total_dealt(), 150.0),
		"%.0f" % DebugTools.meter.get_total_dealt())
	DebugTools.meter.tracked = null
	status.clear()

	# Strength scales it; a refresh keeps the stronger application.
	var unit := _status(&"test_scaled", 1.0, 2.0)    # a +100% "unit"
	status.apply(unit, hero, Vector2.ZERO, 0.35)
	_check("strength scales the amp (+35%)", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 135.0), "")
	status.apply(unit, hero, Vector2.ZERO, 0.2)
	_check("a weaker refresh keeps the stronger amp", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 135.0), "")
	status.apply(unit, hero, Vector2.ZERO, 0.5)
	_check("a stronger refresh upgrades it", is_equal_approx(_hit(d, 100.0, DamageInfo.Type.MAGIC), 150.0), "")
	_clear()
	await _physics_frames(2)


func _test_untargetable() -> void:
	var d := _dummy(Vector2(200, 0))
	await _physics_frames(2)
	var vanish := StatusEffect.new()
	vanish.id = &"test_vanish"
	vanish.duration = 0.3
	vanish.untargetable = true
	vanish.body_alpha = 0.3
	d.status_component.apply(vanish, hero)
	await _physics_frames(1)
	var hp := d.health_component.current_health
	_hit(d, 100.0, DamageInfo.Type.TRUE)
	_check("untargetable: hits do nothing", d.health_component.current_health == hp, "")
	var slow := StatusEffect.new()
	slow.id = &"test_slow"
	slow.duration = 1.0
	d.hurtbox.take_hit(DamageInfo.create(10.0, hero).add_status(slow))
	_check("...and apply no statuses", not d.status_component.has_status(&"test_slow"), "")
	_check("...and queries skip it", Hitbox.query(self, d.global_position, Vector2.RIGHT, HitShape.circle(100.0), hero).is_empty(), "")
	_check("the silhouette fades (body_alpha)", is_equal_approx(d.visuals.modulate.a, 0.3), str(d.visuals.modulate.a))
	await _seconds(0.4)
	_check("afterwards it's hittable and opaque again", d.hurtbox.is_valid_target()
		and is_equal_approx(d.visuals.modulate.a, 1.0), "")
	_clear()
	await _physics_frames(2)


# --- A2 -----------------------------------------------------------------------

func _boomerang(curve: float = 0.0) -> ProjectileData:
	var data := ProjectileData.new()
	data.speed = 1500.0
	data.lifetime = 0.3    # 450 px out
	data.radius = 16.0
	data.pierce = -1
	data.return_to_caster = true
	data.curve_amount = curve
	return data


func _test_returning_projectile() -> void:
	hero.global_position = Vector2.ZERO
	var d := _dummy(Vector2(250, 0))
	var beyond := _dummy(Vector2(700, 0))
	await _physics_frames(2)
	var passes := []
	var projectile := Projectile.fire(hero, _boomerang(), Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(10.0, hero, DamageInfo.Type.MAGIC))
	projectile.pass_hit.connect(func(info, h, p): passes.append([h.owner, p, info.has_tag(Projectile.TAG_RETURN)]))
	var got_back := [false]
	projectile.returned.connect(func(): got_back[0] = true)
	var furthest := [0.0]
	var box := [projectile]    # a freed capture must be checked through a container
	var track := func(): if is_instance_valid(box[0]): furthest[0] = maxf(furthest[0], box[0].global_position.x)
	get_tree().physics_frame.connect(track)
	# Move the caster while it flies: it must come back to where she IS.
	await _seconds(0.25)
	hero.global_position = Vector2(0, 60)
	await _seconds(0.6)
	get_tree().physics_frame.disconnect(track)
	_check("hits once going out and once coming back", passes.size() == 2 and passes[0][0] == d and passes[1][0] == d
		and passes[0][1] == Projectile.Pass.OUTBOUND and passes[1][1] == Projectile.Pass.RETURN, str(passes))
	_check("return-pass hits carry the return tag", passes.size() == 2 and not passes[0][2] and passes[1][2], "")
	_check("flies to max range, no further", furthest[0] > 430.0 and furthest[0] < 470.0, "%.0f" % furthest[0])
	_check("...so the target beyond is never hit", beyond.health_component.current_health == beyond.health_component.max_health, "")
	_check("comes back to the caster's CURRENT position and despawns", got_back[0] and not is_instance_valid(projectile), "")
	_check("each pass damaged the target", is_equal_approx(d.health_component.max_health - d.health_component.current_health, 20.0), "")
	hero.global_position = Vector2.ZERO
	_clear()
	await _physics_frames(2)

	# A curve bends the path sideways; deterministic, so the same every time.
	var peaks := []
	for i in 2:
		var p := Projectile.fire(hero, _boomerang(0.4), Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(1.0, hero))
		var peak := [0.0]
		var held := [p]
		var watch := func(): if is_instance_valid(held[0]): peak[0] = maxf(peak[0], absf(held[0].global_position.y))
		get_tree().physics_frame.connect(watch)
		await _seconds(0.9)
		get_tree().physics_frame.disconnect(watch)
		peaks.append(peak[0])
	_check("curve_amount bends it into a crescent", peaks[0] > 60.0, "%.0f px off-line" % peaks[0])
	_check("...deterministically", is_equal_approx(peaks[0], peaks[1]), str(peaks))

	# A wall turns it around early.
	var wall: Node2D = load(WALL).instantiate()
	wall.position = Vector2(300, 0)
	add_child(wall)
	spawned.append(wall)
	await _physics_frames(2)
	var turned := [Vector2.INF]
	var p2 := Projectile.fire(hero, _boomerang(), Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(1.0, hero))
	p2.turned_back.connect(func(at): turned[0] = at)
	var back := [false]
	p2.returned.connect(func(): back[0] = true)
	await _seconds(0.8)
	_check("a wall turns it around early", turned[0].x < 250.0 and back[0], str(turned[0]))
	_clear()
	await _physics_frames(2)

	# The caster gone: it doesn't linger.
	var temp: Hero = load(HERO).instantiate()
	temp.team = &"a"
	add_child(temp)
	await _physics_frames(2)
	var p3 := Projectile.fire(temp, _boomerang(), Vector2.ZERO, Vector2.RIGHT, DamageInfo.create(1.0, temp))
	await _seconds(0.2)
	temp.queue_free()
	await _seconds(0.3)
	_check("no caster to return to: it expires", not is_instance_valid(p3), "")


func _test_explode_at() -> void:
	var inside := _dummy(Vector2(1000, 0))
	var outside := _dummy(Vector2(1300, 0))
	await _physics_frames(2)
	var data := ProjectileData.new()
	data.explosion_shape = HitShape.circle(150.0)
	var hits := []
	Projectile.explode_at(hero, data, Vector2(1050, 0), Vector2.RIGHT, DamageInfo.create(40.0, hero, DamageInfo.Type.MAGIC),
		func(_i, h): hits.append(h.owner))
	await _physics_frames(1)
	_check("explode_at: a blast with no flight", inside.health_component.max_health - inside.health_component.current_health == 40.0
		and outside.health_component.current_health == outside.health_component.max_health, "")
	_check("...reporting hits to the caller", hits == [inside], str(hits))
	_clear()
	await _physics_frames(2)


# --- A3 -----------------------------------------------------------------------

func _test_regen_ammo() -> void:
	var data := RangedAttackData.new()
	data.id = &"test_regen_gun"
	data.ability_script = RangedAttackAbility
	data.cooldown = 0.0
	data.projectile = ProjectileData.new()
	data.damage = ScalingValue.make(1.0)
	data.fire_mode = RangedAttackData.FireMode.SEMI
	data.shots_per_second = 20.0
	data.magazine_size = 3
	data.reload_style = RangedAttackData.ReloadStyle.REGEN
	data.regen_interval = 0.5
	data.feel_preset = &"shot"
	_check("REGEN data validates", data.validate().is_empty(), "\n".join(data.validate()))
	var gun := RangedAttackAbility.new()
	gun.set_data(data)
	hero.ability_controller.add_ability(gun, &"test_regen")
	await _physics_frames(1)
	for i in 3:
		hero.ability_controller.try_activate(gun, hero.global_position + Vector2(300, 0))
		await _seconds(0.08)
	_check("fires the magazine down", gun.get_ammo() == 0, str(gun.get_ammo()))
	_check("REGEN never 'reloads' (R does nothing)", not gun.start_reload() and not gun.is_reloading(), "")
	_check("firing empty is silent, no reload", not hero.ability_controller.try_activate(gun, Vector2(300, 0))
		and not gun.is_reloading(), "")
	await _seconds(0.3)
	# The clock started at the first shot (it runs while firing), so the
	# first round is already back and the next is on its way.
	_check("one round back per interval", gun.get_ammo() == 1, str(gun.get_ammo()))
	_check("regen ratio shows the next round's progress", gun.get_regen_ratio() > 0.0 and gun.get_regen_ratio() < 1.0,
		"%.2f" % gun.get_regen_ratio())
	await _seconds(0.15)
	hero.ability_controller.try_activate(gun, Vector2(300, 0))    # fire it: regen keeps running
	await _seconds(0.5)
	_check("...whether or not she's firing", gun.get_ammo() == 1, str(gun.get_ammo()))
	await _seconds(1.1)
	_check("refills one at a time up to the magazine", gun.get_ammo() == 3, str(gun.get_ammo()))

	var changes := []
	gun.ammo_changed.connect(func(a, m): changes.append([a, m]))
	gun.set_max_ammo(5)
	_check("set_max_ammo grows the magazine with new rounds loaded", gun.get_max_ammo() == 5 and gun.get_ammo() == 5
		and changes.back() == [5, 5], str(changes))
	gun.set_max_ammo(7, false)
	_check("set_max_ammo(fill_new = false) adds empty slots", gun.get_max_ammo() == 7 and gun.get_ammo() == 5, "")
	gun.set_max_ammo(2)
	_check("shrinking clamps", gun.get_ammo() == 2, "")
	gun.set_regen_interval(0.2)
	gun.set_max_ammo(4, false)
	await _seconds(0.45)
	_check("set_regen_interval speeds regen up", gun.get_ammo() == 4, str(gun.get_ammo()))
	hero.ability_controller.remove_all()
	await _physics_frames(1)


# --- A4 -----------------------------------------------------------------------

func _test_zone_blend_pull() -> void:
	var pull := StatusEffect.new()
	pull.id = &"test_whirlpool"
	pull.duration = 0.3
	pull.compel_enabled = true
	pull.compel_overrides_input = false    # blend: added to their own steering
	pull.compel_speed_multiplier = 0.6
	pull.compel_stop_distance = 10.0
	var zone_data := GroundZoneData.new()
	zone_data.shape = HitShape.circle(300.0)
	zone_data.duration = 1.5
	zone_data.tick_interval = 0.1
	zone_data.status_while_inside = pull
	zone_data.statuses_from_zone = true
	var center := Vector2(0, -1500)
	var idle := _dummy(center + Vector2(200, 0))
	idle.return_to_anchor = false
	var struggler := _dummy(center + Vector2(-150, 0))
	struggler.anchor = center + Vector2(-1500, 0)    # it keeps walking away
	await _physics_frames(2)
	var zone := GroundZone.spawn(hero, zone_data, center, Vector2.RIGHT, hero)
	await _seconds(1.0)
	var idle_gap := idle.global_position.distance_to(center)
	var struggled := struggler.global_position.distance_to(center) - 150.0
	_check("the zone's pull comes from the zone itself", idle.status_component.get_applier(&"test_whirlpool") == zone, "")
	# 0.6 x 220 px/s = 132 px/s toward the centre, from 200 px out.
	_check("a target that doesn't resist is pulled to the centre", idle_gap < 90.0, "%.0f px from centre" % idle_gap)
	_check("a target walking away still gets out, slowly", struggled > 20.0 and struggled < 0.6 * 220.0,
		"%.0f px in 1 s (free walking: 220)" % struggled)
	await _seconds(0.8)
	_check("the pull ends with the zone", not idle.status_component.has_status(&"test_whirlpool"), "")
	_clear()
	await _physics_frames(2)


# --- Blink --------------------------------------------------------------------

func _test_blink_stop_and_self_status() -> void:
	hero.global_position = Vector2(0, 2000)
	var wall: Node2D = load(WALL).instantiate()
	wall.position = Vector2(-300, 2000)    # face at x = -236
	add_child(wall)
	spawned.append(wall)
	var vanish := StatusEffect.new()
	vanish.id = &"test_vanish"
	vanish.duration = 0.5
	vanish.untargetable = true
	var data := ChargeData.new()
	data.id = &"test_blink"
	data.ability_script = ChargeAbility
	data.cooldown = 0.0
	data.distance = 400.0
	data.speed = 12000.0
	data.stop_at_target = true
	data.self_status = vanish
	data.carry_momentum = false
	data.tags = [&"movement"]
	data.feel_preset = &"shot"
	var blink := ChargeAbility.new()
	blink.set_data(data)
	hero.ability_controller.add_ability(blink, &"test_blink")
	await _physics_frames(2)
	hero.ability_controller.try_activate(blink, Vector2(150, 2000))
	await _seconds(0.1)
	_check("stop_at_target: blinks only to the cursor", absf(hero.global_position.x - 150.0) < 6.0, str(hero.global_position))
	_check("self_status on arrival", hero.status_component.has_status(&"test_vanish") and not hero.hurtbox.is_valid_target(), "")
	await _seconds(0.6)
	hero.aim_direction = Vector2.LEFT    # dashes follow the aim unless the feel locks it
	hero.aim_point = Vector2(-900, 2000)
	hero.ability_controller.try_activate(blink, Vector2(-900, 2000))
	await _seconds(0.15)
	# 400 px from x = 150 would end at -250; the wall's face (-236) plus the
	# body radius (50) stops it near -186.
	_check("walls stop it at the last valid point", hero.global_position.x > -200.0 and hero.global_position.x < -170.0,
		str(hero.global_position))
	hero.ability_controller.remove_all()
	_clear()
	await _physics_frames(2)


# --- Helpers ------------------------------------------------------------------

func _dummy(at: Vector2, hp: float = 5000.0) -> TrainingDummy:
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


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
