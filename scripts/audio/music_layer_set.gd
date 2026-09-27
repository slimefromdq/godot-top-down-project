extends Resource
class_name MusicLayerSet

# Adaptive music: synced stems that all start together and loop, faded in and
# out by volume as the "tier" (intensity) changes. AudioManager plays it
# (play_layers / set_music_tier / play_sting); a game system decides the
# tier (MatchMusic for the match). Stems with no stream are simply silent.
# See docs/MUSIC_STEMS.md for what each stem is for.

## Every stem shares these (for the composer; not used to play).
@export var bpm: float = 100.0
@export var bars_per_loop: int = 8
@export var layers: Array[MusicLayer] = []
## Played once at the end (the victory sting), over the fading stems.
@export var victory_sting: AudioStream
@export_range(-40.0, 6.0, 0.5) var sting_volume_db: float = 0.0
## Seconds a tier change crossfades over.
@export var crossfade_time: float = 1.5
## The tier never drops more than one step per this many seconds, so it
## doesn't flicker when a meter hovers near a threshold.
@export var min_seconds_per_drop: float = 8.0
