@tool
extends Resource
class_name FeelSettings

# Player-facing comfort settings for game feel, applied on top of every
# hero's FeelProfile. These are the accessibility knobs: they only scale
# cosmetic effects and can never change gameplay.
#
# One instance lives at resources/feel/feel_settings.tres; GameFeel.settings
# is the live copy (the debug panel edits it).

## Global screen-shake multiplier. 0 = no shake at all.
## (Shake grows with trauma SQUARED: 0.2 trauma is a ~1 px tremor, 0.45 a
## ~4 px thud, the 0.6 cap about 8 px.)
@export_range(0.0, 2.0, 0.05) var shake_intensity: float = 1.0
## Hard cap on shake trauma, so stacked hits can never get violent.
@export_range(0.0, 1.0, 0.05) var max_trauma: float = 0.6
## Max shake offset in pixels at full trauma.
@export var max_shake_offset: Vector2 = Vector2(22, 16)
## Shake wobble speed. Lower is smoother and less nauseating.
@export var shake_frequency: float = 18.0
@export var hitstop_enabled: bool = true
@export_range(0.0, 2.0, 0.05) var hitstop_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var camera_nudge_scale: float = 1.0
@export var flash_enabled: bool = true
