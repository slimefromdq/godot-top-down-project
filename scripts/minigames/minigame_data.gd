@tool
extends Resource
class_name MinigameData

# Numbers every minigame has. Subclass it for a minigame's own numbers
# (AirlockData).

## It can't end sooner than this (reaching the goal early waits it out).
@export var min_duration: float = 1.0
## Forced end (result "timeout") after this long.
@export var max_duration: float = 4.0
## Kept on the actor while it plays (default: rooted and silenced).
@export var occupied_status: StatusEffect


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if min_duration < 0.0 or max_duration <= 0.0 or min_duration > max_duration:
		problems.append("minigame needs 0 <= min_duration <= max_duration")
	return problems
