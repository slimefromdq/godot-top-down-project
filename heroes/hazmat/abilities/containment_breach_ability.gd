extends Ability

# Containment Breach: the data is a ZoneAbilityData. On cast, the passive
# aura is suspended and the breach zone takes its place for zone_duration:
# bigger, following Hazmat, at full ramp at once (ramp_starts_full). The
# zone outlives the cast (he keeps fighting) and leaves its leaves_zone
# residue where it ends. Cues: <id>_zone_start, and the zone's own look.

## The live breach zone, else null.
var zone: GroundZone


func get_zone_data() -> ZoneAbilityData:
	return data as ZoneAbilityData


func _activate(_target_position: Vector2) -> String:
	var zone_data := get_zone_data()
	return "No zone" if zone_data == null or zone_data.zone == null else ""


func _on_active_start() -> void:
	var zone_data := get_zone_data()
	var passive := actor.ability_controller.get_ability_for_slot(&"passive")
	if passive != null and passive.has_method(&"suspend"):
		passive.suspend(zone_data.zone_duration)
	zone = spawn_owned_zone(zone_data.zone, actor.global_position, cast_direction, zone_data.zone_duration)
	actor.trigger_cue(StringName(str(ability_id) + "_zone_start"),
		{"direction": cast_direction, "zone_duration": zone_data.zone_duration})
