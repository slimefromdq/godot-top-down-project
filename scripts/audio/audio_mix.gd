@tool
extends Resource
class_name AudioMix

# How crowded the SFX mix may get (resources/audio/audio_mix.tres). With
# twelve heroes fighting, every gun, hit and footstep cue playing at full
# volume clips the bus and buries the sounds that matter, so AudioManager
# thins the mix before a sound starts:
#
#   * your own sounds (the local player's AudioComponent) always play, at
#     full volume;
#   * everyone else's are a little quieter, and skipped when they're far
#     off screen;
#   * the same sound file starting twice within a few milliseconds plays once
#     (twelve identical "hurt" hits sum into one clipped spike otherwise), and
#     at most same_stream_max_voices copies of one file ring at once;
#   * past max_sfx_voices, other heroes' sounds are dropped (yours steal the
#     oldest voice instead).

const DEFAULT_PATH := "res://resources/audio/audio_mix.tres"

## Most SFX players at once, over every cue.
@export var max_sfx_voices: int = 22
## A sound file started again within this many seconds is skipped.
@export var same_stream_window: float = 0.05
## Most copies of one sound file playing at once.
@export var same_stream_max_voices: int = 3
## Positional sounds from farther than this (pixels from the screen centre)
## aren't played at all...
@export var cull_distance: float = 1900.0
## ...and fade out over this distance (AudioStreamPlayer2D.max_distance),
## with this falloff curve.
@export var max_distance: float = 2200.0
@export var attenuation: float = 1.8
## Volume offset for sounds made by anyone but the local player.
@export var other_source_db: float = -4.0

static var _current: AudioMix


static func current() -> AudioMix:
	if _current == null:
		_current = load(DEFAULT_PATH) if ResourceLoader.exists(DEFAULT_PATH) else AudioMix.new()
	return _current
