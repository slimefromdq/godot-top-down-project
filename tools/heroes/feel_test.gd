extends Node2D

# Headless checks for game feel. The important one: hitstop is purely
# cosmetic. While sprites are frozen, the simulation (physics, knockback,
# cooldowns) must keep running.
#
#   godot --headless res://tools/heroes/feel_test.tscn

const AVERY := "res://heroes/avery/avery.tscn"
const DUMMY := "res://scenes/training_dummy.tscn"

var failures := 0
var avery: Hero
var camera: ShakeCamera


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	avery = load(AVERY).instantiate()
	avery.team = &"a"
	add_child(avery)
	# Act as the local player (camera + "player" group) without real input.
	avery.add_to_group(&"player")
	camera = ShakeCamera.new()
	avery.add_child(camera)
	camera.make_current()
	await _physics_frames(3)

	await _test_hitstop_is_cosmetic()
	await _test_hitstop_scales()
	await _test_pose_trail_and_nudge()
	await _test_shake_and_settings()
	await _test_flash_setting()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_hitstop_is_cosmetic() -> void:
	var dummy := _dummy(Vector2(130, 0))
	await _physics_frames(2)
	var searing := avery.get_ability(&"ability_1")
	searing.cooldown_remaining = 5.0
	var hit_frame := [false]
	var frozen_seen := [false]
	var moved_while_frozen := [false]
	var cooldown_ticked := [false]
	var on_hit := func(_info, _target): hit_frame[0] = true
	avery.combat_hooks.hit_dealt.connect(on_hit)
	# Use the finisher (biggest knockback + hitstop).
	var primary := avery.get_ability(&"primary") as MeleeAttackAbility
	primary._step_index = 2
	primary._time_since_swing = 0.0
	avery.request_slot(&"primary", dummy.global_position)
	while not hit_frame[0]:
		await get_tree().physics_frame
	var dummy_visuals := dummy.visuals
	var x0 := dummy.global_position.x
	var cd0 := searing.cooldown_remaining
	for i in 4:
		await get_tree().physics_frame
		if dummy_visuals.is_frozen():
			frozen_seen[0] = true
			if dummy.global_position.x > x0 + 1.0:
				moved_while_frozen[0] = true
			if searing.cooldown_remaining < cd0:
				cooldown_ticked[0] = true
	avery.combat_hooks.hit_dealt.disconnect(on_hit)
	_check("target visuals freeze on hit", frozen_seen[0], "")
	_check("attacker visuals freeze too (melee)", avery.visuals.is_frozen() or frozen_seen[0], "")
	_check("time scale untouched", is_equal_approx(Engine.time_scale, 1.0), "")
	_check("tree never paused", not get_tree().paused, "")
	_check("knockback keeps simulating during hitstop", moved_while_frozen[0], "")
	_check("cooldowns keep ticking during hitstop", cooldown_ticked[0], "")
	await _seconds(0.4)
	_check("frozen sprite catches back up to its body",
		not dummy_visuals.is_frozen() and dummy_visuals.position.length() < 0.5,
		"offset %.2f" % dummy_visuals.position.length())
	dummy.queue_free()
	avery.ability_controller.interrupt()
	await _seconds(0.5)


func _test_hitstop_scales() -> void:
	var profile := avery.feel_profile
	var light := profile.get_hitstop(profile.get_preset(&"light"), 58.0)
	var finisher := profile.get_hitstop(profile.get_preset(&"finisher"), 93.0)
	var huge := profile.get_hitstop(profile.get_preset(&"finisher"), 5000.0)
	_check("light hitstop in the 40-90 ms band", light >= 0.04 and light <= 0.09, "%.3f" % light)
	_check("finisher stops longer", finisher > light, "%.3f vs %.3f" % [finisher, light])
	_check("hitstop is capped", is_equal_approx(huge, profile.hitstop_max), "%.3f" % huge)


func _test_pose_trail_and_nudge() -> void:
	GameFeel.settings.shake_intensity = 0.0    # isolate the nudge
	avery.global_position = Vector2.ZERO
	var body := avery.visuals.body as Node2D
	var rest := body.position
	var primary := avery.get_ability(&"primary") as MeleeAttackAbility
	primary._step_index = 2
	primary._time_since_swing = 0.0
	avery.request_slot(&"primary", Vector2(500, 0))
	await _seconds(0.15)
	_check("windup leans back away from the aim", body.position.x < rest.x - 2.0, "x=%.1f" % (body.position.x - rest.x))
	while primary.phase != Ability.Phase.ACTIVE:
		await get_tree().physics_frame
	await get_tree().process_frame
	var trails := avery.visuals.find_children("*", "SlashTrail", false, false)
	_check("slash trail spawned on release", trails.size() > 0, "")
	await get_tree().process_frame
	_check("camera nudges toward the swing", camera.offset.x > 1.0, "offset %s" % camera.offset)
	await _seconds(0.8)
	_check("pose returns to rest", body.position.distance_to(rest) < 1.0, "")
	_check("nudge eases back", camera.offset.length() < 1.0, "offset %s" % camera.offset)
	GameFeel.settings.shake_intensity = 1.0


func _test_shake_and_settings() -> void:
	var dummy := _dummy(Vector2(130, 0))
	await _physics_frames(2)
	avery.global_position = Vector2.ZERO
	await _seconds(0.5)    # let earlier trauma decay
	# FeelComponent connected to hit_dealt first, so by the time this runs
	# the hit's shake has been added.
	var at_impact := [0.0]
	var on_hit := func(_info, _target): at_impact[0] = maxf(at_impact[0], camera.get_trauma())
	avery.combat_hooks.hit_dealt.connect(on_hit)
	avery.request_slot(&"primary", dummy.global_position)
	await _seconds(0.25)
	avery.combat_hooks.hit_dealt.disconnect(on_hit)
	_check("hitting as the local player adds trauma", at_impact[0] >= 0.2, "%.2f" % at_impact[0])
	for i in 6:
		camera.add_trauma(1.0)
	_check("trauma is capped by settings", camera.get_trauma() <= GameFeel.settings.max_trauma + 0.001, "")
	GameFeel.settings.shake_intensity = 0.0
	GameFeel.settings.camera_nudge_scale = 0.0
	await _seconds(0.6)
	camera.add_trauma(0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("shake intensity 0 = no shake", camera.offset.length() < 0.01, "offset %s" % camera.offset)
	GameFeel.settings.shake_intensity = 1.0
	GameFeel.settings.camera_nudge_scale = 1.0

	# A hit that doesn't involve the local player never shakes the screen.
	await _seconds(1.0)
	var other := _dummy(Vector2(-600, 400))
	var bystander: Hero = load(AVERY).instantiate()
	bystander.team = &"b"
	add_child(bystander)
	bystander.global_position = Vector2(-730, 400)
	await _physics_frames(2)
	var before := camera.get_trauma()
	bystander.request_slot(&"primary", other.global_position)
	await _seconds(0.25)
	_check("other heroes' hits don't shake your camera", camera.get_trauma() <= before + 0.001,
		"%.2f -> %.2f" % [before, camera.get_trauma()])
	bystander.queue_free()
	other.queue_free()
	dummy.queue_free()
	await _seconds(0.5)


func _test_flash_setting() -> void:
	var dummy := _dummy(Vector2(130, 0))
	await _physics_frames(2)
	GameFeel.settings.flash_enabled = false
	dummy.visuals.flash(Color.WHITE, 0.2)
	var mat := dummy.visuals.body.material as ShaderMaterial
	var amount = mat.get_shader_parameter(&"flash_amount") if mat != null else null
	_check("flash can be disabled", amount == null or amount < 0.01, "")
	GameFeel.settings.flash_enabled = true
	GameFeel.flash(dummy, Color.WHITE, 0.2)
	amount = mat.get_shader_parameter(&"flash_amount") if mat != null else null
	_check("hit flash drives the white-flash shader", amount != null and amount > 0.5, "")
	dummy.queue_free()


# --- Helpers ------------------------------------------------------------------

func _dummy(at: Vector2) -> TrainingDummy:
	var d: TrainingDummy = load(DUMMY).instantiate()
	d.position = at
	d.reset_delay = 999.0
	d.can_die = false
	d.max_health = 5000.0
	add_child(d)
	return d


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
