@tool
extends AbilityData
class_name ChargeData

# Data for ChargeAbility: a telegraphed dash/leap toward the aim, optionally
# leaving a trail of GroundZones behind it.
#
# Timing: the windup (the telegraph) and recovery come from the feel preset
# like any other ability; the dash itself lasts distance / speed.

@export_group("Charge")
@export var distance: float = 400.0
## Pixels per second while charging.
@export var speed: float = 1600.0
## Take no damage while dashing (not during the telegraph).
@export var invulnerable_while_dashing: bool = false
## Keep running speed after the dash (fluid) instead of stopping dead.
@export var carry_momentum: bool = true

@export_group("Trail")
## Zone dropped along the path. Empty = no trail.
@export var trail_zone: GroundZoneData
## Pixels between trail zones.
@export var trail_spacing: float = 60.0


func get_dash_time() -> float:
	return distance / speed if speed > 0.0 else 0.0


func get_scaling_values() -> Dictionary:
	var result := super()
	if trail_zone != null and trail_zone.tick_damage != null:
		result["trail_zone/tick_damage"] = trail_zone.tick_damage
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if distance <= 0.0 or speed <= 0.0:
		problems.append("'%s' distance and speed must be above 0" % id)
	if trail_zone != null:
		if trail_zone.shape == null:
			problems.append("'%s' trail_zone has no shape" % id)
		if trail_zone.has_negative() or trail_spacing <= 0.0:
			problems.append("'%s' trail has negative/zero values" % id)
	return problems
