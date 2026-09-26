extends RangedAttackAbility

# Beloved: a one-shot heart whose on_hit_status is the Beloved mark
# (stack_per_applier, ends_if_applier_dies). The enemy hit becomes her
# Beloved; the previous one loses her mark. The rest of her kit asks
# get_beloved(). Cue: <id>_chosen (context.target).

var _beloved: Node2D


func get_beloved() -> Node2D:
	if _beloved == null or StatusEffectComponent.is_actor_gone(_beloved):
		return null
	var status := CombatQueries.status_of(_beloved)
	var mark := data.on_hit_status
	if status == null or mark == null or not status.has_status_from(mark.id, actor):
		return null
	return _beloved


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var target := ZoneRamp.target_of(hurtbox) as Node2D
	if target == null or target == _beloved:
		return
	var old := get_beloved()
	if old != null and data.on_hit_status != null:
		CombatQueries.status_of(old).remove_from(data.on_hit_status.id, actor)
	_beloved = target
	actor.trigger_cue(StringName(str(ability_id) + "_chosen"), {"target": target})
