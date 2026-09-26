@tool
extends AbilityData
class_name CosmoStarfallData

# Starfall (Cosmo's ultimate). Meteors hit for the inherited `damage`
# through `meteor` (a ProjectileData explosion). Named values:
#   values/channel_duration       seconds
#   values/storm_radius           meteors land within this of the cast point
#   values/meteors_per_second     used when scale_with_moons is off
#   values/impact_delay           shadow time before each meteor lands
#   values/starfall_weapon_resist fraction of PHYSICAL damage she ignores

@export_group("Starfall")
@export var meteor: ProjectileData
## The storm's edge (a CIRCLE zone, no damage); its radius is storm_radius.
@export var storm_zone: GroundZoneData
## On Cosmo while channelling: can't walk (move_speed x 0; dashes still work).
@export var channel_status: StatusEffect
## On Cosmo while channelling: a -100% incoming PHYSICAL "unit", applied at
## strength starfall_weapon_resist. Magic damage is not reduced.
@export var resist_status: StatusEffect

@export_group("Moons")
## Meteors per second scale with her moons gained (index 0 = her base
## moons, 1 = one Waxing Moon breakpoint reached, ...).
@export var scale_with_moons: bool = true
@export var meteors_per_second_by_moons: Array[float] = [3.5, 4.0, 4.5, 5.0, 5.5]

@export_group("Interrupts")
@export var ends_on_stun: bool = true
@export var ends_on_silence: bool = true
@export var ends_on_recast: bool = true
## Her movement ability (New Moon) ends the channel: her escape hatch.
@export var ends_on_movement: bool = true

@export_group("Audio")
## Optional music stinger while channelling.
@export var channel_music: AudioStream
@export var channel_music_priority: int = 50


func get_meteor_rate(waxes: int) -> float:
	if scale_with_moons and not meteors_per_second_by_moons.is_empty():
		return meteors_per_second_by_moons[clampi(waxes, 0, meteors_per_second_by_moons.size() - 1)]
	return get_value(&"meteors_per_second", null)


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	var result := {}
	for i in meteors_per_second_by_moons.size():
		result["meteors_per_second/+%d_moons" % i] = meteors_per_second_by_moons[i]
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if meteor == null or meteor.explosion_shape == null:
		problems.append("'%s' needs a meteor with an explosion_shape" % id)
	if storm_zone == null or channel_status == null or resist_status == null:
		problems.append("'%s' needs storm_zone, channel_status and resist_status" % id)
	for key in [&"channel_duration", &"storm_radius", &"meteors_per_second", &"impact_delay", &"starfall_weapon_resist"]:
		if not values.has(key):
			problems.append("'%s' is missing values/%s" % [id, key])
	return problems
