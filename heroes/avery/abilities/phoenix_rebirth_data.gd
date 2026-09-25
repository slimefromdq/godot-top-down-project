@tool
extends AbilityData
class_name PhoenixRebirthData

# Phoenix Rebirth: when Avery would die while this is off cooldown, the death
# is cancelled, she goes through a short rebirth (can't act, can't be hurt),
# then rises with a share of her health and, optionally, a fire burst.
#
# Trigger mode: automatic only for now (passive when ready). An "arm it by
# pressing the key" mode would slot in as an enum here plus an _activate()
# that opens an arming window; the revive itself wouldn't change.
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


func validate() -> PackedStringArray:
	var problems := super()
	if rebirth_state == null:
		problems.append("'%s' has no rebirth_state status" % id)
	if rebirth_duration < 0.0 or invulnerable_after < 0.0:
		problems.append("'%s' rebirth timings are negative" % id)
	if burst_enabled and (hit_shape == null or damage == null):
		problems.append("'%s' burst is enabled but has no hit_shape/damage" % id)
	return problems
