@tool
extends AbilityData
class_name ZoneAbilityData

# Data for ZoneAbility: channel a GroundZone for a while. With follow_owner,
# face_aim and an ARC shape on the zone, that's a persistent cone in front of
# the hero (a flamethrower, a song, a swarm); with a CIRCLE and follow_owner,
# an aura. The zone is owned by the cast: interrupting the cast (a stun) ends
# it, unless the zone data sets outlives_cast.

@export_group("Zone")
@export var zone: GroundZoneData
## Seconds the zone is channelled (the cast's ACTIVE phase). The feel preset
## supplies the windup and recovery around it.
@export var zone_duration: float = 3.0
## Pixels ahead of the hero (along the aim) where the zone is placed. Ignored
## while the zone follows its owner.
@export var spawn_offset: float = 0.0


func get_range() -> float:
	if ability_range > 0.0:
		return ability_range
	return zone.shape.get_reach() + spawn_offset if zone != null and zone.shape != null else 0.0


func get_scaling_values() -> Dictionary:
	var result := super()
	if zone != null and zone.tick_damage != null:
		result["zone/tick_damage"] = zone.tick_damage
	return result


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"zone_duration": zone_duration}


func validate() -> PackedStringArray:
	var problems := super()
	if zone == null:
		problems.append("'%s' has no zone" % id)
	else:
		for problem in zone.validate():
			problems.append("'%s' %s" % [id, problem])
	if zone_duration <= 0.0 or spawn_offset < 0.0:
		problems.append("'%s' zone_duration must be above 0 and spawn_offset >= 0" % id)
	return problems
