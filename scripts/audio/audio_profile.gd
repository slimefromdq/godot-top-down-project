extends Resource
class_name AudioProfile

# Everything an actor sounds like, in one .tres. Works exactly like
# VisualProfile: map cue names to SoundCues. See docs/VISUALS_AND_AUDIO.md.

## Cue name -> sound. Built-in names: hurt, heal, death, spawn, fire, reload,
## reload_done, dry_fire, ability_failed, plus each ability's ability_id
## (and <id>_end / <id>_hit where the ability documents them).
@export var cues: Dictionary[StringName, SoundCue] = {}
## Played on anything THIS actor kills: a cosmetic kill sound.
@export var kill_sound: SoundCue

@export_group("Music")
## Theme music requested while this actor is alive (e.g. a boss theme).
@export var theme_music: AudioStream
## Higher priority music wins. Level music uses 0; a boss might use 10.
@export var theme_priority: int = 10
@export var theme_fade_time: float = 1.0
