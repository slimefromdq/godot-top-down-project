extends Ability
class_name PlaceBarrierAbility

# Generic "place a shield wall" driven by PlaceBarrierData: on the active
# phase, a PlacedBarrier goes down at the cursor (clamped to place_range)
# facing away from the caster. One per ability: a new one replaces the old.
# Cue: <id>_placed (context.position, .direction).

var barrier: PlacedBarrier


func get_barrier_data() -> PlaceBarrierData:
	return data as PlaceBarrierData


func _on_active_start() -> void:
	var d := get_barrier_data()
	var offset := (cast_target - actor.global_position).limit_length(d.place_range)
	if offset.length() < d.barrier_radius:
		offset = cast_direction * d.barrier_radius
	var at := actor.global_position + offset
	if is_instance_valid(barrier):
		barrier.end()
	# The arc's centre sits behind the wall so its curve bulges toward the enemy.
	barrier = PlacedBarrier.place(actor, at - cast_direction * d.barrier_radius, cast_direction, {
		"radius": d.barrier_radius, "arc_degrees": d.arc_degrees, "max_charges": d.charges,
		"recharge_time": d.recharge_time, "lifetime": d.lifetime, "color": d.color})
	actor.trigger_cue(StringName(str(ability_id) + "_placed"), {"position": at, "direction": cast_direction})
