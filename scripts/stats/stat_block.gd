@tool
extends Resource
class_name StatBlock

# A hero's (or dummy's) level-scaled stats in one resource.
#
# Health, Weapon and Magic are the three core stats. Weapon scales physical /
# basic-attack damage, Magic scales ability damage, healing and effects; both
# are read by ScalingValue formulas. Armor and Magic Resist reduce incoming
# physical / magic damage (see GameRules.resistance_multiplier).

const HEALTH := &"health"
const WEAPON := &"weapon"
const MAGIC := &"magic"
const ARMOR := &"armor"
const MAGIC_RESIST := &"magic_resist"

## Every stat id, in display / export order.
const ALL: Array[StringName] = [HEALTH, WEAPON, MAGIC, ARMOR, MAGIC_RESIST]

@export var health: StatScaling = StatScaling.make(600.0, 60.0)
@export var weapon: StatScaling = StatScaling.make(40.0, 4.0)
@export var magic: StatScaling = StatScaling.make(20.0, 4.0)
@export var armor: StatScaling = StatScaling.make(0.0)
@export var magic_resist: StatScaling = StatScaling.make(0.0)


func get_scaling(stat: StringName) -> StatScaling:
	match stat:
		HEALTH: return health
		WEAPON: return weapon
		MAGIC: return magic
		ARMOR: return armor
		MAGIC_RESIST: return magic_resist
	return null


func value_at(stat: StringName, level: int) -> float:
	var scaling := get_scaling(stat)
	return scaling.value_at(level) if scaling != null else 0.0
