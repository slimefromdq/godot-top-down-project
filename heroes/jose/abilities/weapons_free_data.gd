@tool
extends ZoneAbilityData
class_name WeaponsFreeData

# Data for Jose's ultimate (weapons_free_ability.gd). The kill box is the
# inherited `zone` (a CIRCLE that follows Jose, no damage of its own) and
# `zone_duration` is the channel length. Named values:
#   values/weapons_free_fire_rate   multiplies the gun's shots per second

@export_group("Weapons Free")
## Slot of the gun that auto-fires (its projectile, damage and muzzles).
@export var gun_slot: StringName = &"primary"
## Walking speed multiplier while channelling.
@export_range(0.0, 1.0, 0.05) var channel_move_speed_multiplier: float = 0.6
## Slots that still work during the channel (Flourish).
@export var allowed_slots: Array[StringName] = [&"movement"]
## Blocked slots that fail silently (manual fire is replaced by autofire).
## Every other slot is blocked with a "Channeling" message.
@export var quiet_slots: Array[StringName] = [&"primary"]
## Only shoot targets Jose can see (CombatQueries.has_line_of_sight:
## walls block, and enemies hidden in a bush are skipped).
@export var requires_line_of_sight: bool = true
## Pressing the ultimate again ends the channel early.
@export var recast_ends_channel: bool = false
## Silence ends the channel (a stun always does).
@export var silence_interrupts: bool = true
## Damage-meter label for the auto-shots.
@export var shot_label: StringName = &"weapons_free"

@export_group("Audio")
## Optional music stinger while channelling (AudioManager music request).
@export var channel_music: AudioStream
@export var channel_music_priority: int = 50
@export var channel_music_fade: float = 0.3


func get_balance_metrics(level: int, weapon: float, magic: float) -> Dictionary:
	var result := super(level, weapon, magic)
	if values.has(&"weapons_free_fire_rate"):
		result["weapons_free_fire_rate"] = values[&"weapons_free_fire_rate"].evaluate_at(level, weapon, magic)
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if gun_slot == &"":
		problems.append("'%s' has no gun_slot" % id)
	if not values.has(&"weapons_free_fire_rate"):
		problems.append("'%s' is missing values/weapons_free_fire_rate" % id)
	if channel_move_speed_multiplier < 0.0:
		problems.append("'%s' channel_move_speed_multiplier is negative" % id)
	return problems
