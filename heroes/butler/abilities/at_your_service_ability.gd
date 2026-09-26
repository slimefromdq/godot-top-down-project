extends ChargeAbility

# At Your Service: an ally-targeted dash (AllyTargeting with `optional`).
# With an ally: dash to them (stop_at_target) and put the data's
# on_hit_status on them (a shield, from Butler's stats). No ally: a short
# dash (values/short_distance) toward the cursor.


func _get_cast_feel() -> AttackFeel:
	var feel := super()
	if cast_ally == null:
		_distance = minf(_distance, data.get_value(&"short_distance", get_stats()))
		feel.active = get_charge_data().get_dash_time(_distance)
	return feel


func _on_active_end() -> void:
	super()
	if is_instance_valid(cast_ally) and data.on_hit_status != null:
		var status := CombatQueries.status_of(cast_ally)
		if status != null:
			status.apply(data.on_hit_status, actor)
			actor.trigger_cue(StringName(str(ability_id) + "_shield"), {"target": cast_ally})
