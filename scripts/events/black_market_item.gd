@tool
extends Resource
class_name BlackMarketItem

# One Black Market product (embedded in resources/rules/map_events.tres). A
# temporary buff: it costs carried Motes AND gold, takes no item slot, and is
# lost on death or when its timer ends.
#
# Like a StatusEffect it is a bundle of optional parts:
#   status        a StatusEffect applied for the item's duration (multipliers,
#                 stat modifiers, invisibility ...): Overclock, Glass Cannon
#                 and Mote Magnet's pickup radius are only this.
#   effect        a TempEffect script for what a status can't do (a dash, a
#                 Mote pull, an instant heal). Its numbers are in `values`.
#   duration      seconds the buff lasts; 0 = MapEventRules.blackmarket_item_duration.
#                 An instant item (Second Wind) ignores it.

@export var id: StringName = &"item"
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var glyph: String = "?"
@export var color: Color = Color("fbd34d")
## Motes taken from the buyer's CARRIED stack (never banked, never a Dream Mote).
@export var mote_cost: int = 2
@export var gold_cost: int = 300
@export var duration: float = 0.0
@export var status: StatusEffect
@export var effect: Script
## Numbers for the effect script (dash_distance, pull_radius, heal_pct ...).
@export var values: Dictionary[StringName, float] = {}
## Bots buy the affordable item with the highest priority (ties: stock order).
@export var bot_priority: int = 0


func value_of(key: StringName, fallback: float = 0.0) -> float:
	return values.get(key, fallback)


## The effect object for one purchase (a TempEffect; the base one just applies
## the status).
func make_effect() -> TempEffect:
	if effect != null:
		var made = effect.new()
		if made is TempEffect:
			return made
	return TempEffect.new()


func describe() -> String:
	var lines: Array[String] = []
	if status != null:
		for stat in status.stat_multipliers:
			var mult: float = status.stat_multipliers[stat]
			lines.append("%+d%% %s" % [roundi((mult - 1.0) * 100.0), str(stat).replace("_", " ")])
		for modifier in status.stat_modifiers:
			if modifier != null:
				lines.append("%+d%% max %s" % [roundi(modifier.percent * 100.0), str(modifier.stat).replace("_", " ")])
	if description != "":
		lines.append(description)
	return "\n".join(lines)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("black market item has no id")
	if mote_cost < 0 or gold_cost < 0 or duration < 0.0:
		problems.append("black market item '%s' has negative costs or duration" % id)
	if status == null and effect == null:
		problems.append("black market item '%s' does nothing (no status, no effect)" % id)
	if status != null:
		for problem in status.validate():
			problems.append("black market item '%s': %s" % [id, problem])
	if effect != null:
		var probe = effect.new()
		if not probe is TempEffect:
			problems.append("black market item '%s' effect is not a TempEffect" % id)
	return problems
