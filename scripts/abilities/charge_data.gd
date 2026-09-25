@tool
extends AbilityData
class_name ChargeData

# Data for ChargeAbility: a telegraphed dash/leap toward the aim, optionally
# leaving a trail of GroundZones behind it.
#
# Timing: the windup (the telegraph) and recovery come from the feel preset
# like any other ability; the dash itself lasts distance / speed.

## Which way the dash goes.
enum DirectionMode {
	AIM,                ## Toward the aim (a telegraphed charge).
	MOVE_INPUT_OR_AIM,  ## The way the hero is walking; the aim if standing still (a roll).
}

@export_group("Charge")
@export var direction_mode: DirectionMode = DirectionMode.AIM
@export var distance: float = 400.0
## charge_enabled only: the distance at zero charge; `distance` is reached at
## full charge (a wind-up dash that goes further the longer you hold).
@export var min_distance: float = 0.0
## Pixels per second while charging.
@export var speed: float = 1600.0
## Take no damage while dashing (not during the telegraph).
@export var invulnerable_while_dashing: bool = false
## Seconds of immunity from the moment the dash starts. Above 0 it replaces
## invulnerable_while_dashing's window (which is the dash's own length).
@export var invulnerable_duration: float = 0.0
## Keep running speed after the dash (fluid) instead of stopping dead.
@export var carry_momentum: bool = true

@export_group("Trail")
## Zone dropped along the path. Empty = no trail.
@export var trail_zone: GroundZoneData
## Pixels between trail zones.
@export var trail_spacing: float = 60.0


# Dash length for a charge ratio (always `distance` without charge_enabled).
func get_distance(ratio: float = 1.0) -> float:
	if not charge_enabled:
		return distance
	return lerpf(min_distance, distance, clampf(ratio, 0.0, 1.0))


func get_dash_time(dash_distance: float = -1.0) -> float:
	if dash_distance < 0.0:
		dash_distance = distance
	return dash_distance / speed if speed > 0.0 else 0.0


func get_scaling_values() -> Dictionary:
	var result := super()
	if trail_zone != null and trail_zone.tick_damage != null:
		result["trail_zone/tick_damage"] = trail_zone.tick_damage
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if min_distance < 0.0 or (charge_enabled and min_distance > distance):
		problems.append("'%s' min_distance must be between 0 and distance" % id)
	if invulnerable_duration < 0.0:
		problems.append("'%s' invulnerable_duration is negative" % id)
	if distance <= 0.0 or speed <= 0.0:
		problems.append("'%s' distance and speed must be above 0" % id)
	if trail_zone != null:
		if trail_zone.shape == null:
			problems.append("'%s' trail_zone has no shape" % id)
		if trail_zone.has_negative() or trail_spacing <= 0.0:
			problems.append("'%s' trail has negative/zero values" % id)
	return problems
