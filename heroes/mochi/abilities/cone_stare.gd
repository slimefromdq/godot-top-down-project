extends MeleeAttackAbility

# Cone Stare: the generic melee cone (telegraphed windup, stun on hit; a stun
# or death during the windup cancels it) plus MochiGazeData.shred_status on
# everyone caught.


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var gaze := data as MochiGazeData
	if gaze != null and gaze.shred_status != null and hurtbox.status_component != null \
			and hurtbox.is_valid_target():
		hurtbox.status_component.apply(gaze.shred_status, actor)
