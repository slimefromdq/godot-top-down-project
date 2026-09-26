extends Resource
class_name MoteData

# One kind of Mote (resources/match/small_mote.tres, dream_mote.tres).
# The match's spawn timings live in MatchRules; this is the Mote itself.

@export var id: StringName = &"mote"
## Worth this much when banked or delivered (before the late-match multiplier).
@export var value: int = 1
## A Dream Mote: announced, always on both teams' minimaps, with an off-screen
## arrow, and whoever carries it is always revealed.
@export var is_dream: bool = false

@export_group("Pickup")
## A hero this close gets pulled in...
@export var magnet_radius: float = 110.0
## ...over this many seconds, then it attaches.
@export var magnet_time: float = 0.2
## After a drop, its last carrier can't grab it back for this long.
@export var regrab_lockout: float = 1.5

@export_group("Dropped")
## A dropped Mote (death burst, jostle) fades after this long. Spawned Motes
## never fade.
@export var fade_time: float = 20.0
## It blinks for this long before fading.
@export var blink_time: float = 5.0

@export_group("Look")
## The body. Its root gets setup_mote(mote) if it has that method. Swap for a
## sprite scene later; gameplay never reads it.
@export var look_scene: PackedScene
## Drawn size in pixels (the procedural look reads it).
@export var size: float = 34.0
