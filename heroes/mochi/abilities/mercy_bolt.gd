extends RangedAttackAbility

# Mercy: a heavy bolt that hits harder the more health its target is
# missing: damage x (1 + values/missing_health_bonus x missing fraction),
# so +100% on a target at 0 HP. Her tentacle (if out) fires one too.


func _build_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> DamageInfo:
	return scale_by_missing(info, hurtbox)


func scale_by_missing(info: DamageInfo, hurtbox: HurtboxComponent) -> DamageInfo:
	if hurtbox.health_component != null:
		var missing := 1.0 - hurtbox.health_component.get_health_ratio()
		info.amount *= 1.0 + data.get_value(&"missing_health_bonus", get_stats()) * missing
	return info


func _on_active_start() -> void:
	super()
	for deployable in Deployable.find_owned(actor):
		if deployable.has_method(&"mirror"):
			deployable.mirror(self, actor.aim_point)


func on_mirrored_hit(_tentacle: Node, _info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
	pass


func modify_mirrored_hit(info: DamageInfo, hurtbox: HurtboxComponent) -> DamageInfo:
	return scale_by_missing(info, hurtbox)
