extends Resource
class_name SoundCue

# One sound event. Put several variations in `streams` and one is picked at
# random each time, with a little pitch variation, so rapid repeats (like a
# machine gun) don't sound robotic.

@export var streams: Array[AudioStream] = []
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0
@export_range(0.1, 3.0, 0.01) var pitch_min: float = 0.95
@export_range(0.1, 3.0, 0.01) var pitch_max: float = 1.05
## Audio bus. SFX and Music exist in default_bus_layout.tres.
@export var bus: StringName = &"SFX"
## Play in world space (quieter far from the camera). Off for UI-style sounds.
@export var positional: bool = true
## Minimum seconds between plays of this cue. Stops rapid fire from stacking
## into noise. 0 = no limit.
@export var min_interval: float = 0.0
## Most copies of this cue playing at once. Oldest is cut off. 0 = no limit.
@export var max_voices: int = 6


func pick_stream() -> AudioStream:
	if streams.is_empty():
		return null
	return streams.pick_random()
