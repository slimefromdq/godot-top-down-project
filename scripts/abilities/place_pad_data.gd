@tool
extends AbilityData
class_name PlacePadData

# Data for PlacePadAbility: put down a jump pad (JumpPad.place). Press to place
# it at the cursor (within place_range), drag, release: the landing spot is
# where the cursor was let go, up to max_offset from the pad. Allies of the
# caster (and the caster) who step on it are launched there; enemies get
# enemy_status instead. Turn on the Charge group (charge_enabled) for the
# hold-and-drag; without it the landing is min_offset along the aim.
# max_charges on the data lets several be stocked.

@export_group("Pad")
## Farthest from the caster the pad can be put down.
@export var place_range: float = 500.0
## Farthest landing spot from the pad.
@export var max_offset: float = 700.0
## Shortest throw: a release closer than this lands min_offset along the aim.
@export var min_offset: float = 200.0
@export var pad_radius: float = 70.0
## Seconds in the air per launch.
@export var air_time: float = 0.8
@export var arc_height: float = 160.0
## Seconds before a pad disappears. 0 = until max_launches.
@export var lifetime: float = 10.0
## Launches before a pad disappears. 0 = until lifetime.
@export var max_launches: int = 4
## Put on enemies who step on it (e.g. a displacement back the way they came).
@export var enemy_status: StatusEffect
@export var pad_color: Color = Color("f5c518")


func get_range() -> float:
	return ability_range if ability_range > 0.0 else place_range


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"max_offset": max_offset, "pad_lifetime": lifetime, "pad_max_launches": max_launches}


func validate() -> PackedStringArray:
	var problems := super()
	if place_range < 0.0 or max_offset <= 0.0 or min_offset < 0.0 or min_offset > max_offset \
			or pad_radius <= 0.0 or air_time <= 0.0 or lifetime < 0.0 or max_launches < 0:
		problems.append("'%s' pad needs positive sizes/timings and min_offset <= max_offset" % id)
	if lifetime <= 0.0 and max_launches <= 0:
		problems.append("'%s' pad never expires (set lifetime or max_launches)" % id)
	if enemy_status != null:
		for problem in enemy_status.validate():
			problems.append("'%s' enemy_status: %s" % [id, problem])
	return problems
