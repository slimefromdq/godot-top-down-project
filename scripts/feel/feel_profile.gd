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


func get_preset(preset: StringName) -> AttackFeel:
	var feel: AttackFeel = presets.get(preset)
	if feel != null:
		return feel
	return fallback


func get_input_buffer() -> float:
	return input_buffer if input_buffer >= 0.0 else GameRules.current().default_input_buffer
