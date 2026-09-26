@tool
extends AbilityData
class_name TillyCrumpleZoneData

# Data for Tilly's Crumple Zone passive: a status she always carries (shorter
# knockbacks and pulls) and one she gets every time she lands from a launch.

## Kept on her at all times (StatusEffect.DISPLACEMENT_TAKEN below 1).
@export var always_status: StatusEffect
## Applied on every landing from a launch (a speed burst).
@export var landing_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	for effect in [always_status, landing_status]:
		if effect == null:
			problems.append("'%s' needs always_status and landing_status" % id)
		else:
			for problem in effect.validate():
				problems.append("'%s' %s" % [id, problem])
	return problems
