@tool
extends Resource
class_name StatModifier

# A change to one stat, e.g. "+30 Weapon" or "+10% Health". Items will be
# lists of these later; nothing creates them yet except tests and the debug
# panel.
#
# Final stat = (level value + sum of flat) * (1 + sum of percent)
# Modifiers never overwrite the base, so removing one always restores the
# original value exactly.

@export var stat: StringName = StatBlock.WEAPON
@export var flat: float = 0.0
## 0.1 = +10%.
@export var percent: float = 0.0
## Who added this (an item id, a buff id). remove_modifiers_from() uses it.
@export var source_id: StringName


static func make(stat_id: StringName, flat_amount: float, percent_amount: float = 0.0, source: StringName = &"") -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat_id
	modifier.flat = flat_amount
	modifier.percent = percent_amount
	modifier.source_id = source
	return modifier
