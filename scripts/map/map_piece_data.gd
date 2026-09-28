extends Resource
class_name MapPieceData

# Tuning for a neutral map piece (Map Liveliness Plan). One class for every
# piece; each uses only its own group. Anyone can hit a piece (it has no team),
# and hits come through the normal HurtboxComponent / HealthComponent path, so
# no hero code knows about pieces. Cues play through the match profiles
# (MatchManager.play_world_cue): each piece names its own below.

@export var display_name: String = ""

@export_group("Health")
@export var max_health: float = 600.0

@export_group("Breakable")
## Seconds from shattering until it starts regrowing (breakable cover).
@export var regrow_time: float = 25.0
## Seconds of warning shimmer before it's solid again.
@export var regrow_warning: float = 3.0
## While a body stands where it would regrow, it waits and retries this often.
@export var regrow_retry: float = 0.25

@export_group("Geyser")
## The geyser's mound: low cover of this radius (walk around it, shoot over).
@export var body_radius: float = 46.0
## Hits (not damage) that pop it (Mote geyser).
@export var hits_to_pop: int = 6
## Hits fade away if nobody hits it for this long.
@export var hit_decay_time: float = 4.0
@export var mote_count: int = 3
## Mote value before the late-match multiplier.
@export var mote_value: int = 1
@export var mote_burst_radius: float = 140.0
## Dormant seconds after popping.
@export var cooldown: float = 45.0
## Uses the small Mote when empty.
@export var mote_data: MoteData

@export_group("Cues")
## Match cue names (MatchRules.cue_visuals / cue_audio).
@export var hit_cue: StringName = &"piece_hit"
@export var break_cue: StringName = &""
@export var warning_cue: StringName = &""
@export var restore_cue: StringName = &""
