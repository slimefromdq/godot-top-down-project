extends ChargeAbility

# Tractor Beam: pick an ally or an enemy near the cursor (AllyTargeting with
# accepts BOTH, optional), then fly the data's distance along the aim with
# them in tow: an enemy gets enemy_status (carried, stunned), an ally gets
# ally_status (carried, untargetable). Released on arrival. No target: a short
# hover-dash (values/short_distance). Cue: <id>_lift (context.target).

var _lifted: Node2D


func get_tractor_data() -> SamTractorData:
	return data as SamTractorData


func _get_cast_feel() -> AttackFeel:
	# Fly along the aim, whoever was picked (AllyTargeting points the cast at
	# them, but the beam carries them where Sam is going).
	var aim := actor.aim_direction if actor.aim_direction != Vector2.ZERO else Vector2.RIGHT
	cast_direction = aim.normalized()
	cast_target = actor.global_position + cast_direction * get_charge_data().distance
	var feel := super()
	if cast_ally == null:
		_distance = minf(_distance, data.get_value(&"short_distance", get_stats()))
		feel.active = get_charge_data().get_dash_time(_distance)
	return feel


func _on_active_start() -> void:
	_lifted = cast_ally if is_instance_valid(cast_ally) else null
	if _lifted != null:
		var status := CombatQueries.status_of(_lifted)
		var effect := get_tractor_data().ally_status if is_cast_target_ally() else get_tractor_data().enemy_status
		if status != null and effect != null:
			status.apply(effect, actor)
		actor.trigger_cue(StringName(str(ability_id) + "_lift"), {"target": _lifted})
	super()


func _on_active_end() -> void:
	super()
	_drop()


func _on_cast_end(interrupted: bool) -> void:
	super(interrupted)
	_drop()


func _drop() -> void:
	if not is_instance_valid(_lifted):
		_lifted = null
		return
	var status := CombatQueries.status_of(_lifted)
	if status != null:
		for effect in [get_tractor_data().ally_status, get_tractor_data().enemy_status]:
			if effect != null:
				status.remove_from(effect.id, actor)
	_lifted = null
