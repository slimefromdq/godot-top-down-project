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
#
# Hold-to-charge: any ability can opt in with the "Charge" group. The cast
# then starts in a CHARGING phase (see Ability) and waits for a release.
# Charged numbers are pairs of named values, `key` and `key_full`, read with
# get_charged_value(), so they stay ordinary inspectable ScalingValues.

## What a charge released before charge_min_to_fire does.
enum ChargeBelowMin {
	CANCEL,         ## Nothing fires and no cooldown is spent.
	FIRE_MINIMUM,   ## Fires as if charged to exactly charge_min_to_fire.
}

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

@export_group("Charge")
## Hold to charge, release to fire. The cast waits in a CHARGING phase until
## the hero releases the slot (Hero.release_slot), then runs as usual.
@export var charge_enabled: bool = false
## Seconds of holding for a full charge (ratio 1).
@export var charge_time_max: float = 1.0
## Seconds of holding needed before a release counts.
@export var charge_min_to_fire: float = 0.0
## What a release before charge_min_to_fire does.
@export var charge_below_min: ChargeBelowMin = ChargeBelowMin.CANCEL
## Fire by itself the moment the charge is full. Auto releases never count
## as "perfect".
@export var charge_auto_release_at_max: bool = false
## Walking speed multiplier while charging (1 = no slow).
@export_range(0.0, 1.0, 0.05) var charge_move_speed_multiplier: float = 0.6
## Another ability's key cancels the charge without spending the cooldown
## (that ability then starts). Off = the charge can only end by releasing.
@export var charge_can_cancel: bool = true
## Seconds after reaching full charge during which a release is "perfect".
## 0 = no perfect window.
@export var charge_perfect_window: float = 0.0

@export_group("Feel")
## Preset in the hero's FeelProfile (light, heavy, finisher ...).
@export var feel_preset: StringName = &"light"
## Overrides the preset entirely when set.
@export var feel_override: AttackFeel


func get_value(key: StringName, stats: StatsComponent) -> float:
	var value: ScalingValue = values.get(key)
	return value.evaluate(stats) if value != null else 0.0


# A charged number: lerps from the named value `key` (ratio 0) to `key_full`
# (ratio 1). `key` may also be "damage", meaning the main damage field. With
# no `key_full`, the charge doesn't change the number.
func get_charged_value(key: StringName, stats: StatsComponent, ratio: float) -> float:
	var low := _scaling_for(key)
	var low_value := low.evaluate(stats) if low != null else 0.0
	var high: ScalingValue = values.get(StringName(str(key) + "_full"))
	if high == null:
		return low_value
	return lerpf(low_value, high.evaluate(stats), clampf(ratio, 0.0, 1.0))


func _scaling_for(key: StringName) -> ScalingValue:
	if values.has(key):
		return values[key]
	return damage if key == &"damage" else null


# Charge ratio a release below the minimum fires at (FIRE_MINIMUM).
func get_min_charge_ratio() -> float:
	return clampf(charge_min_to_fire / charge_time_max, 0.0, 1.0) if charge_time_max > 0.0 else 0.0


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


# Extra derived numbers for the balance CSV that aren't ScalingValues (fire
# rate, magazine, effective DPS ...), at a level and the hero's stats there.
# Subclasses override; keys become the CSV "metric" column.
func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {}


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
	if charge_enabled:
		if charge_time_max <= 0.0:
			problems.append("'%s' charge_time_max must be above 0" % id)
		if charge_min_to_fire < 0.0 or charge_perfect_window < 0.0 or charge_move_speed_multiplier < 0.0:
			problems.append("'%s' has negative charge settings" % id)
		elif charge_min_to_fire > charge_time_max:
			problems.append("'%s' charge_min_to_fire is longer than charge_time_max" % id)
	if on_hit_status != null:
		for problem in on_hit_status.validate():
			problems.append("'%s' on_hit_status: %s" % [id, problem])
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
