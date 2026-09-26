extends Ability

# Only Us: a ContainmentRing (values/ring_radius, values/ring_duration) closes
# around Pike and her Beloved, centred between them. Needs a Beloved within
# values/max_distance. Cue: <id>_ring (context.position, radius).

## The last ring made (may have ended).
var ring: ContainmentRing


func _activate(_target_position: Vector2) -> String:
	var beloved := _beloved()
	if beloved == null:
		return "No Beloved"
	if actor.global_position.distance_to(beloved.global_position) > data.get_value(&"max_distance", get_stats()):
		return "Too far"
	return ""


func _on_active_start() -> void:
	var beloved := _beloved()
	if beloved == null:
		return
	var center := (actor.global_position + beloved.global_position) / 2.0
	var radius := data.get_value(&"ring_radius", get_stats())
	ring = ContainmentRing.spawn(actor, center, radius, data.get_value(&"ring_duration", get_stats()),
		[actor, beloved], Color(1.0, 0.45, 0.7, 0.9))
	actor.trigger_cue(StringName(str(ability_id) + "_ring"), {"position": center, "radius": radius})


func _beloved() -> Node2D:
	var beloved := controller.get_ability_for_slot(&"ability_1")
	return beloved.get_beloved() if beloved != null and beloved.has_method(&"get_beloved") else null
