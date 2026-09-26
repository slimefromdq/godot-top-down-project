extends RefCounted
class_name ZoneRamp

# Per-target damage ramp for ground zones (GroundZoneData Ramp group): the
# longer a target stays in the gas, the harder each tick hits.
#
# A ramp belongs to (owner, ramp_key, target). Every zone with the same owner
# and key shares it, so a hero's aura, thrown clouds and leftovers all feed
# one ramp per victim. It counts STEPS: each damage tick on the target adds
# one after it lands, and a tick's multiplier is
#   min(1 + ramp_per_tick * steps, ramp_max)
# so the first tick is x1. A target that has been outside every such zone for
# ramp_reset_after seconds starts again from 0 steps.
#
# Abilities can push a ramp directly: raise_steps() (a hit that starts the
# victim "one step higher"), reset() (a cleanse). Time is the physics clock,
# so results are the same on every machine.

class Entry:
	var steps: int = 0
	var last_seen: float = -INF    # physics time the target was last inside / pushed


static var _entries: Dictionary = {}    # key string -> Entry
const _PRUNE_AT := 512
const _PRUNE_AGE := 30.0


# Ramps are kept per actor, not per hurtbox, so zones and direct hits agree.
static func target_of(hurtbox: Node) -> Node:
	if not is_instance_valid(hurtbox):
		return null
	return hurtbox.owner if hurtbox.owner != null else hurtbox.get_parent()


static func now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


# The target is inside a ramping zone this physics tick. Starts the ramp over
# if it was outside for longer than `reset_after`.
static func touch(owner_node: Node, key: StringName, target: Node, reset_after: float) -> void:
	var entry := _entry(owner_node, key, target, true)
	var t := now()
	if t - entry.last_seen > reset_after:
		entry.steps = 0
	entry.last_seen = t


static func get_steps(owner_node: Node, key: StringName, target: Node) -> int:
	var entry := _entry(owner_node, key, target, false)
	return entry.steps if entry != null else 0


static func multiplier(owner_node: Node, key: StringName, target: Node, per_tick: float, max_multiplier: float) -> float:
	return minf(1.0 + per_tick * get_steps(owner_node, key, target), maxf(max_multiplier, 1.0))


# One damage tick landed: the next one hits a step harder.
static func add_step(owner_node: Node, key: StringName, target: Node) -> void:
	var entry := _entry(owner_node, key, target, true)
	entry.steps += 1
	entry.last_seen = now()


# At least `steps` steps from now on (a head start, or "full ramp at once").
static func raise_steps(owner_node: Node, key: StringName, target: Node, steps: int) -> void:
	var entry := _entry(owner_node, key, target, true)
	entry.steps = maxi(entry.steps, steps)
	entry.last_seen = now()


# Steps needed to reach `max_multiplier` (the "full ramp" of a zone).
static func steps_to_max(per_tick: float, max_multiplier: float) -> int:
	return ceili((max_multiplier - 1.0) / per_tick - 0.0001) if per_tick > 0.0 else 0


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
	var t := now()
	for k in _entries.keys():
		if t - _entries[k].last_seen > _PRUNE_AGE:
			_entries.erase(k)
