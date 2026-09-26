@tool
extends AbilityData
class_name ChargeData

# Data for ChargeAbility: a telegraphed dash/leap toward the aim, optionally
# leaving a trail of GroundZones behind it.
#
# Timing: the windup (the telegraph) and recovery come from the feel preset
# like any other ability (telegraph_time overrides the windup); the dash
# itself lasts distance / speed.
#
# Sweep and drop: with a bash (hit_shape + damage) whose on_hit_status
# carries (StatusEffect.carry_enabled), everything the dash runs into is
# swept along with the hero. end_on_hit_status_on_arrival lets them go when
# the dash ends, and arrival_status is applied to each of them then (a
# stun on landing).

## Which way the dash goes.
enum DirectionMode {
	AIM,                ## Toward the aim (a telegraphed charge).
	MOVE_INPUT_OR_AIM,  ## The way the hero is walking; the aim if standing still (a roll).
}

@export_group("Charge")
@export var direction_mode: DirectionMode = DirectionMode.AIM
@export var distance: float = 400.0
## Stop at the aim point if it's closer than `distance` (a blink "up to"
## its range). Off = always the full distance.
@export var stop_at_target: bool = false
## Applied to the hero when the dash arrives (a vanish after a blink, a
## speed burst). Empty = none.
@export var self_status: StatusEffect
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
## Seconds of telegraph (the windup) before the dash starts. Negative = the
## feel preset's windup.
@export var telegraph_time: float = -1.0

@export_group("Arrival")
## When the dash ends (or is cut short), remove on_hit_status from every
## target the bash hit: a carry lasts exactly as long as the dash.
@export var end_on_hit_status_on_arrival: bool = false
## Applied to every target the bash hit when the dash ends (a drop stun).
@export var arrival_status: StatusEffect

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
	if arrival_status != null:
		for problem in arrival_status.validate():
			problems.append("'%s' arrival_status: %s" % [id, problem])
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
