extends Node
class_name StatsComponent

# Current level plus the stats computed from a StatBlock at that level.
#
# Everything that depends on a stat asks this component (get_stat) instead of
# caching numbers, so a level-up or an item takes effect everywhere at once.
# Listeners that do cache (HealthComponent's max HP) watch stats_changed.

signal stats_changed
signal level_changed(level: int)

@export var stat_block: StatBlock
@export_range(1, 20) var level: int = 1

var _modifiers: Array[StatModifier] = []


func _ready() -> void:
	if stat_block == null:
		stat_block = StatBlock.new()
	level = clampi(level, 1, get_max_level())


func get_max_level() -> int:
	return GameRules.current().max_level


func get_stat(stat: StringName) -> float:
	var value := stat_block.value_at(stat, level) if stat_block != null else 0.0
	var flat := 0.0
	var percent := 0.0
	for modifier in _modifiers:
		if modifier.stat == stat:
			flat += modifier.flat
			percent += modifier.percent
	return (value + flat) * (1.0 + percent)


# Shortcuts for the three core stats. ScalingValue formulas use these.
func get_health() -> float:
	return get_stat(StatBlock.HEALTH)


func get_weapon() -> float:
	return get_stat(StatBlock.WEAPON)


func get_magic() -> float:
	return get_stat(StatBlock.MAGIC)


func level_up() -> void:
	set_level(level + 1)


# Clamped to the match level cap. Returns without signals if nothing changed.
func set_level(new_level: int) -> void:
	new_level = clampi(new_level, 1, get_max_level())
	if new_level == level:
		return
	level = new_level
	level_changed.emit(level)
	stats_changed.emit()


# Item hook. Items (later) add a batch of modifiers tagged with their id and
# remove them all by that id when sold.
func add_modifier(modifier: StatModifier) -> void:
	_modifiers.append(modifier)
	stats_changed.emit()


func remove_modifier(modifier: StatModifier) -> void:
	_modifiers.erase(modifier)
	stats_changed.emit()


func remove_modifiers_from(source_id: StringName) -> void:
	var before := _modifiers.size()
	_modifiers = _modifiers.filter(func(m: StatModifier): return m.source_id != source_id)
	if _modifiers.size() != before:
		stats_changed.emit()


func get_modifiers() -> Array[StatModifier]:
	return _modifiers.duplicate()


# Find the StatsComponent that belongs to any node (actor, dummy, ...), or null.
static func find_on(node: Node) -> StatsComponent:
	if node == null or not is_instance_valid(node):
		return null
	if node is StatsComponent:
		return node
	var direct := node.get_node_or_null(^"Components/StatsComponent")
	return direct as StatsComponent
