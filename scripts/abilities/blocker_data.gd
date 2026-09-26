@tool
extends AbilityData
class_name BlockerData

# Data for BlockerAbility: hold to raise a FrontalBlocker (a cloak, a shield)
# on the aim arc; release to lower it. See FrontalBlocker for the rules.

@export_group("Blocker")
## The blocker's HP, from the caster's stats (level scaling).
@export var blocker_hp: ScalingValue
@export var radius: float = 110.0
@export var arc_degrees: float = 120.0
## Fraction of max HP regained per second while lowered.
@export var regen_per_second: float = 0.2
## Seconds after lowering or breaking before it regenerates.
@export var regen_delay: float = 1.0
## After breaking, it can be raised again at this fraction of max HP.
@export_range(0.0, 1.0, 0.05) var min_raise_ratio: float = 0.2
## Kept on the caster while raised (a slow).
@export var raised_status: StatusEffect
## Put on the caster when they lower it by letting go (not when it breaks).
@export var lowered_status: StatusEffect
## Slots that may still be used while it's up. Every other slot is refused
## ("Channeling"); quiet_slots_while_raised are refused silently.
@export var allowed_slots_while_raised: Array[StringName] = [&"movement", &"ultimate"]
@export var quiet_slots_while_raised: Array[StringName] = [&"primary"]
@export var color: Color = Color(0.55, 0.05, 0.12, 0.55)


func get_range() -> float:
	return ability_range if ability_range > 0.0 else radius


func get_scaling_values() -> Dictionary:
	var result := super()
	if blocker_hp != null:
		result["blocker_hp"] = blocker_hp
	return result


func validate() -> PackedStringArray:
	var problems := super()
	if blocker_hp == null:
		problems.append("'%s' has no blocker_hp" % id)
	elif blocker_hp.has_negative():
		problems.append("'%s' blocker_hp has negative numbers" % id)
	if radius <= 0.0 or arc_degrees <= 0.0 or regen_per_second < 0.0 or regen_delay < 0.0:
		problems.append("'%s' blocker needs a positive radius/arc and non-negative regen" % id)
	return problems
