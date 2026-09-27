@tool
extends AbilityData
class_name PikeObsessionData

# Data for Pike's Obsession passive.
#   values/ambush_cooldown           at most one ambush knife per this many s (6)
#   values/ambush_damage_multiplier  the ambush knife's damage (x2)
#   values/restealth_delay           seconds after reappearing before she can
#                                    vanish again (1.5)

## Kept on Pike while she's hidden (invisible to enemies, speed, fade).
@export var unseen_status: StatusEffect
## Casting from these slots keeps her hidden; anything else (and every
## knife) reveals her.
@export var keeps_stealth_slots: Array[StringName] = [&"movement"]
## Carried by the ambush knife (a root).
@export var ambush_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if unseen_status == null or ambush_status == null:
		problems.append("'%s' needs unseen_status and ambush_status" % id)
	return problems
