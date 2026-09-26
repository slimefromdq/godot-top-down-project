extends ChargeAbility

# Dinner Is Served: Hunger to full and Starving for the whole duration, then
# the generic dash does the rest: a long bat-swarm flight with an
# untargetable dash_status, a bash that drains (lifesteal) everyone passed.


func _on_active_start() -> void:
	var passive := controller.get_ability_for_slot(&"passive")
	if passive != null and passive.has_method(&"start_starving"):
		passive.start_starving()
	super()
