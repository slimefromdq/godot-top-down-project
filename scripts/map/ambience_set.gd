extends Resource
class_name AmbienceSet

# One map's ambience: which AmbienceProfile each region kind uses (keyed by
# DreamZone pair_id), the match mood, and how each Dreamer's Plaza glows.
# Used by MapAmbience. Presentation only.

## DreamZone pair_id -> profile. Regions with no entry stay quiet.
@export var regions: Dictionary[StringName, AmbienceProfile] = {}
## Seconds for region sound beds to crossfade as the listener moves.
@export var crossfade_time: float = 1.5

@export_group("Mood")
@export var mood: MapMoodProfile

@export_group("Dreamer Glow")
## Soft team-coloured glow on the ground around each Dreamer, growing with
## its wake meter.
@export var glow_radius: float = 700.0
@export_range(0.0, 1.0) var glow_alpha_asleep: float = 0.05
@export_range(0.0, 1.0) var glow_alpha_full: float = 0.35
## While stirring the glow pulses this many times a second, this much.
@export var stir_pulse_speed: float = 1.6
@export_range(0.0, 1.0) var stir_pulse_amount: float = 0.5

@export_group("Reactions")
## Actor cues that count as loud: the cue itself or `<ability>_<cue>`.
@export var startle_cues := PackedStringArray(["fire", "death"])
## A loud cue within this distance of a region's critters scatters them.
@export var shot_scatter_radius: float = 700.0
## Fountains: a ring spreads across the water about every ripple_interval
## seconds, and when a shot is fired within shot_scatter_radius.
@export var ripple_interval: float = 2.5
@export var ripple_speed: float = 60.0
@export var ripple_life: float = 2.2
@export var ripple_color := Color(1, 1, 1, 0.55)
