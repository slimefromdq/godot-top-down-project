@tool
extends AbilityData
class_name RideData

# Data for RideAbility: hold to ride forward at high speed, steering freely;
# let go (or run out of time) to land with a telegraphed burst.
#
#   hold      the ride. This IS the ability's Charge phase, so the Charge
#             group sets it up: charge_time_max = the longest ride (it
#             lands by itself then, charge_auto_release_at_max), and
#             charge_min_to_fire = the shortest. validate() checks them.
#   windup    landing_telegraph seconds: the hero plants, the landing
#             circle fills in (cue <id>_windup, context.radius/.duration)
#   active    the burst: hit_shape (a CIRCLE around the hero) for `damage`
#             plus on_hit_status (e.g. a knockback) on every enemy inside
#   recovery  from the feel preset
#
# The cooldown starts when the ride ends: on landing, or when a stun/death
# cuts the ride short (no free rides by getting interrupted).

enum SteerMode {
	MOVE_INPUT,   ## Steer with the movement keys; no input keeps the heading.
	AIM,          ## Steer toward the aim point.
}

@export_group("Ride")
## Pixels per second while riding (status slows still apply).
@export var ride_speed: float = 1100.0
## How fast the ride reaches ride_speed and changes velocity.
@export var ride_acceleration: float = 7000.0
## Degrees per second the heading can turn. 0 = turns instantly.
@export var turn_rate_degrees: float = 300.0
@export var steer_mode: SteerMode = SteerMode.MOVE_INPUT
## Applied to the rider while riding, removed on landing (a tint, a resist).
@export var ride_status: StatusEffect

@export_group("Landing")
## Seconds of readable warning between the end of the ride and the burst.
@export var landing_telegraph: float = 0.25


func get_range() -> float:
	return ability_range if ability_range > 0.0 else ride_speed * charge_time_max


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"max_ride_time": charge_time_max, "max_ride_distance": ride_speed * charge_time_max,
		"landing_telegraph": landing_telegraph}


func validate() -> PackedStringArray:
	var problems := super()
	if not charge_enabled or not charge_auto_release_at_max or charge_can_cancel:
		problems.append("'%s' rides need charge_enabled, charge_auto_release_at_max and charge_can_cancel off" % id)
	if charge_below_min != ChargeBelowMin.FIRE_MINIMUM:
		problems.append("'%s' rides need charge_below_min = FIRE_MINIMUM (a tap still lands)" % id)
	if ride_speed <= 0.0 or ride_acceleration < 0.0 or turn_rate_degrees < 0.0 or landing_telegraph < 0.0:
		problems.append("'%s' has negative/zero ride numbers" % id)
	if hit_shape == null or damage == null:
		problems.append("'%s' needs a hit_shape and damage for the landing burst" % id)
	if ride_status != null:
		for problem in ride_status.validate():
			problems.append("'%s' ride_status: %s" % [id, problem])
	return problems
