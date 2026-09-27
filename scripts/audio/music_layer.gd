extends Resource
class_name MusicLayer

# One stem of a MusicLayerSet. Every stem starts together and loops, so they
# stay in sync; a stem is audible while the set's current tier is at least
# `tier`. Leave `stream` empty and the layer is silent (the system still runs).

@export var layer_name: String = "base"
@export var stream: AudioStream
## Heard from this tier up (0 = always, 1 = from the second tier ...).
@export var tier: int = 0
@export_range(-40.0, 6.0, 0.5) var volume_db: float = 0.0
