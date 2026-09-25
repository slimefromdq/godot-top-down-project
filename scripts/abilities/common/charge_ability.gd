extends Ability
class_name ChargeAbility

# Generic telegraphed charge driven by ChargeData.
#
#   windup    the telegraph: the hero plants (slowed by the feel preset) and a
#             line shows where the charge will go, so opponents can react
#   active    the dash: an exact forced move of `distance` toward the aim,
#             dropping trail zones every `trail_spacing` pixels
#   recovery  from the feel preset
#
# Walls stop the dash (it's a normal forced move), and a stun during the
# telegraph or the dash cancels it.
#
# Hold-to-charge (charge_enabled): the dash length goes from min_distance to
# distance with the charge ratio.
#
# Bash (optional, data): with a hit_shape and damage on the data, enemies
# the hero runs through are hit once each during the dash, for `damage`
# (charged: lerped to values/damage_full) plus on_hit_status (e.g. a
# knockback status). Cue <id>_hit per target.
#
# Cues: <id>_windup carries context.target_position and context.duration for
# the telegraph; <id>_active marks the launch; <id>_end fires on arrival.

var _last_trail_point := Vector2.ZERO
var _dashing := false
# MOVE_INPUT_OR_AIM: the direction chosen when the cast started.
var _move_direction := Vector2.ZERO
# This cast's dash length (charge-dependent).
var _distance: float = 0.0
var _bash_id: int = 0


func get_charge_data() -> ChargeData:
	return data as ChargeData


func is_movement_ability() -> bool:
	return true


func _get_cast_feel() -> AttackFeel:
	# The preset supplies windup, recovery and the telegraph slow; the dash
	# length decides the active time. Work on a copy so the shared preset
	# (used by other abilities) isn't changed.
	var feel: AttackFeel = super().duplicate()
	_distance = get_charge_data().distance
	feel.active = get_charge_data().get_dash_time(_distance)
	feel.lunge_distance = 0.0
	return feel


# The charge decides the length: resize the active phase to match.
func _on_charge_released(ratio: float, _perfect: bool) -> void:
	_distance = get_charge_data().get_distance(ratio)
	current_feel.active = get_charge_data().get_dash_time(_distance)


func get_dash_distance() -> float:
	return _distance


func _activate(_target_position: Vector2) -> String:
	var charge := get_charge_data()
	if charge == null:
		return "No charge data"
	_move_direction = Vector2.ZERO
	if charge.direction_mode == ChargeData.DirectionMode.MOVE_INPUT_OR_AIM:
		_move_direction = actor.move_direction.normalized() if actor.move_direction != Vector2.ZERO \
			else cast_direction
		cast_direction = _move_direction
	return ""


# The dash direction: the aim (which may follow the mouse during the
# telegraph), or the walking direction fixed at cast start.
func get_dash_direction() -> Vector2:
	return _move_direction if _move_direction != Vector2.ZERO else cast_direction


func _cue_context() -> Dictionary:
	var context := super()
	var charge := get_charge_data()
	context["target_position"] = actor.global_position + get_dash_direction() * _distance
	context["direction"] = get_dash_direction()
	context["distance"] = _distance
	context["distance"] = _distance
	return context


func _on_active_start() -> void:
	var charge := get_charge_data()
	_dashing = true
	actor.movement_component.displace(get_dash_direction(), _distance, charge.get_dash_time(_distance), charge.carry_momentum)
	if charge.invulnerable_duration > 0.0:
		actor.health_component.set_invulnerable_for(charge.invulnerable_duration)
	elif charge.invulnerable_while_dashing:
		actor.health_component.set_invulnerable_for(charge.get_dash_time(_distance))
	_start_bash()
	_last_trail_point = actor.global_position
	_drop_trail(_last_trail_point)


func _on_active_tick(_delta: float) -> void:
	var charge := get_charge_data()
	if charge.trail_zone == null:
		return
	# Fill in every spacing step we passed this tick, so fast dashes leave an
	# unbroken trail.
	var to_here := actor.global_position - _last_trail_point
	while to_here.length() >= charge.trail_spacing:
		_last_trail_point += to_here.normalized() * charge.trail_spacing
		_drop_trail(_last_trail_point)
		to_here = actor.global_position - _last_trail_point


func _on_active_end() -> void:
	_end_bash()
	if _dashing and is_instance_valid(actor):
		actor.trigger_cue(StringName(str(ability_id) + "_end"), {"direction": get_dash_direction()})


func _on_recovery_start() -> void:
	_dashing = false


func _start_bash() -> void:
	if data.hit_shape == null or data.damage == null:
		return
	var hitbox: Hitbox = actor.get(&"hitbox")
	if hitbox == null:
		return
	if not hitbox.hit_landed.is_connected(_on_bash_landed):
		hitbox.hit_landed.connect(_on_bash_landed)
	_bash_id = DamageInfo.new_attack_id()
	hitbox.begin(data.hit_shape, get_dash_direction(), _make_bash, _bash_id)


func _end_bash() -> void:
	if _bash_id != 0 and is_instance_valid(actor):
		actor.hitbox.end(_bash_id)
	_bash_id = 0


func _make_bash(_hurtbox: HurtboxComponent) -> DamageInfo:
	var amount := data.get_charged_value(&"damage", get_stats(), get_charge_ratio()) if uses_charge() \
		else data.damage.evaluate(get_stats())
	amount *= StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE)
	var info := DamageInfo.create(amount, actor, data.damage_type)
	info.tags = data.tags.duplicate()
	info.label = data.get_label()
	info.direction = get_dash_direction()
	info.knockback = get_dash_direction() * data.knockback
	info.weight = current_feel.weight if current_feel != null else 1.0
	info.add_status(data.on_hit_status)
	return info


func _on_bash_landed(info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	if _bash_id == 0 or info.attack_id != _bash_id:
		return
	actor.trigger_cue(StringName(str(ability_id) + "_hit"), {
		"position": hurtbox.global_position, "target": hurtbox.owner, "direction": info.direction})


func _on_cast_end(interrupted: bool) -> void:
	_end_bash()
	# A stun mid-dash stops the body where it is.
	if interrupted and _dashing and is_instance_valid(actor):
		actor.movement_component.stop_forced_move()
	_dashing = false


func _drop_trail(point: Vector2) -> void:
	var charge := get_charge_data()
	if charge.trail_zone != null:
		GroundZone.spawn(actor, charge.trail_zone, point, get_dash_direction(), actor)
