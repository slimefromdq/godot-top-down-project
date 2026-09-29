extends Node
class_name MoteLedger

# Where the match's Motes come from. Every system that makes Motes tags them
# with a source (Mote.spawn's mote_source); the tag rides along while the Mote
# is carried and dropped. The ledger counts, per source:
#
#   spawned    Motes made (count and value), the moment they appear
#   banked     value put into the depositor's OWN Dreamer
#   delivered  value put into the ENEMY Dreamer (fills the wake meter)
#   spent      value paid at the Black Market (gone from the economy)
#
# so "does the Wanderer overshadow the trickle?" is one look at report().
# It is passive: it never changes a Mote, a deposit or a rule. A child of the
# MapEvents node; found with MoteLedger.find(tree). Untagged Motes (debug
# spawns) are not counted.

const GROUP := &"mote_ledger"
const TRICKLE := &"trickle"
const ZONE := &"zone"
const DREAM := &"dream"
const NEUTRAL := &"neutral"
const GEYSER := &"geyser"
const ISLAND := &"island"
const WANDERER := &"wanderer"
## Report order.
const SOURCES: Array[StringName] = [TRICKLE, ZONE, DREAM, NEUTRAL, GEYSER, ISLAND, WANDERER]
## The new systems (everything else is the base economy).
const EVENT_SOURCES: Array[StringName] = [ISLAND, WANDERER]

signal changed

var _rows: Dictionary = {}    # source -> {spawned, spawned_value, banked, delivered, spent}


static func find(tree: SceneTree) -> MoteLedger:
	return tree.get_first_node_in_group(GROUP) as MoteLedger if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func reset() -> void:
	_rows.clear()
	changed.emit()


func record_spawn(source: StringName, value: int) -> void:
	var row := _row(source)
	row.spawned += 1
	row.spawned_value += value
	changed.emit()


func record_deposit(source: StringName, value: int, delivered: bool) -> void:
	if source == &"":
		return
	_row(source)["delivered" if delivered else "banked"] += value
	changed.emit()


func record_spent(source: StringName, value: int) -> void:
	if source == &"":
		return
	_row(source).spent += value
	changed.emit()


func get_row(source: StringName) -> Dictionary:
	return _row(source).duplicate()


func get_total(field: String) -> int:
	var total := 0
	for row in _rows.values():
		total += int(row[field])
	return total


## Share (0..1) of all deposited value that came from `source`.
func deposited_share(source: StringName) -> float:
	var all := get_total("banked") + get_total("delivered")
	var row := _row(source)
	return float(row.banked + row.delivered) / all if all > 0 else 0.0


## Deposited value from the new event sources / all deposited value.
func event_share() -> float:
	var share := 0.0
	for source in EVENT_SOURCES:
		share += deposited_share(source)
	return share


func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%-9s %7s %7s %7s %9s %7s %6s" % ["source", "spawned", "value", "banked", "delivered", "spent", "share"])
	var names: Array = SOURCES.duplicate()
	for source in _rows:
		if not names.has(source):
			names.append(source)
	for source in names:
		var row := _row(source)
		lines.append("%-9s %7d %7d %7d %9d %7d %5.1f%%" % [source, row.spawned, row.spawned_value,
			row.banked, row.delivered, row.spent, deposited_share(source) * 100.0])
	return lines


func report() -> String:
	return "\n".join(report_lines())


## CSV of the table (source,spawned,spawned_value,banked,delivered,spent).
func to_csv() -> String:
	var out := "source,spawned,spawned_value,banked,delivered,spent\n"
	for source in SOURCES:
		var row := _row(source)
		out += "%s,%d,%d,%d,%d,%d\n" % [source, row.spawned, row.spawned_value, row.banked, row.delivered, row.spent]
	return out


func _row(source: StringName) -> Dictionary:
	if not _rows.has(source):
		_rows[source] = {"spawned": 0, "spawned_value": 0, "banked": 0, "delivered": 0, "spent": 0}
	return _rows[source]
