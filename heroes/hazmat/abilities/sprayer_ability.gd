extends RangedAttackAbility

# Sprayer: a generic spray gun, plus one rule. Enemies it hits start their
# Contamination ramp values/ramp_head_start steps higher (never lower than
# where they already are), so walking them into the gas hurts at once.


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var passive := actor.ability_controller.get_ability_for_slot(&"passive")
	if passive == null or not passive.has_method(&"get_ramp_key"):
		return
	var steps := roundi(data.get_value(&"ramp_head_start", get_stats()))
	ZoneRamp.raise_steps(actor, passive.get_ramp_key(), ZoneRamp.target_of(hurtbox), steps)
