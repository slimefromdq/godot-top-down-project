extends RangedAttackAbility

# Friendship Bracelet: a projectile that stops on the first actor of either
# team (ProjectileData.affects BOTH), then chains to the nearest other actor
# on THAT actor's team within values/chain_range and links the two
# (ActorLink) for values/link_duration: enemies get a leash
# (values/leash_distance), allies a healing share (values/heal_share).
# Cue: <id>_link (context.target, target_position).

## The last link made (may have ended).
var link: ActorLink


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	_chain(ZoneRamp.target_of(hurtbox) as Node2D, false)


func _on_ally_hit(hurtbox: HurtboxComponent) -> void:
	_chain(ZoneRamp.target_of(hurtbox) as Node2D, true)


func _chain(first: Node2D, allies: bool) -> void:
	if first == null:
		return
	var second := _nearest_teammate(first, data.get_value(&"chain_range", get_stats()))
	if second == null:
		actor.trigger_cue(StringName(str(ability_id) + "_fizzle"), {"target": first})
		return
	var duration := data.get_value(&"link_duration", get_stats())
	if allies:
		link = ActorLink.spawn(actor, first, second, duration, actor, 0.0, data.get_value(&"heal_share", get_stats()), data.on_hit_status)
	else:
		link = ActorLink.spawn(actor, first, second, duration, actor, data.get_value(&"leash_distance", get_stats()), 0.0, data.on_hit_status)
	link.color = Color(0.7, 1.0, 0.85, 0.9) if allies else Color(1.0, 0.6, 0.85, 0.9)
	actor.trigger_cue(StringName(str(ability_id) + "_link"), {"target": first, "target_position": second.global_position})


func _nearest_teammate(first: Node2D, reach: float) -> Node2D:
	var team := CombatQueries.team_of(first)
	var best: Node2D = null
	var best_distance := reach
	for node in actor.get_tree().get_nodes_in_group(&"minimap_units"):
		var other := node as Node2D
		if other == null or other == first or other == actor or StatusEffectComponent.is_actor_gone(other):
			continue
		if CombatQueries.team_of(other) != team:
			continue
		var distance := first.global_position.distance_to(other.global_position)
		if distance <= best_distance:
			best = other
			best_distance = distance
	return best
