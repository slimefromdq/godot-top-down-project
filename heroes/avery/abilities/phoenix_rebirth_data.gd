@tool
extends AbilityData
class_name PhoenixRebirthData

# Phoenix Rebirth: when Avery would die while this is off cooldown, the death
# is cancelled, she goes through a short rebirth (can't act, can't be hurt),
# then rises with a share of her health and, optionally, a fire burst.
#
# Trigger mode: automatic when she would die. While alive she can also press
# the key to spend the ultimate on a Blaze (blaze_status on herself and
# blaze_zone around her); either use puts the ultimate on cooldown.
#
# The burst reuses the base AbilityData hit fields: hit_shape (the area),
# damage + damage_type, on_hit_status (e.g. a knockback), plus burst_extra_status.

@export_group("Rebirth")
## Health restored when she rises, as a fraction of max HP.
@export_range(0.05, 1.0, 0.05) var restore_health_ratio: float = 0.4
## Seconds the rebirth takes. She can't act and takes no damage meanwhile.
@export var rebirth_duration: float = 1.2
## Extra seconds of invulnerability after rising.
@export var invulnerable_after: float = 0.3
## Status on Avery during the rebirth (should stun, so she can't act).
@export var rebirth_state: StatusEffect
## Remove her debuffs (burns, slows) when the rebirth starts.
@export var cleanse_on_trigger: bool = true

@export_group("Fire burst")
@export var burst_enabled: bool = true
## Applied with on_hit_status, e.g. a burn.
@export var burst_extra_status: StatusEffect

@export_group("Blaze (cast while alive)")
## Press the key while alive to spend the ultimate on a Blaze instead of
## keeping it for the revive.
@export var blaze_enabled: bool = true
## Status on Avery while blazing (speed, regeneration). Its duration is the
## length of the Blaze.
@export var blaze_status: StatusEffect
## Aura that follows her for the Blaze (damage and burn on enemies inside).
@export var blaze_zone: GroundZoneData


func get_range() -> float:
	if blaze_enabled and blaze_zone != null and blaze_zone.shape != null:
		return blaze_zone.shape.get_reach()
	return super()


func get_scaling_values() -> Dictionary:
	var result := super()
	if blaze_zone != null and blaze_zone.tick_damage != null:
		result["blaze/tick_damage"] = blaze_zone.tick_damage
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if rebirth_state == null:
		problems.append("'%s' has no rebirth_state status" % id)
	if rebirth_duration < 0.0 or invulnerable_after < 0.0:
		problems.append("'%s' rebirth timings are negative" % id)
	if blaze_enabled and (blaze_status == null or blaze_zone == null):
		problems.append("'%s' blaze is enabled but has no blaze_status/blaze_zone" % id)
	if burst_enabled and (hit_shape == null or damage == null):
		problems.append("'%s' burst is enabled but has no hit_shape/damage" % id)
	return problems
