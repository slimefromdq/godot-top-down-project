extends RefCounted
class_name StackCounter

# Per-source, per-target stack counters with a cap, decay and a "full"
# trigger: build a meter on a victim with hits, and when it fills something
# happens (Mochi's Madness explodes). A counter belongs to
# (owner, key, target), so two sources (a hero and her tentacle) keep
# separate counters on the same victim just by using different owners.
#
#   add(owner, key, target, max, decay_after, immunity) -> true when this
#       hit filled it. A full counter resets to 0 and the target is immune
#       (add() does nothing) for `immunity` seconds.
#   A counter with no add() for `decay_after` seconds drops back to 0.
#
# Only the owner reacts to "full": the caller does the burst, so the counter
# stays hero-agnostic. Time is the physics clock (ZoneRamp.now()), so
# results are the same on every machine. Read stacks for HUD marks with
# get_stacks(); is_immune() for "can't build right now".

class Entry:
	var stacks: int = 0
	var last_add: float = -INF
	var immune_until: float = -INF


static var _entries: Dictionary = {}    # key string -> Entry
const _PRUNE_AT := 512
const _PRUNE_AGE := 30.0


static func add(owner_node: Node, key: StringName, target: Node, max_stacks: int,
		decay_after: float, immunity: float, amount: int = 1) -> bool:
	var entry := _entry(owner_node, key, target, true)
	var t := ZoneRamp.now()
	if t < entry.immune_until:
		return false
	if t - entry.last_add > decay_after:
		entry.stacks = 0
	entry.last_add = t
	entry.stacks += amount
	if entry.stacks < max_stacks:
		return false
	entry.stacks = 0
	entry.immune_until = t + immunity
	return true


static func get_stacks(owner_node: Node, key: StringName, target: Node, decay_after: float = INF) -> int:
	var entry := _entry(owner_node, key, target, false)
	if entry == null or ZoneRamp.now() - entry.last_add > decay_after:
		return 0
	return entry.stacks


static func is_immune(owner_node: Node, key: StringName, target: Node) -> bool:
	var entry := _entry(owner_node, key, target, false)
	return entry != null and ZoneRamp.now() < entry.immune_until


static func reset(owner_node: Node, key: StringName, target: Node) -> void:
	_entries.erase(_key(owner_node, key, target))


static func _entry(owner_node: Node, key: StringName, target: Node, create: bool) -> Entry:
	var k := _key(owner_node, key, target)
	var entry: Entry = _entries.get(k)
	if entry == null and create:
		if _entries.size() >= _PRUNE_AT:
			_prune()
		entry = Entry.new()
		_entries[k] = entry
	return entry


static func _key(owner_node: Node, key: StringName, target: Node) -> String:
	var owner_id := owner_node.get_instance_id() if is_instance_valid(owner_node) else 0
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	return "%d:%s:%d" % [owner_id, key, target_id]


static func _prune() -> void:
	var t := ZoneRamp.now()
	for k in _entries.keys():
		var e: Entry = _entries[k]
		if t - maxf(e.last_add, e.immune_until) > _PRUNE_AGE:
			_entries.erase(k)
