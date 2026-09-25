@tool
extends Resource
class_name ScalingValue

# One tunable number that can scale with level and the caster's stats:
#
#   value = base + per_level * (level - 1)
#         + weapon_ratio * Weapon + magic_ratio * Magic
#
# Every damage, heal, shield and burn tick in the game is one of these, which
# is why the debug panel, stat inspector and CSV export can show any ability's
# numbers without knowing anything about that ability.

@export var base: float = 0.0
@export var per_level: float = 0.0
## Fraction of the caster's Weapon stat added. 0.8 = 80% Weapon.
@export var weapon_ratio: float = 0.0
## Fraction of the caster's Magic stat added.
@export var magic_ratio: float = 0.0


static func make(base_value: float, weapon: float = 0.0, magic: float = 0.0, level_growth: float = 0.0) -> ScalingValue:
	var value := ScalingValue.new()
	value.base = base_value
	value.weapon_ratio = weapon
	value.magic_ratio = magic
	value.per_level = level_growth
	return value


# Evaluate for a caster. A null caster (e.g. a trap with no owner) uses only
# the flat part at level 1.
func evaluate(stats: StatsComponent) -> float:
	if stats == null:
		return base
	return evaluate_at(stats.level, stats.get_weapon(), stats.get_magic())


func evaluate_at(level: int, weapon: float, magic: float) -> float:
	return base + per_level * (level - 1) + weapon_ratio * weapon + magic_ratio * magic


# "40 +5/lvl +80% W +30% M": for tooltips and the stat inspector.
func describe() -> String:
	var parts: Array[String] = ["%s" % _fmt(base)]
	if per_level != 0.0:
		parts.append("%+s/lvl" % _fmt(per_level))
	if weapon_ratio != 0.0:
		parts.append("%+d%% W" % roundi(weapon_ratio * 100.0))
	if magic_ratio != 0.0:
		parts.append("%+d%% M" % roundi(magic_ratio * 100.0))
	return " ".join(parts)


func has_negative() -> bool:
	return base < 0.0 or per_level < 0.0 or weapon_ratio < 0.0 or magic_ratio < 0.0


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.01))
