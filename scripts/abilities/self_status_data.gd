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
	if strength_base < 0.0 or strength_per_enemy < 0.0 or count_radius < 0.0 or max_enemies_counted < 0:
		problems.append("'%s' has negative strength/radius/count" % id)
	return problems
