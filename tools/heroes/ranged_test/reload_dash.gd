extends ChargeAbility

# Test hero only: a dash that refills the hero's gun on use, the pattern a
# future movement ability will follow. Shows the cross-ability hook:
# Hero.get_ranged_ability() finds the gun, reload_instantly() fills it.


func _on_active_start() -> void:
	super()
	var hero := actor as Hero
	var gun := hero.get_ranged_ability(&"") if hero != null else null
	if gun != null:
		gun.reload_instantly()
