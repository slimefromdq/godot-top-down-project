extends ChargeAbility

# Flourish: Jose's flip. The roll itself is the generic ChargeAbility driven
# by flourish.tres (direction_mode MOVE_INPUT_OR_AIM, invulnerable_duration,
# distance, speed). This script only adds the payoff: the moment the flip
# starts, his gun is reloaded, with a "<id>_reload" cue (flourish_reload)
# for the spin and the cylinder click. The HUD shows the ammo refill through
# the gun's own ammo_changed signal.


func _on_active_start() -> void:
	super()
	var hero := actor as Hero
	var gun := hero.get_reload_ability() if hero != null else null
	if gun != null:
		gun.reload_instantly()
	actor.trigger_cue(StringName(str(ability_id) + "_reload"), {
		"direction": get_dash_direction(),
		"ammo": gun.get_ammo() if gun != null else 0,
	})
