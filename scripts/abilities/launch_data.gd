@tool
extends AbilityData
class_name LaunchData

# Data for LaunchAbility: leap toward the cursor with Actor.launch() (up to
# max_distance), sailing over low cover and ledges like a jump pad; walls
# still stop you. With steer_speed, move input slides the landing point
# while airborne (a glide).

@export_group("Launch")
## Farthest landing point from the take-off spot (the cursor is clamped to it).
@export var max_distance: float = 800.0
## Seconds in the air (the whole leap takes exactly this long).
@export var air_time: float = 1.0
## How high the arc looks (cosmetic).
@export var arc_height: float = 140.0
## Pixels per second the landing point moves with move input while airborne.
## 0 = no steering. It never leaves max_distance of the take-off spot.
@export var steer_speed: float = 0.0
## Applied to the caster on take-off (e.g. damage resist while gliding).
@export var self_status: StatusEffect
## Applied to the caster on landing.
@export var landing_status: StatusEffect


func get_range() -> float:
	return ability_range if ability_range > 0.0 else max_distance


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"air_time": air_time, "max_distance": max_distance}


func validate() -> PackedStringArray:
	var problems := super()
	if max_distance <= 0.0 or air_time <= 0.0 or arc_height < 0.0 or steer_speed < 0.0:
		problems.append("'%s' launch needs a positive distance and air time" % id)
	for effect in [self_status, landing_status]:
		if effect != null:
			for problem in effect.validate():
				problems.append("'%s' %s" % [id, problem])
	return problems
