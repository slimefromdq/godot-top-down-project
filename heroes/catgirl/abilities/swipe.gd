extends MeleeAttackAbility

# Swipe: a short claw swipe that steals up to values/steal_count carried
# Motes from each hero it hits, straight into Catgirl's stack
# (MoteCarrier.steal_from: her carry cap applies, the Dream Mote goes last).
# Cue: swipe_steal (context.count, .target).


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	var target := ZoneRamp.target_of(hurtbox)
	var victim := MoteCarrier.find_on(target)
	var mine := MoteCarrier.find_on(actor)
	if victim == null or mine == null:
		return
	var stolen := mine.steal_from(victim, roundi(data.get_value(&"steal_count", get_stats())))
	if stolen > 0:
		actor.trigger_cue(&"swipe_steal", {"position": hurtbox.global_position, "count": stolen, "target": target})
