@tool
extends Resource
class_name AbilityData

# Every tunable number of one ability, plus which script runs it.
#
# A hero's HeroDefinition maps slot -> AbilityData, and the Hero creates a node
# from `ability_script` for each. So adding an ability to a hero is a data
# edit, and most abilities reuse a generic script (MeleeAttackAbility,
# ChargeAbility ...) with different numbers.
#
# Named values: `values` holds any extra ScalingValues an ability needs
# ("damage", "heal", "burst_damage"...). Scripts read them with get_value().
# Because they're all ScalingValues, the debug panel, stat inspector and CSV
# export can show every number of every ability without special cases.
#
# Abilities with structured data (combo steps, revive settings) use a small
# subclass, e.g. MeleeAttackData.

@export var id: StringName = &"ability"
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export var icon: Texture2D
## The Ability script that runs this. Must extend Ability.
@export var ability_script: Script

@export_group("Cooldown and cost")
@export var cooldown: float = 5.0
## Added per level above 1. Negative = shorter cooldown at higher levels.
@export var cooldown_per_level: float = 0.0
## Cost hook for a future resource system (mana, heat...). Nothing spends it
## yet; see Ability._pay_cost().
@export var cost: float = 0.0
@export var cost_type: StringName = &""

@export_group("Hit")
## Area covered. Melee abilities use it; others may ignore it.
@export var hit_shape: HitShape
## Main damage number.
@export var damage: ScalingValue
@export var damage_type: DamageInfo.Type = DamageInfo.Type.PHYSICAL
## Knockback impulse on hit (pixels/second added to the target's velocity).
@export var knockback: float = 0.0
## Status applied on hit (stun, slow, burn, knockback, pull...).
@export var on_hit_status: StatusEffect
## Tags added to every DamageInfo (melee, ability, basic_attack...).
@export var tags: Array[StringName] = []
## Damage-meter label. Empty = the ability id.
@export var meter_label: StringName = &""

@export_group("Numbers")
## Range for targeting/AI. 0 = derive from hit_shape.
@export var ability_range: float = 0.0
## Any extra named numbers the ability script reads.
@export var values: Dictionary[StringName, ScalingValue] = {}

@export_group("Feel")
## Preset in the hero's FeelProfile (light, heavy, finisher ...).
@export var feel_preset: StringName = &"light"
## Overrides the preset entirely when set.
@export var feel_override: AttackFeel


func get_value(key: StringName, stats: StatsComponent) -> float:
	var value: ScalingValue = values.get(key)
	return value.evaluate(stats) if value != null else 0.0


func get_cooldown(level: int) -> float:
	return maxf(cooldown + cooldown_per_level * (level - 1), 0.0)


func get_range() -> float:
	if ability_range > 0.0:
		return ability_range
	return hit_shape.get_reach() if hit_shape != null else 0.0


func get_label() -> StringName:
	return meter_label if meter_label != &"" else id


# Every ScalingValue in this ability, by a readable path ("damage",
# "values/heal", "combo_steps/2/damage"). Tools iterate this; subclasses with
# nested data extend it.
func get_scaling_values() -> Dictionary:
	var result := {}
	if damage != null:
		result["damage"] = damage
	for key in values:
		result["values/%s" % key] = values[key]
	return result


# Problems a designer should fix. Empty = fine. Used by the editor validator.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("has no id")
	if ability_script == null:
		problems.append("'%s' has no ability_script" % id)
	elif not _script_extends_ability(ability_script):
		problems.append("'%s' ability_script doesn't extend Ability" % id)
	if cooldown < 0.0 or cost < 0.0 or ability_range < 0.0 or knockback < 0.0:
		problems.append("'%s' has a negative cooldown/cost/range/knockback" % id)
	if hit_shape != null and hit_shape.has_negative():
		problems.append("'%s' hit_shape has negative values" % id)
	if feel_override != null and feel_override.has_negative():
		problems.append("'%s' feel_override has negative timings" % id)
	var scaling := get_scaling_values()
	for path in scaling:
		if scaling[path] == null:
			problems.append("'%s' %s is empty" % [id, path])
		elif scaling[path].has_negative():
			problems.append("'%s' %s has negative numbers" % [id, path])
	return problems


static func _script_extends_ability(script: Script) -> bool:
	var current := script
	while current != null:
		if current.get_global_name() == &"Ability":
			return true
		current = current.get_base_script()
	return false
