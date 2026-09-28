extends Resource
class_name AmbienceProfile

# How one kind of region looks and sounds when nobody is fighting in it:
# drifting motes (pollen, fog wisps, dust ...), critters that scatter from
# heroes, and a looping ambient sound. Presentation only. An AmbienceSet maps
# region pair ids (a DreamZone's pair_id) to these. See
# docs/VISUALS_AND_AUDIO.md > Map ambience.

@export_group("Drifters")
## Drifting particles per million px² of region (about 0.5 screens).
@export var density: float = 30.0
@export var color := Color(1, 1, 1, 0.5)
## Each drifter picks between color and color_alt.
@export var color_alt := Color(1, 1, 1, 0.3)
@export var size_min: float = 3.0
@export var size_max: float = 7.0
## Stretch along the drift direction (1 = round; 3 = long fog wisps).
@export var stretch: float = 1.0
## Steady drift, px/s. Drifters wrap around the region's bounds.
@export var drift := Vector2(12, -6)
## Side-to-side sway, px, and its speed (cycles/s).
@export var sway: float = 10.0
@export var sway_speed: float = 0.3
## 0 = steady; 1 = blinks fully on and off (fireflies).
@export_range(0.0, 1.0) var twinkle: float = 0.0
@export var twinkle_speed: float = 0.8

@export_group("Critters")
## Small critters (birds, fireflies, moths) resting in the region.
@export var critter_count: int = 0
@export var critter_color := Color(1, 1, 1, 0.9)
@export var critter_size: float = 5.0
## A hero this close startles them.
@export var scatter_radius: float = 260.0
@export var scatter_speed: float = 420.0
## Seconds before a scattered critter settles back down.
@export var settle_time: float = 6.0

@export_group("Sound")
## Looping bed played while the listener is in this region (crossfaded).
@export var loop: AudioStream
@export_range(-40.0, 6.0, 0.5) var loop_volume_db: float = -14.0
