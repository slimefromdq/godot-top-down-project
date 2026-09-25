extends Ability
class_name ZoneAbility

# Generic "channel a zone" ability driven by ZoneAbilityData.
#
#   windup    from the feel preset
#   active    the zone lives for zone_duration (spawned with
#             spawn_owned_zone, so it ends with the cast)
#   recovery  from the feel preset
#
# Per-target logic without a new zone class: override the hooks below, which
# are wired to the zone's target_entered / target_ticked / target_exited.
# Cues: <id>_zone_start (context.zone_duration), <id>_zone_end.

## The live zone during ACTIVE, else null.
var zone: GroundZone


func get_zone_data() -> ZoneAbilityData:
	return data as ZoneAbilityData


func _get_cast_feel() -> AttackFeel:
	# Copy: the preset is shared with other abilities.
	var feel: AttackFeel = super().duplicate()
	feel.active = get_zone_data().zone_duration
	feel.lunge_distance = 0.0
	return feel


func _activate(_target_position: Vector2) -> String:
	var zone_data := get_zone_data()
	if zone_data == null or zone_data.zone == null:
		return "No zone"
	return ""


func _on_active_start() -> void:
	var zone_data := get_zone_data()
	var at := actor.global_position + cast_direction * zone_data.spawn_offset
	zone = spawn_owned_zone(zone_data.zone, at, cast_direction, zone_data.zone_duration)
	zone.target_entered.connect(_on_zone_target_entered)
	zone.target_ticked.connect(_on_zone_target_ticked)
	zone.target_exited.connect(_on_zone_target_exited)
	actor.trigger_cue(StringName(str(ability_id) + "_zone_start"),
		{"direction": cast_direction, "zone_duration": zone_data.zone_duration})


func _on_active_end() -> void:
	if is_instance_valid(zone):
		end_owned_zones()
		if is_instance_valid(actor):
			actor.trigger_cue(StringName(str(ability_id) + "_zone_end"), {"direction": cast_direction})
	zone = null


# Per-target hooks. All optional.
func _on_zone_target_entered(_hurtbox: HurtboxComponent) -> void: pass
func _on_zone_target_ticked(_hurtbox: HurtboxComponent) -> void: pass
func _on_zone_target_exited(_hurtbox: HurtboxComponent) -> void: pass
