extends Ability

# Overcast: the data is a ZoneAbilityData. Places its zone (a raincloud) on
# the cursor, anywhere within ability_range, for zone_duration. Instant: the
# cloud outlives the cast. The zone's status_while_inside (reveal + slow) is
# also what the rifle checks for its crits.

## The last cloud placed (may have ended).
var cloud: GroundZone


func get_zone_data() -> ZoneAbilityData:
	return data as ZoneAbilityData


func _activate(_target_position: Vector2) -> String:
	var zone_data := get_zone_data()
	return "No zone" if zone_data == null or zone_data.zone == null else ""


func _on_active_start() -> void:
	var zone_data := get_zone_data()
	var at := actor.global_position + (cast_target - actor.global_position).limit_length(zone_data.get_range())
	cloud = GroundZone.spawn(actor, zone_data.zone, at, cast_direction, actor, zone_data.zone_duration)
	actor.trigger_cue(StringName(str(ability_id) + "_zone_start"),
		{"target_position": at, "zone_duration": zone_data.zone_duration})
