extends Node
class_name StatusEffectComponent

# Holds the buffs and debuffs currently on an actor. Other components ask it
# for multipliers and CC state instead of being edited directly, so an effect
# ending always restores the original values.

signal status_applied(effect: StatusEffect)
signal status_removed(effect: StatusEffect)
## A stun landed. AbilityController listens to interrupt the current cast.
signal stunned(effect: StatusEffect)

## Optional. Needed for displacement (knockback / pull).
@export var movement_component: MovementComponent
## Optional. Needed for damage over time.
@export var health_component: HealthComponent

const TICK_EPSILON := 0.0001

# id -> Entry
var _active: Dictionary = {}


func _ready() -> void:
	# Older scenes don't wire these; find the siblings so they still work.
	var root := _get_root()
	if movement_component == null:
		movement_component = VisualsComponent._find_child_of_type(root, "MovementComponent")
	if health_component == null:
		health_component = VisualsComponent._find_child_of_type(root, "HealthComponent")


class Entry:
	var effect: StatusEffect
	var time_left: float
	var stacks: int = 1
	var source: Node
	# Snapshot of one tick's damage per stack, from the applier's stats.
	var tick_amount: float = 0.0
	var tick_timer: float = 0.0


# `source` is who applied it (for DoT kill credit and snapshotting their
# stats); `direction` is the hit direction (for ALONG_HIT displacement).
func apply(effect: StatusEffect, source: Node = null, direction: Vector2 = Vector2.ZERO) -> void:
	if effect == null:
		return
	var entry: Entry = _active.get(effect.id)
	var is_new := entry == null
	if is_new:
		entry = Entry.new()
		entry.effect = effect
		entry.time_left = effect.duration
		_active[effect.id] = entry
	else:
		match effect.stack_rule:
			StatusEffect.StackRule.IGNORE_IF_ACTIVE:
				return
			StatusEffect.StackRule.REFRESH:
				entry.time_left = effect.duration
			StatusEffect.StackRule.EXTEND:
				entry.time_left += effect.duration
				if effect.max_duration > 0.0:
					entry.time_left = minf(entry.time_left, effect.max_duration)
			StatusEffect.StackRule.STACK:
				entry.stacks = mini(entry.stacks + 1, effect.max_stacks)
				entry.time_left = effect.duration

	entry.source = source
	if effect.tick_damage != null:
		entry.tick_amount = effect.tick_damage.evaluate(StatsComponent.find_on(source))

	# Stun first: it interrupts the victim's current cast (which may stop a
	# dash), THEN the displacement starts, so the stun's own knockback isn't
	# cancelled by that interrupt.
	if effect.stuns:
		stunned.emit(effect)
	_displace(effect, source, direction)
	if is_new:
		status_applied.emit(effect)


func remove(effect_id: StringName) -> void:
	if not _active.has(effect_id):
		return
	var effect: StatusEffect = _active[effect_id].effect
	_active.erase(effect_id)
	status_removed.emit(effect)


func clear() -> void:
	for effect_id in _active.keys():
		remove(effect_id)


func has_status(effect_id: StringName) -> bool:
	return _active.has(effect_id)


func get_stacks(effect_id: StringName) -> int:
	var entry: Entry = _active.get(effect_id)
	return entry.stacks if entry != null else 0


func get_time_left(effect_id: StringName) -> float:
	var entry: Entry = _active.get(effect_id)
	return entry.time_left if entry != null else 0.0


func get_active_effects() -> Array[StatusEffect]:
	var result: Array[StatusEffect] = []
	for entry in _active.values():
		result.append(entry.effect)
	return result


func get_multiplier(stat: StringName) -> float:
	var result := 1.0
	for entry in _active.values():
		result *= pow(entry.effect.stat_multipliers.get(stat, 1.0), entry.stacks)
	return result


func is_stunned() -> bool:
	return _any(func(e: StatusEffect): return e.stuns)


func is_rooted() -> bool:
	return _any(func(e: StatusEffect): return e.roots or e.stuns)


func is_silenced() -> bool:
	return _any(func(e: StatusEffect): return e.silences or e.stuns)


# Simulation timers run on physics ticks (see HealthComponent for why).
func _physics_process(delta: float) -> void:
	for effect_id in _active.keys():
		var entry: Entry = _active.get(effect_id)
		if entry == null:
			continue    # removed by an earlier tick's side effect (death)
		_tick_damage(entry, delta)
		entry.time_left -= delta
		if entry.time_left <= 0.0 and _active.has(effect_id):
			remove(effect_id)


func _tick_damage(entry: Entry, delta: float) -> void:
	var effect := entry.effect
	if effect.tick_damage == null or effect.tick_interval <= 0.0 or health_component == null:
		return
	entry.tick_timer += delta
	# The epsilon absorbs float drift from summing 1/60 s steps; without it a
	# 1 s burn with 0.25 s ticks sometimes loses its last tick.
	while entry.tick_timer + TICK_EPSILON >= effect.tick_interval and not health_component.is_dead():
		entry.tick_timer -= effect.tick_interval
		var info := DamageInfo.create(entry.tick_amount * entry.stacks,
			entry.source if is_instance_valid(entry.source) else null, effect.tick_damage_type)
		info.tags = [DamageInfo.TAG_DOT, effect.id]
		info.label = effect.tick_label if effect.tick_label != &"" else effect.id
		info.weight = 0.0    # DoT ticks never trigger hitstop / shake
		health_component.apply_damage(info)


func _displace(effect: StatusEffect, source: Node, direction: Vector2) -> void:
	if effect.displace_distance <= 0.0 or movement_component == null:
		return
	var root := _get_root() as Node2D
	var dir := direction
	var source_2d := source as Node2D
	if effect.displace_direction != StatusEffect.DisplaceDirection.ALONG_HIT and source_2d != null and root != null:
		dir = (root.global_position - source_2d.global_position).normalized()
		if effect.displace_direction == StatusEffect.DisplaceDirection.TOWARD_SOURCE:
			# Don't pull past the attacker: stop at most at their feet.
			var gap := root.global_position.distance_to(source_2d.global_position)
			var distance := minf(effect.displace_distance, maxf(gap - effect.pull_stop_distance, 0.0))
			movement_component.displace(-dir, distance, effect.displace_duration)
			return
	if dir == Vector2.ZERO:
		return
	movement_component.displace(dir.normalized(), effect.displace_distance, effect.displace_duration)


func _any(predicate: Callable) -> bool:
	for entry in _active.values():
		if predicate.call(entry.effect):
			return true
	return false


func _get_root() -> Node:
	return owner if owner != null else get_parent()


# Lets components treat a missing StatusEffectComponent as "no modifiers".
static func multiplier_of(component: StatusEffectComponent, stat: StringName) -> float:
	if component == null:
		return 1.0
	return component.get_multiplier(stat)
