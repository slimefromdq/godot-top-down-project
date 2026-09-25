@tool
extends Resource
class_name AttackFeel

# How one attack (or cast) plays out over time, and how heavy it feels.
#
# A FeelProfile holds named presets ("light", "heavy", "finisher"); an ability
# or combo step picks one by name. The inspector groups split the values in
# two, and that split matters for networking:
#
#   Simulation  changes what happens in the game (when the hit lands, how far
#               you lunge, when you can act again). Deterministic, runs on
#               physics ticks; a server would run these.
#   Cosmetic    only changes what you see and hear. Local to each player,
#               never affects the simulation. (Filled in by the game-feel pass.)
#
# Timeline of a cast:
#   |-- windup --|-- active --|------ recovery ------|
#   anticipation   hitbox on   follow-through; cancellable after the
#   (lean back)    lunge       cancel_* times below

@export_group("Simulation")
## Seconds of anticipation before the hit can land. Heavier = longer.
@export_range(0.0, 2.0, 0.01) var windup: float = 0.1
## Seconds the hitbox is live.
@export_range(0.0, 2.0, 0.01) var active: float = 0.08
## Seconds of follow-through after the hitbox closes.
@export_range(0.0, 2.0, 0.01) var recovery: float = 0.2
## Walking speed multiplier for the whole cast (commitment). 1 = no slow.
@export_range(0.0, 1.0, 0.05) var move_multiplier: float = 0.4
## Forward step toward the aim direction when the active frames start.
@export var lunge_distance: float = 30.0
@export_range(0.0, 0.5, 0.01) var lunge_duration: float = 0.08
## Seconds into recovery after which walking or a movement ability cancels
## the rest of the recovery. 0 = the whole recovery is cancellable.
## Negative = never.
@export var movement_cancel_after: float = 0.0
## Seconds into recovery after which another ability (or the next combo hit)
## can start. Earlier presses are buffered, not dropped.
@export var ability_cancel_after: float = 0.1
## Lock the aim when the windup starts (true = committed swing).
@export var lock_aim: bool = true

@export_group("Cosmetic")
## How heavy this reads to the cosmetic systems (hitstop, shake, sound).
## 1 = a normal hit, 2+ = a finisher. Never read by gameplay.
@export_range(0.0, 3.0, 0.05) var weight: float = 1.0


func get_total_time() -> float:
	return windup + active + recovery


# An instant cast: no phases at all (old-style abilities).
static func instant() -> AttackFeel:
	var feel := AttackFeel.new()
	feel.windup = 0.0
	feel.active = 0.0
	feel.recovery = 0.0
	feel.move_multiplier = 1.0
	feel.lunge_distance = 0.0
	feel.ability_cancel_after = 0.0
	return feel


func has_negative() -> bool:
	return windup < 0.0 or active < 0.0 or recovery < 0.0 or lunge_distance < 0.0 \
		or lunge_duration < 0.0 or move_multiplier < 0.0
