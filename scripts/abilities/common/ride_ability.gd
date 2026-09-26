extends Ability
class_name RideAbility

# Generic hold-to-ride driven by RideData (see there for the phases). The
# ride itself is MovementComponent.set_cruise, re-steered every tick, so
# stuns and roots stop it like any movement.
#
# Cues: <id>_charge_start (the ride begins; context.charge_ability rides
# along so a live effect can follow it), <id>_charge_release (the ride
# ends), <id>_windup (the landing telegraph: context.radius, .duration),
# <id>_active (the burst: context.radius), <id>_hit per target.

var _riding := false
var _heading := Vector2.RIGHT


func get_ride_data() -> RideData:
	return data as RideData


func is_movement_ability() -> bool:
	return true


func is_riding() -> bool:
	return _riding


func get_heading() -> Vector2:
	return _heading


func _activate(_target_position: Vector2) -> String:
	if get_ride_data() == null or data.hit_shape == null:
		return "No ride data"
	return ""


func _get_cast_feel() -> AttackFeel:
	# Copy: the preset is shared. The telegraph length is the data's.
	var feel: AttackFeel = super().duplicate()
	feel.windup = get_ride_data().landing_telegraph
	feel.lunge_distance = 0.0
	return feel


func _on_charge_start() -> void:
	var ride := get_ride_data()
	_riding = true
	_heading = actor.aim_direction if actor.aim_direction != Vector2.ZERO else Vector2.RIGHT
	if ride.steer_mode == RideData.SteerMode.MOVE_INPUT and actor.move_direction != Vector2.ZERO:
		_heading = actor.move_direction.normalized()
	if ride.ride_status != null:
		actor.status_component.apply(ride.ride_status, actor)
	_cruise()


func _physics_process(delta: float) -> void:
	super(delta)
	if _riding and phase == Phase.CHARGING:
		_steer(delta)
		_cruise()


func _steer(delta: float) -> void:
	var ride := get_ride_data()
	var wanted := _heading
	match ride.steer_mode:
		RideData.SteerMode.MOVE_INPUT:
			if actor.move_direction != Vector2.ZERO:
				wanted = actor.move_direction.normalized()
		RideData.SteerMode.AIM:
			var to_aim := actor.aim_point - actor.global_position
			if to_aim.length() > 1.0:
				wanted = to_aim.normalized()
	if ride.turn_rate_degrees <= 0.0:
		_heading = wanted
		return
	var max_turn := deg_to_rad(ride.turn_rate_degrees) * delta
	_heading = _heading.rotated(clampf(_heading.angle_to(wanted), -max_turn, max_turn))


func _cruise() -> void:
	var ride := get_ride_data()
	actor.movement_component.set_cruise(self, _heading, ride.ride_speed, ride.ride_acceleration)


func _on_charge_released(_ratio: float, _perfect: bool) -> void:
	_stop_riding()
	# The landing faces the way the ride was going.
	cast_direction = _heading


func _stop_riding() -> void:
	if not _riding:
		return
	_riding = false
	if is_instance_valid(actor):
		actor.movement_component.clear_cruise(self)
		var ride := get_ride_data()
		if ride.ride_status != null:
			actor.status_component.remove_from(ride.ride_status.id, actor)


func _on_active_start() -> void:
	var hitbox: Hitbox = actor.get(&"hitbox")
	if hitbox == null:
		return
	var id := DamageInfo.new_attack_id()
	for hurtbox in hitbox.sweep(data.hit_shape, cast_direction, _make_burst, id):
		actor.trigger_cue(StringName(str(ability_id) + "_hit"), {
			"position": hurtbox.global_position, "target": hurtbox.owner,
			"direction": (hurtbox.global_position - actor.global_position).normalized()})


func _make_burst(hurtbox: HurtboxComponent) -> DamageInfo:
	var amount := data.damage.evaluate(get_stats()) \
		* StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE)
	var info := DamageInfo.create(amount, actor, data.damage_type)
	info.tags = data.tags.duplicate()
	info.label = data.get_label()
	# Outward from the hero, so an ALONG_HIT knockback pushes away too.
	var away := hurtbox.global_position - actor.global_position
	info.direction = away.normalized() if away != Vector2.ZERO else cast_direction
	info.knockback = info.direction * data.knockback
	info.weight = current_feel.weight if current_feel != null else 1.0
	info.add_status(data.on_hit_status)
	return info


func _on_cast_end(interrupted: bool) -> void:
	var was_riding := _riding
	_stop_riding()
	# Cut short while riding (stun, death, cancel): the ride still costs its
	# cooldown, it just doesn't land.
	if interrupted and was_riding:
		_spend_cooldown()


func _cue_context() -> Dictionary:
	var context := super()
	context["radius"] = data.hit_shape.get_reach() if data.hit_shape != null else 0.0
	if _riding:
		context["direction"] = _heading
	return context


func _exit_tree() -> void:
	_stop_riding()
	super()
