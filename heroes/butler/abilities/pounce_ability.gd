extends ChargeAbility

# Pounce: the generic dash, aimed at the enemy nearest the cursor (within
# the data's distance of Butler and values/snap_radius of the cursor); it
# stops at them (stop_at_target). No one there: a plain dash at the cursor.

## The enemy this pounce went for, or null.
var prey: Node2D


func _get_cast_feel() -> AttackFeel:
	prey = _find_prey(cast_target)
	if prey != null:
		cast_target = prey.global_position
		cast_direction = (cast_target - actor.global_position).normalized()
	return super()


func _find_prey(point: Vector2) -> Node2D:
	var snap := data.get_value(&"snap_radius", get_stats())
	var best: Node2D = null
	var best_distance := INF
	for hurtbox in Hitbox.query(actor, actor.global_position, Vector2.RIGHT,
			HitShape.circle(get_charge_data().distance), actor):
		if not hurtbox.is_valid_target():
			continue
		var distance := point.distance_to(hurtbox.global_position)
		if distance <= snap and distance < best_distance:
			best_distance = distance
			best = hurtbox.owner as Node2D if hurtbox.owner != null else hurtbox.get_parent() as Node2D
	return best
