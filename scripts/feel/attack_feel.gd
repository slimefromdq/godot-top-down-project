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

@export_subgroup("Anticipation")
## Pixels the body leans back (away from the aim) during the windup.
@export var windup_lean: float = 10.0
## Squash during the windup (0.1 = 10% wider, 10% shorter).
@export_range(0.0, 0.5, 0.01) var windup_squash: float = 0.06
## Brightness the body builds toward during the windup. Alpha = strength.
@export var windup_glow: Color = Color(1.0, 0.85, 0.5, 0.3)
## Pixels the body snaps forward when the swing releases.
@export var release_snap: float = 14.0

@export_subgroup("Hitstop")
## Freeze on hit, in seconds, before the damage bonus (FeelProfile). Only the
## animations of the attacker and target freeze; the game never pauses.
@export_range(0.0, 0.2, 0.005) var hitstop: float = 0.045
## Freeze the attacker too (melee), or only the target (projectiles).
@export var hitstop_attacker: bool = true

@export_subgroup("Camera")
## Trauma added on hit (0-1). Only when the local player is involved.
## Shake grows with trauma squared, so below ~0.15 it's barely visible.
@export_range(0.0, 1.0, 0.01) var shake_on_hit: float = 0.22
## Trauma added when the swing releases, hit or miss. Keep 0 for light swings.
@export_range(0.0, 1.0, 0.01) var shake_on_swing: float = 0.0
## Pixels the camera leans in the swing direction on release.
@export var camera_nudge: float = 8.0

@export_subgroup("Hit flash")
@export var flash_color: Color = Color(1, 1, 1, 0.9)
@export_range(0.0, 0.5, 0.01) var flash_time: float = 0.08

@export_subgroup("Trail")
@export var trail_color: Color = Color(1.0, 0.85, 0.45, 0.9)
## Thickness multiplier for the slash trail band.
@export_range(0.2, 3.0, 0.05) var trail_width: float = 1.0
## Fire particles thrown off the blade tip during the swing. 0 = none.
@export_range(0, 128) var trail_particles: int = 18

@export_subgroup("Audio")
## Swing whoosh. Empty = the FeelProfile default.
@export var swing_sound: SoundCue
## Impact on hit. Empty = the FeelProfile default.
@export var impact_sound: SoundCue
## Fire layer on swing and hit. Empty = the FeelProfile default.
@export var fire_sound: SoundCue
## Heavier attacks sound deeper: < 1 lowers the pitch.
@export_range(0.5, 2.0, 0.01) var pitch_scale: float = 1.0


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
