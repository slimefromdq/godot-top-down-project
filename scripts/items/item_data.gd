@tool
extends Resource
class_name ItemData

# One shop item (resources/items/*.tres), listed in a ShopCatalog.
#
# An item is data only:
#   * stat_modifiers    StatModifiers on the owner's StatsComponent (+150
#                       Health, +25 Magic, +10% Health ...)
#   * stat_multipliers  always-on multipliers, keyed like a StatusEffect's
#                       (fire_rate, move_speed, damage, damage_taken,
#                       cooldown_rate ...): 1.15 = +15%
#   * active_ability    an AbilityData: the item is an ACTIVE item and its
#                       ability goes in the hero's "item" slot. A hero holds
#                       at most one active item (MatchRules.max_active_items).
#
# Tiers are price bands (cheap, medium, expensive). builds_from makes an
# upgrade path: owning that item takes its cost off the price, and buying
# this one uses it up. ItemInventory applies and removes everything; the
# numbers in describe() come from the data, so tooltips can't go stale.

enum Tier { CHEAP, MEDIUM, EXPENSIVE }

const TIER_NAMES := ["Cheap", "Medium", "Expensive"]
## Display names for the stat_multipliers keys items use.
const MULTIPLIER_NAMES := {
	&"fire_rate": "Fire rate",
	&"move_speed": "Move speed",
	&"damage": "Damage",
	&"damage_taken": "Damage taken",
	&"cooldown_rate": "Cooldown speed",
}
const STAT_NAMES := {
	&"health": "Health",
	&"weapon": "Weapon",
	&"magic": "Magic",
	&"armor": "Armor",
	&"magic_resist": "Magic Resist",
}

@export var id: StringName = &"item"
@export var display_name: String = "Item"
## Flavour line shown under the numbers.
@export_multiline var description: String = ""
@export var tier: Tier = Tier.CHEAP
## Groups items into rows in the shop (health, fire_rate, magic, active ...).
@export var family: StringName = &""
## Full price in gold.
@export var cost: int = 300
## Owning this item takes its cost off the price, and buying uses it up.
@export var builds_from: ItemData

@export_group("Passive")
@export var stat_modifiers: Array[StatModifier] = []
## Keyed like StatusEffect.stat_multipliers (fire_rate, move_speed ...).
@export var stat_multipliers: Dictionary[StringName, float] = {}

@export_group("Active")
## Makes this an active item: the ability goes in the "item" slot.
@export var active_ability: AbilityData

@export_group("Look")
## The shop button's gel colour.
@export var color: Color = Color("7dd3fc")
## One or two characters drawn on the icon.
@export var glyph: String = "?"


func is_active() -> bool:
	return active_ability != null


func get_tier_name() -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]


# "+150 Health, +12% Fire rate, Active: Pocket Overdrive (45 s)" built from
# the real numbers.
func describe_stats() -> PackedStringArray:
	var lines := PackedStringArray()
	for modifier in stat_modifiers:
		if modifier == null:
			continue
		var stat_name: String = STAT_NAMES.get(modifier.stat, str(modifier.stat))
		if modifier.flat != 0.0:
			lines.append("%+d %s" % [roundi(modifier.flat), stat_name])
		if modifier.percent != 0.0:
			lines.append("%+d%% %s" % [roundi(modifier.percent * 100.0), stat_name])
	for key in stat_multipliers:
		var key_name: String = MULTIPLIER_NAMES.get(key, str(key))
		lines.append("%+d%% %s" % [roundi((stat_multipliers[key] - 1.0) * 100.0), key_name])
	if active_ability != null:
		lines.append("Active: %s (%d s)" % [active_ability.display_name, roundi(active_ability.cooldown)])
	return lines


func describe() -> String:
	var text := "\n".join(describe_stats())
	if active_ability != null and active_ability.description != "":
		text += "\n" + active_ability.description
	if description != "":
		text += "\n" + description
	if builds_from != null:
		text += "\nBuilds from %s." % builds_from.display_name
	return text


# Problems a designer should fix. Empty = fine.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("item has no id")
	if cost < 0:
		problems.append("item '%s' has a negative cost" % id)
	if builds_from != null:
		if builds_from == self:
			problems.append("item '%s' builds from itself" % id)
		elif builds_from.cost > cost:
			problems.append("item '%s' costs less than its component '%s'" % [id, builds_from.id])
	for i in stat_modifiers.size():
		var modifier := stat_modifiers[i]
		if modifier == null:
			problems.append("item '%s' stat modifier %d is empty" % [id, i + 1])
		elif not StatBlock.ALL.has(modifier.stat):
			problems.append("item '%s' stat modifier %d has unknown stat '%s'" % [id, i + 1, modifier.stat])
	for key in stat_multipliers:
		if stat_multipliers[key] <= 0.0:
			problems.append("item '%s' multiplier '%s' must be above 0" % [id, key])
	if active_ability != null:
		if active_ability.ability_script == null:
			problems.append("item '%s' active ability has no script" % id)
		for problem in active_ability.validate():
			problems.append("item '%s' active: %s" % [id, problem])
	return problems
