extends Ability
class_name MeleeAttackAbility

# Generic melee swing (or combo string) driven by MeleeAttackData.
#
# Each cast is one swing: windup, then the hitbox is live for the active
# frames (hitting each target once), then recovery. Pressing again during the
# cancel window (or holding the key, thanks to the controller's buffer)
# continues the combo; pausing longer than combo_reset_time restarts it.
#
# Cues (on top of the base <id>_windup/_active/_recovery): context.step is the
# 1-based combo step and context.step_count the combo length, so visuals can
# play a different swing per step. "<id>_hit" fires on each target hit.
#
# Subclass hooks: override _build_hit() to change a hit before it lands,
# _on_target_hit() to react after.

var _step_index: int = 0
var _step: AttackStep
var _attack_id: int = 0
var _time_since_swing: float = INF


func get_melee_data() -> MeleeAttackData:
	return data as MeleeAttackData


# Which step the NEXT cast will use (0-based), for HUD/inspector display.
func get_next_step_index() -> int:
	var melee := get_melee_data()
	if melee == null or melee.get_step_count() <= 1:
		return 0
	if _time_since_swing > melee.combo_reset_time:
		return 0
	return _step_index % melee.get_step_count()


func get_current_step() -> AttackStep:
	return _step


func _get_step(index: int) -> AttackStep:
	var melee := get_melee_data()
	if melee != null:
		return melee.get_step(index)
	# Plain AbilityData: one swing from the base fields.
	var step := AttackStep.new()
	step.hit_shape = data.hit_shape
	step.damage = data.damage
	step.knockback = data.knockback
	step.feel_preset = data.feel_preset
	step.feel_override = data.feel_override
	return step


func _get_cast_feel() -> AttackFeel:
	_step_index = get_next_step_index()
	_step = _get_step(_step_index)
	if _step.feel_override != null:
		return _step.feel_override
	return get_feel_preset(_step.feel_preset)


func _activate(_target_position: Vector2) -> String:
	if _step == null or _step.hit_shape == null:
		return "No hit shape"
	var hitbox: Hitbox = actor.get(&"hitbox")
	if hitbox == null:
		return "No Hitbox"
	if not hitbox.hit_landed.is_connected(_on_hitbox_hit):
		hitbox.hit_landed.connect(_on_hitbox_hit)
	return ""


func _cue_context() -> Dictionary:
	var context := super()
	var melee := get_melee_data()
	context["step"] = _step_index + 1
	context["step_count"] = melee.get_step_count() if melee != null else 1
	context["arc_degrees"] = _step.hit_shape.arc_degrees if _step != null and _step.hit_shape != null else 0.0
	context["radius"] = _step.hit_shape.get_reach() if _step != null and _step.hit_shape != null else 0.0
	return context


func _on_active_start() -> void:
	# Take the id first: begin() checks for hits immediately, and
	# _on_hitbox_hit needs to recognise those first-tick hits as ours.
	_attack_id = DamageInfo.new_attack_id()
	actor.hitbox.begin(_step.hit_shape, cast_direction, _make_hit, _attack_id)
	_launch_projectile()


func _on_active_end() -> void:
	if _attack_id != 0 and is_instance_valid(actor):
		actor.hitbox.end(_attack_id)
	_attack_id = 0


func _on_cast_end(interrupted: bool) -> void:
	_time_since_swing = 0.0
	# An interrupted swing restarts the combo; a finished one advances it.
	_step_index = 0 if interrupted else _step_index + 1


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_casting():
		_time_since_swing += delta


func _make_hit(hurtbox: HurtboxComponent) -> DamageInfo:
	var info := DamageInfo.create(
		_step.damage.evaluate(get_stats()) * _damage_multiplier(), actor, data.damage_type)
	info.tags = data.tags.duplicate()
	if not info.tags.has(DamageInfo.TAG_MELEE):
		info.tags.append(DamageInfo.TAG_MELEE)
	info.label = _step.meter_label if _step.meter_label != &"" else data.get_label()
	info.knockback = cast_direction * _step.knockback
	info.direction = cast_direction
	info.weight = current_feel.weight if current_feel != null else 1.0
	info.add_status(data.on_hit_status)
	info.add_status(_step.on_hit_status)
	return _build_hit(info, hurtbox)


# The Hitbox reports every landed hit (after damage applied, so
# final_amount is known). Ours are the ones with our current attack id.
func _on_hitbox_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	if _attack_id == 0 or info.attack_id != _attack_id:
		return
	actor.trigger_cue(StringName(str(ability_id) + "_hit"), {
		"position": hurtbox.global_position,
		"direction": cast_direction,
		"target": hurtbox.owner,
		"weight": info.weight,
		"step": _step_index + 1,
		"damage": info.final_amount,
	})
	_on_target_hit(info, hurtbox)


func _launch_projectile() -> void:
	var melee := get_melee_data()
	if melee == null:
		return
	var projectile := _step.projectile if _step.projectile != null else melee.swing_projectile
	if projectile == null:
		return
	var damage_value := _step.projectile_damage if _step.projectile_damage != null else melee.swing_projectile_damage
	if damage_value == null:
		return
	var template := DamageInfo.create(damage_value.evaluate(get_stats()) * _damage_multiplier(),
		actor, melee.swing_projectile_damage_type)
	template.tags = data.tags.duplicate()
	template.label = melee.swing_projectile_label if melee.swing_projectile_label != &"" \
		else StringName(str(data.get_label()) + "_projectile")
	template.weight = 0.5 * (current_feel.weight if current_feel != null else 1.0)
	var origin := actor.global_position + cast_direction * melee.projectile_spawn_offset
	Projectile.fire(actor, projectile, origin, cast_direction, template)
	actor.trigger_cue(StringName(str(ability_id) + "_projectile"), {"position": origin, "direction": cast_direction})


# Damage buffs from statuses (e.g. a future "+20% damage" buff).
func _damage_multiplier() -> float:
	return StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE)


# Override to change a hit before it lands (or return null to skip it).
func _build_hit(info: DamageInfo, _hurtbox: HurtboxComponent) -> DamageInfo:
	return info


# Override to react after a hit landed (info.final_amount is set).
func _on_target_hit(_info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
	pass
