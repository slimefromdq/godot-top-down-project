@tool
extends MinigameData
class_name AirlockData

# Numbers for the airlock (AirlockMinigame), Sam's Close Encounter: a short
# top-down maze. Start on the left, find the way through the inner walls to
# the door strip on the right, and stand in it for door_hold. Distances are
# room pixels (the overlay scales the room to fit). Each abduction picks one
# of `layouts` at random, so there's no single route to memorise.

@export_group("Room")
@export var room_size := Vector2(460, 300)
@export var start := Vector2(40, 150)
## The door strip starts here and runs to the right wall.
@export var door_x: float = 420.0
## Seconds standing in the door strip to open it.
@export var door_hold: float = 0.3
@export var player_speed: float = 470.0
@export var player_radius: float = 16.0
@export var layouts: Array[MazeLayout] = []

@export_group("AI victims")
## An AI victim (no player) finds the way at this fraction of full speed.
@export_range(0.1, 1.0, 0.05) var bot_speed_scale: float = 0.75


func validate() -> PackedStringArray:
	var problems := super()
	if door_x <= start.x or door_x >= room_size.x or player_speed <= 0.0 or door_hold < 0.0:
		problems.append("airlock needs start.x < door_x < room width and a positive speed")
	if layouts.is_empty():
		problems.append("airlock has no maze layouts")
	return problems
