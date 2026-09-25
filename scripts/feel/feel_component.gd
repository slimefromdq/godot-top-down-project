extends Node
class_name FeelComponent

# Makes a hero's attacks FEEL heavy, using the hero's FeelProfile. It only
# listens: to its hero's cast phases and combat hooks. It never changes
# gameplay; with this node deleted, the game plays identically, it just
# feels flat. That's what keeps it safe for networking: every client can run
# it locally for whatever it sees.
#
#   windup     lean back, squash, glow building    (anticipation)
#   active     snap forward, slash trail + embers,  (release)
#              swing whoosh + fire layer, camera nudge, optional swing shake
#   hit        hitstop on attacker and target, white flash on the target,
#              impact + fire layer, shake if the local player is involved
#   recovery   ease back to rest
#   hurt       shake if this is the local player
#
# The pose is applied to the body sprite only (never the physics body), and
# it pauses while the visuals are frozen by hitstop.

var actor: Actor
var visuals: VisualsComponent

var _pose_tween: Tween
var _body_rest_position := Vector2.ZERO
var _body_rest_scale := Vector2.ONE
var _hooked: Array[Ability] = []
# The last attack that triggered attacker-side feel, so a swing through five
# targets freezes and shakes once, not five times.
var _last_feel_attack_id: int = 0


func _ready() -> void:
	actor = owner as Actor
	if actor == null:
		return
	# Wait one frame: the hero builds its abilities in its own _ready, which
	# runs after this one.
	_connect.call_deferred()


func _connect() -> void:
	visuals = actor.visuals
	if visuals.body != null:
		var body_2d := visuals.body as Node2D
		_body_rest_position = body_2d.position
		_body_rest_scale = body_2d.scale
	actor.ability_controller.abilities_changed.connect(_hook_abilities)
	_hook_abilities()
	var hooks: CombatHooks = actor.get(&"combat_hooks")
	if hooks != null:
		hooks.hit_dealt.connect(_on_hit_dealt)
		hooks.damage_taken.connect(_on_damage_taken)


func get_profile() -> FeelProfile:
	return actor.get(&"feel_profile")


func _process(_delta: float) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.set_speed_scale(visuals.get_time_scale() if visuals != null else 1.0)


func _hook_abilities() -> void:
	for ability in actor.ability_controller.abilities:
		if ability in _hooked:
			continue
		_hooked.append(ability)
		ability.phase_changed.connect(_on_phase_changed.bind(ability))


# --- Cast phases -------------------------------------------------------------

func _on_phase_changed(phase: Ability.Phase, ability: Ability) -> void:
	var feel := ability.current_feel
	if feel == null:
		return
	match phase:
		Ability.Phase.WINDUP:
			_windup_pose(feel, ability.cast_direction)
		Ability.Phase.ACTIVE:
			_release(feel, ability)
		Ability.Phase.RECOVERY:
			_return_to_rest(feel.recovery)
		Ability.Phase.IDLE:
			_return_to_rest(0.08)


func _windup_pose(feel: AttackFeel, direction: Vector2) -> void:
	var body := visuals.body as Node2D
	if body == null:
		return
	var duration := maxf(feel.windup, 0.01)
	_new_pose_tween().set_parallel()
	_pose_tween.tween_property(body, "position", _body_rest_position - direction * feel.windup_lean, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(body, "scale",
		_body_rest_scale * Vector2(1.0 + feel.windup_squash, 1.0 - feel.windup_squash), duration)
	var glow := Color.WHITE.lerp(Color(1.0 + feel.windup_glow.r, 1.0 + feel.windup_glow.g, 1.0 + feel.windup_glow.b),
		feel.windup_glow.a)
	_pose_tween.tween_property(body, "self_modulate", glow, duration)


func _release(feel: AttackFeel, ability: Ability) -> void:
	var direction := ability.cast_direction
	var body := visuals.body as Node2D
	if body != null:
		_new_pose_tween().set_parallel()
		_pose_tween.tween_property(body, "position", _body_rest_position + direction * feel.release_snap, 0.05) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_pose_tween.tween_property(body, "scale",
			_body_rest_scale * Vector2(1.0 - feel.windup_squash * 0.5, 1.0 + feel.windup_squash * 0.5), 0.05)
		_pose_tween.tween_property(body, "self_modulate", Color.WHITE, 0.08)

	var profile := get_profile()
	var shape := _hit_shape_of(ability)
	if profile != null and profile.slash_trail_scene != null and shape != null:
		EffectSpawner.spawn(visuals, profile.slash_trail_scene, {
			"position": Vector2.ZERO,
			"direction": direction,
			"radius": shape.get_reach(),
			"arc_degrees": shape.arc_degrees if shape.kind == HitShape.Kind.ARC else 60.0,
			"step": ability.get(&"_step_index") + 1 if ability.get(&"_step_index") != null else 1,
			"duration": feel.active,
			"color": feel.trail_color,
			"width": feel.trail_width,
			"particles": feel.trail_particles,
			"visuals": visuals,
		}, visuals)

	if profile != null:
		GameFeel.play(profile.get_sound(feel, &"swing_sound"), actor.global_position, feel.pitch_scale, profile.pitch_jitter)
		GameFeel.play(profile.get_sound(feel, &"fire_sound"), actor.global_position, feel.pitch_scale, profile.pitch_jitter)
	if GameFeel.is_local(actor):
		GameFeel.nudge(direction, feel.camera_nudge)
		GameFeel.shake(feel.shake_on_swing)


func _return_to_rest(duration: float) -> void:
	var body := visuals.body as Node2D
	if body == null:
		return
	_new_pose_tween().set_parallel()
	duration = maxf(duration, 0.05)
	_pose_tween.tween_property(body, "position", _body_rest_position, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.tween_property(body, "scale", _body_rest_scale, duration)
	_pose_tween.tween_property(body, "self_modulate", Color.WHITE, duration * 0.5)


func _new_pose_tween() -> Tween:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	_pose_tween = create_tween()
	return _pose_tween


# The shape a swing covers: the current combo step's, else the ability's.
func _hit_shape_of(ability: Ability) -> HitShape:
	if ability is MeleeAttackAbility:
		var step: AttackStep = ability.get_current_step()
		if step != null:
			return step.hit_shape
	return ability.data.hit_shape if ability.data != null else null


# --- Hits ------------------------------------------------------------------

func _on_hit_dealt(info: DamageInfo, target: Node) -> void:
	if info.weight <= 0.0:
		return    # damage over time: no impact feel per tick
	var profile := get_profile()
	if profile == null:
		return
	var feel := info.feel
	if feel == null:
		feel = profile.projectile_feel if profile.projectile_feel != null else profile.fallback
	if feel == null:
		return

	var duration := profile.get_hitstop(feel, info.final_amount)
	var first_hit_of_attack := info.attack_id != _last_feel_attack_id
	_last_feel_attack_id = info.attack_id

	# Target side: every target freezes, flashes and gets an impact sound.
	GameFeel.hitstop([target], duration, profile.hitstop_tremble, profile.hitstop_catch_up)
	GameFeel.flash(target, feel.flash_color, feel.flash_time)
	GameFeel.play(profile.get_sound(feel, &"impact_sound"), info.hit_position, feel.pitch_scale, profile.pitch_jitter)

	# Attacker side: once per attack, however many targets it hits.
	if not first_hit_of_attack:
		return
	if feel.hitstop_attacker:
		GameFeel.hitstop([actor], duration, 0.0, profile.hitstop_catch_up)
	if GameFeel.is_local(actor):
		GameFeel.shake(feel.shake_on_hit)


func _on_damage_taken(info: DamageInfo) -> void:
	if info.weight <= 0.0 or not GameFeel.is_local(actor):
		return
	var profile := get_profile()
	if profile != null:
		GameFeel.shake(profile.hurt_shake * clampf(info.weight, 0.5, 2.0))
