@tool
extends MinigameData
class_name AirlockData

# Numbers for the airlock (AirlockMinigame), Sam's Close Encounter. A small
# top-down room: start on the left, the door on the right. Distances are in
# room pixels (the room is room_size; the overlay scales it to fit).
# Hazard patterns are fixed (not random), so the room can be learned.

@export_group("Room")
@export var room_size := Vector2(600, 320)
@export var start_x: float = 40.0
## The door strip starts here and runs to the right wall.
@export var door_x: float = 520.0
## Seconds standing in the door strip to open it.
@export var door_hold: float = 0.3
@export var player_speed: float = 400.0
@export var player_radius: float = 18.0

@export_group("Getting hit")
## Every hit pushes the player back (to the left) this far.
@export var knockback: float = 60.0
## Seconds after a hit before the next one can land.
@export var hit_cooldown: float = 0.35

@export_group("Hearts")
## Slow hearts drifting in from the right along lanes (fractions of height).
@export var heart_lanes: PackedFloat32Array = PackedFloat32Array([0.5, 0.22, 0.78, 0.5, 0.35, 0.65])
@export var heart_first: float = 0.0
@export var heart_interval: float = 0.55
@export var heart_speed: float = 170.0
@export var heart_radius: float = 16.0

@export_group("HI!! bubbles")
## Speech bubbles sweeping down columns (fractions of width).
@export var bubble_columns: PackedFloat32Array = PackedFloat32Array([0.3, 0.7, 0.5])
@export var bubble_first: float = 0.6
@export var bubble_interval: float = 0.8
@export var bubble_speed: float = 300.0
@export var bubble_size := Vector2(110, 36)

@export_group("Hug arm")
## A wobbly arm from the left wall that grabs at where the player is.
@export var arm_delay: float = 0.6
@export var arm_speed: float = 260.0
@export var arm_radius: float = 22.0
@export var arm_wobble: float = 18.0


func validate() -> PackedStringArray:
	var problems := super()
	if door_x <= start_x or door_x >= room_size.x or player_speed <= 0.0 or door_hold < 0.0:
		problems.append("airlock needs start_x < door_x < room width and a positive speed")
	return problems


# Seconds a flawless run takes: straight to the door, then the hold.
func perfect_time() -> float:
	return (door_x - start_x) / player_speed + door_hold
