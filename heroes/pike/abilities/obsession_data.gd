@tool
extends AbilityData
class_name PikeObsessionData

# Data for Pike's Obsession passive.
#   values/ambush_cooldown           at most one ambush knife per this many s (6)
#   values/ambush_damage_multiplier  the ambush knife's damage (x2)

## Kept on Pike while her Beloved can't see her (speed, fade).
@export var unseen_status: StatusEffect
## Carried by the ambush knife (a root).
@export var ambush_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if unseen_status == null or ambush_status == null:
		problems.append("'%s' needs unseen_status and ambush_status" % id)
	return problems
