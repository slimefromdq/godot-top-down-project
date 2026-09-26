extends RangedAttackAbility

# Don't Go: the generic one-shot knife with a root on_hit_status; on her
# Beloved the root lasts values/beloved_root_duration instead.


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var beloved_ability := controller.get_ability_for_slot(&"ability_1")
	if beloved_ability == null or not beloved_ability.has_method(&"get_beloved"):
		return
	if ZoneRamp.target_of(hurtbox) == beloved_ability.get_beloved() and hurtbox.status_component != null:
		hurtbox.status_component.apply(data.on_hit_status, actor, cast_direction, 1.0,
			data.get_value(&"beloved_root_duration", get_stats()))
