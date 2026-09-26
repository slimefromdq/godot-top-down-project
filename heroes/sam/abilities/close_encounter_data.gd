@tool
extends AbilityData
class_name SamEncounterData

# Data for Close Encounter. Target an enemy near the cursor (ally_targeting
# with accepts ENEMIES, cast_range 700). Named values:
#   values/telegraph    seconds the beam takes to land (they can dodge it)
#   values/beam_radius  how far they may be from the spot and still be taken
#   values/ufo_speed    how fast the UFO (the victim) flies toward Sam's cursor

## The minigame the victim plays (the airlock maze).
@export var minigame: MinigameData
## On the victim while abducted: untargetable, the UFO look for everyone.
@export var abducted_status: StatusEffect
## On the victim when dropped (the landing daze).
@export var daze_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := super()
	if minigame == null or abducted_status == null or daze_status == null:
		problems.append("'%s' needs a minigame, an abducted_status and a daze_status" % id)
	elif not minigame.validate().is_empty():
		problems.append("'%s' minigame: %s" % [id, ", ".join(minigame.validate())])
	return problems
