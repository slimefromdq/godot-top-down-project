@tool
extends Resource
class_name FeelProfile

# Everything about how a hero's attacks FEEL, in one inspector: timing,
# commitment, cancel windows, buffering, and (in the Cosmetic group) hitstop,
# shake, flash, trails and sound layers.
#
# Abilities don't hold their own feel numbers; they name a preset ("light",
# "heavy", "finisher") and the hero's FeelProfile supplies it. Retuning every
# heavy attack of a hero is one edit, and a new melee hero starts from a
# copy of an existing profile.

## Named presets. Abilities refer to these by key.
@export var presets: Dictionary[StringName, AttackFeel] = {}
## Used when an ability names a preset that isn't here.
@export var fallback: AttackFeel

@export_group("Input")
## Seconds an early press is remembered while the hero is busy. Negative = use
## GameRules.default_input_buffer.
@export var input_buffer: float = -1.0

@export_group("Cosmetic")
## Feel used for hits that don't come from a timed swing (projectiles,
## bursts). Empty = fallback.
@export var projectile_feel: AttackFeel

@export_subgroup("Hitstop")
## Extra freeze per 100 damage dealt, so big hits stop harder.
@export var hitstop_per_100_damage: float = 0.02
## Upper limit for any single freeze (the ~90 ms ceiling).
@export_range(0.0, 0.2, 0.005) var hitstop_max: float = 0.09
## Pixels the target shivers while frozen.
@export var hitstop_tremble: float = 3.0
## Seconds a frozen sprite takes to catch back up with its body.
@export var hitstop_catch_up: float = 0.06

@export_subgroup("Camera")
## Trauma when THIS hero (if it's the local player) gets hit.
@export_range(0.0, 1.0, 0.01) var hurt_shake: float = 0.3

@export_subgroup("Trail")
## Scene spawned on the hero for each swing. Receives setup_cue(context).
@export var slash_trail_scene: PackedScene

@export_subgroup("Audio defaults")
@export var swing_sound: SoundCue
@export var impact_sound: SoundCue
@export var fire_sound: SoundCue
## Random pitch spread (+/-) on top of each SoundCue's own range.
@export_range(0.0, 0.3, 0.01) var pitch_jitter: float = 0.05


# Hitstop for a hit of `damage` with `feel`, before global settings.
func get_hitstop(feel: AttackFeel, damage: float) -> float:
	if feel == null:
		return 0.0
	return minf(feel.hitstop + damage / 100.0 * hitstop_per_100_damage, hitstop_max) \
		if feel.hitstop > 0.0 else 0.0


func get_sound(feel: AttackFeel, which: StringName) -> SoundCue:
	var own: SoundCue = feel.get(which) if feel != null else null
	return own if own != null else get(which)


func get_preset(preset: StringName) -> AttackFeel:
	var feel: AttackFeel = presets.get(preset)
	if feel != null:
		return feel
	return fallback


func get_input_buffer() -> float:
	return input_buffer if input_buffer >= 0.0 else GameRules.current().default_input_buffer
