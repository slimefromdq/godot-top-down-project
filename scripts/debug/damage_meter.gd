extends Node
class_name DamageMeter

# Records what the tracked actor (the local player by default) deals, takes
# and heals, for the damage-meter overlay. Pure observer: it listens to the
# global CombatEvents feed and never touches gameplay.
#
# "Source" in the breakdown is the DamageInfo label: blade, crescent, burn,
# fire_trail, searing_cut, dawnbreaker, phoenix_burst ... so blade vs.
# crescent vs. burn vs. abilities falls straight out of the data.
#
# DPS is over a rolling window: damage in the last `window` seconds divided by
# the time actually spent fighting inside that window (so a 2-second burst
# isn't diluted by 3 idle seconds).

signal changed

## Rolling DPS window in seconds.
@export var window: float = 5.0

## Who we're measuring. Empty = whoever is in the "player" group.
var tracked: Node

var _dealt: Array[Dictionary] = []     # {t, amount, label, target}
var _taken: Array[Dictionary] = []     # {t, amount, label}
var _healed: Array[Dictionary] = []    # {t, amount, label}
var _started_at: float = 0.0


func _ready() -> void:
	CombatEvents.damage_dealt.connect(_on_damage)
	CombatEvents.heal_done.connect(_on_heal)
	reset()


func reset() -> void:
	_dealt.clear()
	_taken.clear()
	_healed.clear()
	_started_at = _now()
	changed.emit()


func get_tracked() -> Node:
	if tracked != null and is_instance_valid(tracked):
		return tracked
	return get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null


func get_total_dealt() -> float:
	return _sum(_dealt)


func get_total_taken() -> float:
	return _sum(_taken)


func get_total_healed() -> float:
	return _sum(_healed)


func get_elapsed() -> float:
	return _now() - _started_at


# Damage per second over the rolling window.
func get_dps() -> float:
	var now := _now()
	var recent := _dealt.filter(func(e): return now - e.t <= window)
	if recent.is_empty():
		return 0.0
	var span := maxf(now - recent[0].t, 1.0)
	return _sum(recent) / minf(span, window)


# [{label, total, hits, share}] sorted biggest first.
func get_dealt_breakdown() -> Array[Dictionary]:
	return _breakdown(_dealt)


func get_healing_breakdown() -> Array[Dictionary]:
	return _breakdown(_healed)


func get_taken_breakdown() -> Array[Dictionary]:
	return _breakdown(_taken)


func _on_damage(info: DamageInfo) -> void:
	var me := get_tracked()
	if me == null or info.final_amount <= 0.0:
		return
	if info.source == me:
		_dealt.append({"t": _now(), "amount": info.final_amount, "label": _label(info.label), "target": info.target})
		changed.emit()
	elif info.target == me:
		_taken.append({"t": _now(), "amount": info.final_amount, "label": _label(info.label)})
		changed.emit()


func _on_heal(amount: float, _source: Node, target: Node, label: StringName) -> void:
	if target != get_tracked() or amount <= 0.0:
		return
	_healed.append({"t": _now(), "amount": amount, "label": _label(label)})
	changed.emit()


func _breakdown(events: Array[Dictionary]) -> Array[Dictionary]:
	var by_label := {}
	for e in events:
		var row: Dictionary = by_label.get_or_add(e.label, {"label": e.label, "total": 0.0, "hits": 0})
		row.total += e.amount
		row.hits += 1
	var total := maxf(_sum(events), 0.0001)
	var rows: Array[Dictionary] = []
	for row in by_label.values():
		row["share"] = row.total / total
		rows.append(row)
	rows.sort_custom(func(a, b): return a.total > b.total)
	return rows


static func _sum(events: Array) -> float:
	var total := 0.0
	for e in events:
		total += e.amount
	return total


static func _label(label: StringName) -> StringName:
	return label if label != &"" else &"other"


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
