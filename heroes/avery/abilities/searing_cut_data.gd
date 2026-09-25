@tool
extends MeleeAttackData
class_name SearingCutData

# Searing Cut: a melee slash that heals Avery for each enemy it hits, with
# diminishing returns so a wave of minions can't make her unkillable.
#
# Heal for the Nth target hit by one slash:
#     heal_per_target * falloff^(N - 1)
# e.g. falloff 0.5 -> 100%, 50%, 25%, 12.5% ...
# Stops after max_targets_healed targets, and the whole slash never heals
# more than heal_cap.

@export_group("Healing")
## Heal for the first target hit. Scales with Magic.
@export var heal_per_target: ScalingValue
## Multiplier applied for each additional target (0-1).
@export_range(0.0, 1.0, 0.05) var falloff: float = 0.5
## Targets after this many heal nothing. 0 = no limit.
@export var max_targets_healed: int = 4
## Most one slash can heal in total. Empty = no cap.
@export var heal_cap: ScalingValue
@export var heal_label: StringName = &"searing_cut_heal"


# Heal for the Nth target (1-based), before the total cap.
func heal_for_target(n: int, stats: StatsComponent) -> float:
	if heal_per_target == null or n < 1:
		return 0.0
	if max_targets_healed > 0 and n > max_targets_healed:
		return 0.0
	return heal_per_target.evaluate(stats) * pow(falloff, n - 1)


func get_scaling_values() -> Dictionary:
	var result := super()
	if heal_per_target != null:
		result["heal_per_target"] = heal_per_target
	if heal_cap != null:
		result["heal_cap"] = heal_cap
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if heal_per_target == null:
		problems.append("'%s' has no heal_per_target" % id)
	if max_targets_healed < 0:
		problems.append("'%s' max_targets_healed is negative" % id)
	return problems
