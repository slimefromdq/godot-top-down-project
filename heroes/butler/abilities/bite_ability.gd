extends MeleeAttackAbility

# Bite: the generic melee lunge (stun on hit, lifesteal on the data), plus
# Hunger: a Bite that lands feeds the passive values/hunger_restored, once
# per cast however many it catches.

var _fed := false


func _on_active_start() -> void:
	_fed = false
	super()


func _on_target_hit(_info: DamageInfo, _hurtbox: HurtboxComponent) -> void:
	if _fed:
		return
	var passive := controller.get_ability_for_slot(&"passive")
	if passive != null and passive.has_method(&"feed"):
		_fed = true
		passive.feed(data.get_value(&"hunger_restored", get_stats()))
