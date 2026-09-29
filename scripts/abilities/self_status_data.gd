@tool
extends AbilityData
class_name SelfStatusData

# Data for SelfStatusAbility: put a status on yourself (a shield, a speed
# burst, a damage-resist stance), optionally stronger for every enemy nearby.
#
#   strength = strength_base + strength_per_enemy x enemies within count_radius
#
# (enemies counted up to max_enemies_counted). The strength scales the
# status's shield and how far its stat multipliers move from 1.0, exactly
# like StatusEffectComponent.apply(..., strength). So a shield of 150 at
# strength 1 + 0.35 per enemy is 150 alone and 307.5 with three enemies
# around. Timing (windup/recovery) comes from the feel preset; the status
# lands when the active phase starts.

@export_group("Self status")
## Applied to the caster.
@export var self_status: StatusEffect
## Strength with no enemies around.
@export var strength_base: float = 1.0
## Added per enemy within count_radius.
@export var strength_per_enemy: float = 0.0
## Pixels around the caster in which enemies are counted.
@export var count_radius: float = 450.0
## Most enemies that count. 0 = no cap.
@export var max_enemies_counted: int = 0
## Count only enemy heroes (the "heroes" group), not minions or dummies.
@export var count_heroes_only: bool = false
## Keep the status only while the key is held (a scope, a stance): released
## = removed. The status's duration caps the hold.
@export var hold_to_keep: bool = false
## hold_to_keep only: a meter (0..1) that drains while held and refills
## while released: hold_meter_seconds of use from full (0 = no meter),
## hold_meter_recharge_seconds from empty to full. Empty ends the hold; a
## hold needs hold_meter_min to start. Shown on the ability bar.
@export var hold_meter_seconds: float = 0.0
@export var hold_meter_recharge_seconds: float = 5.0
@export_range(0.0, 1.0, 0.01) var hold_meter_min: float = 0.1
## hold_to_keep only: while held, drop this zone behind the caster every
## hold_trail_spacing px travelled (a flame trail).
@export var hold_trail_zone: GroundZoneData
@export var hold_trail_spacing: float = 60.0


func get_strength(enemies: int) -> float:
	if max_enemies_counted > 0:
		enemies = mini(enemies, max_enemies_counted)
	return strength_base + strength_per_enemy * enemies


func get_range() -> float:
	return ability_range if ability_range > 0.0 else count_radius


func get_scaling_values() -> Dictionary:
	var result := super()
	if self_status != null and self_status.shield_amount != null:
		result["self_status/shield_amount"] = self_status.shield_amount
	return result


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	if self_status == null:
		return {}
	var metrics := {"status_duration": self_status.duration, "strength_alone": get_strength(0)}
	if hold_meter_seconds > 0.0:
		metrics["hold_meter_seconds"] = hold_meter_seconds
		metrics["hold_meter_recharge_seconds"] = hold_meter_recharge_seconds
	if max_enemies_counted > 0:
		metrics["strength_max"] = get_strength(max_enemies_counted)
	return metrics


func validate() -> PackedStringArray:
	var problems := super()
	if self_status == null:
		problems.append("'%s' has no self_status" % id)
	else:
		for problem in self_status.validate():
			problems.append("'%s' self_status: %s" % [id, problem])
	if hold_meter_seconds < 0.0 or hold_meter_recharge_seconds < 0.0 or hold_trail_spacing <= 0.0:
		problems.append("'%s' has invalid hold meter/trail values" % id)
	if hold_trail_zone != null:
		for problem in hold_trail_zone.validate():
			problems.append("'%s' hold_trail_zone: %s" % [id, problem])
	if strength_base < 0.0 or strength_per_enemy < 0.0 or count_radius < 0.0 or max_enemies_counted < 0:
		problems.append("'%s' has negative strength/radius/count" % id)
	return problems
