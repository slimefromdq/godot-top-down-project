extends ChargeAbility

# Cartwheel: the generic dash, plus one rule. If it ends on one of Tilly's
# own trampolines, the pad launches her (JumpPad waits for her footing) and
# the cooldown resets. Cue: <id>_trick.


func _on_active_end() -> void:
	super()
	if not is_instance_valid(actor):
		return
	for node in actor.get_tree().get_nodes_in_group(JumpPad.GROUP):
		var pad := node as JumpPad
		if pad != null and pad.get_owner_actor() == actor and _on_pad(pad):
			reset_cooldown()
			actor.trigger_cue(StringName(str(ability_id) + "_trick"), {"position": pad.global_position})
			return


func _on_pad(pad: JumpPad) -> bool:
	return pad.has_actor_inside(actor) or actor.global_position.distance_to(pad.global_position) <= pad.radius
