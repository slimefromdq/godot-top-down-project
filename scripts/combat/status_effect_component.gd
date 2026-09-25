extends Node
class_name StatusEffectComponent

# Holds the buffs and debuffs currently on an actor. Other components ask it
# for multipliers and CC state instead of being edited directly, so an effect
# ending always restores the original values.
#
# Each application is an Entry. Normally one Entry per status id (reapplying
# follows the stack rule, and the latest applier owns it); with
# StatusEffect.stack_per_applier each applier gets its own Entry.
#
# Appliers hear about their statuses through their own CombatHooks:
#   status_expired(id, target)            ran its full duration
#   status_removed(id, target, reason)    ended for any reason (see REASON_*)
#   status_target_died(id, target, info)  the target died while carrying it
# That's how a "mark" ability learns its marked target died, whoever killed it.

signal status_applied(effect: StatusEffect)
signal status_removed(effect: StatusEffect)
## A stun landed. AbilityController listens to interrupt the current cast.
signal stunned(effect: StatusEffect)

## Why a status ended (the `reason` of CombatHooks.status_removed).
const REASON_EXPIRED := &"expired"
const REASON_REMOVED := &"removed"         ## remove()/remove_from()/clear(): a cleanse, a zone exit
const REASON_TARGET_DIED := &"target_died"
const REASON_APPLIER_DIED := &"applier_died"

## Optional. Needed for displacement (knockback / pull) and compel.
@export var movement_component: MovementComponent
## Optional. Needed for damage over time and death notifications.
@export var health_component: HealthComponent
## Optional. Needed for stat_modifiers.
@export var stats_component: StatsComponent

const TICK_EPSILON := 0.0001

# key -> Entry. The key is the status id, or "id@applier" for
# stack_per_applier statuses.
var _active: Dictionary = {}
# Makes every stat-modifier source id unique, even for the same applier
# re-applying after an expiry.
static var _next_serial: int = 1


func _ready() -> void:
	# Older scenes don't wire these; find the siblings so they still work.
	var root := _get_root()
	if movement_component == null:
		movement_component = VisualsComponent._find_child_of_type(root, "MovementComponent")
	if health_component == null:
		health_component = VisualsComponent._find_child_of_type(root, "HealthComponent")
	if stats_component == null:
		stats_component = StatsComponent.find_on(root)
	if health_component != null:
		# damage_taken fires before `died`, so appliers are told while the
		# statuses are still on the target (a dummy clears them on death).
		health_component.damage_taken.connect(_on_damage_taken)


class Entry:
	var key: String
	var effect: StatusEffect
	var time_left: float
	var stacks: int = 1
	var source: Node
	# Snapshot of one tick's damage per stack, from the applier's stats.
	var tick_amount: float = 0.0
	var tick_timer: float = 0.0
	# StatModifier.source_id for this application's modifiers ("" = none).
	var modifier_source: StringName = &""


# `source` is who applied it (for DoT kill credit and snapshotting their
# stats); `direction` is the hit direction (for ALONG_HIT displacement).
func apply(effect: StatusEffect, source: Node = null, direction: Vector2 = Vector2.ZERO) -> void:
	if effect == null:
		return
	var key := _key_for(effect, source)
	var entry: Entry = _active.get(key)
	var is_new := entry == null
	var first_of_id := is_new and not has_status(effect.id)
	var previous_source = null    # untyped: may have been freed
	if is_new:
		entry = Entry.new()
		entry.key = key
		entry.effect = effect
		entry.time_left = effect.duration
		_active[key] = entry
	else:
		previous_source = entry.source
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
	_apply_modifiers(entry)

	# A shared status taken over by a new applier: the old one's status
	# ended from its point of view.
	if is_instance_valid(previous_source) and previous_source != source:
		_notify_removed(previous_source, effect.id, REASON_REMOVED)

	# Stun first: it interrupts the victim's current cast (which may stop a
	# dash), THEN the displacement starts, so the stun's own knockback isn't
	# cancelled by that interrupt.
	if effect.stuns:
		stunned.emit(effect)
	_displace(effect, source, direction)
	if first_of_id:
		status_applied.emit(effect)


# Remove every application of a status (a cleanse).
func remove(effect_id: StringName) -> void:
	for entry in _entries_of(effect_id):
		_end(entry, REASON_REMOVED)


# Remove only `source`'s application (a zone releasing its own status).
func remove_from(effect_id: StringName, source: Node) -> void:
	for entry in _entries_of(effect_id):
		if entry.source == source:
			_end(entry, REASON_REMOVED)


func clear() -> void:
	for entry in _active.values():
		_end(entry, REASON_REMOVED)


func has_status(effect_id: StringName) -> bool:
	return not _entries_of(effect_id).is_empty()


func has_status_from(effect_id: StringName, source: Node) -> bool:
	for entry in _entries_of(effect_id):
		if entry.source == source:
			return true
	return false


# Highest stack count among the applications of this status.
func get_stacks(effect_id: StringName) -> int:
	var result := 0
	for entry in _entries_of(effect_id):
		result = maxi(result, entry.stacks)
	return result


func get_time_left(effect_id: StringName) -> float:
	var result := 0.0
	for entry in _entries_of(effect_id):
		result = maxf(result, entry.time_left)
	return result


# Who applied a status (the most recent applier if several).
func get_applier(effect_id: StringName) -> Node:
	var entries := _entries_of(effect_id)
	if entries.is_empty() or not is_instance_valid(entries.back().source):
		return null
	return entries.back().source


func get_active_effects() -> Array[StatusEffect]:
	var result: Array[StatusEffect] = []
	for entry in _active.values():
		if not result.has(entry.effect):
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


# The compel currently steering this actor (the most recently applied one),
# or null. MovementComponent reads this every physics tick.
func get_compel_effect() -> StatusEffect:
	var entry := _compel_entry()
	return entry.effect if entry != null else null


# Who the compelled actor walks toward (the applier, live position).
func get_compel_source() -> Node2D:
	var entry := _compel_entry()
	return entry.source as Node2D if entry != null else null


func is_compelled() -> bool:
	return _compel_entry() != null


# Simulation timers run on physics ticks (see HealthComponent for why).
func _physics_process(delta: float) -> void:
	for key in _active.keys():
		var entry: Entry = _active.get(key)
		if entry == null:
			continue    # removed by an earlier tick's side effect (death)
		if entry.effect.ends_with_applier() and is_actor_gone(entry.source):
			_end(entry, REASON_APPLIER_DIED)
			continue
		_tick_damage(entry, delta)
		entry.time_left -= delta
		if entry.time_left <= 0.0 and _active.get(key) == entry:
			_end(entry, REASON_EXPIRED)


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


# The one exit path: removes the entry, its stat modifiers, tells the applier
# and (for the last application of an id) the visuals.
func _end(entry: Entry, reason: StringName) -> void:
	if _active.get(entry.key) != entry:
		return
	_active.erase(entry.key)
	if entry.modifier_source != &"" and stats_component != null:
		# Removing a modifier never grants current HP (see HealthComponent).
		stats_component.remove_modifiers_from(entry.modifier_source, false)
	if reason == REASON_EXPIRED:
		var hooks := _hooks_of(entry.source)
		if hooks != null:
			hooks.status_expired.emit(entry.effect.id, _get_root())
	_notify_removed(entry.source, entry.effect.id, reason)
	if not has_status(entry.effect.id):
		status_removed.emit(entry.effect)


func _notify_removed(source, effect_id: StringName, reason: StringName) -> void:
	var hooks := _hooks_of(source)
	if hooks != null:
		hooks.status_removed.emit(effect_id, _get_root(), reason)


# A killing blow landed: tell every applier, then drop every status.
func _on_damage_taken(info: DamageInfo) -> void:
	if not info.killed:
		return
	var root := _get_root()
	for entry in _active.values():
		var hooks := _hooks_of(entry.source)
		if hooks != null:
			hooks.status_target_died.emit(entry.effect.id, root, info)
	for entry in _active.values():
		_end(entry, REASON_TARGET_DIED)


func _apply_modifiers(entry: Entry) -> void:
	if entry.effect.stat_modifiers.is_empty() or stats_component == null:
		return
	if entry.modifier_source == &"":
		# Unique per application: status id + applier + serial, so two
		# appliers (or a reapplication) never remove each other's modifiers.
		var applier_id := entry.source.get_instance_id() if is_instance_valid(entry.source) else 0
		entry.modifier_source = StringName("status:%s:%d:%d" % [entry.effect.id, applier_id, _next_serial])
		_next_serial += 1
	else:
		# Stack count may have changed: replace this entry's own modifiers.
		stats_component.remove_modifiers_from(entry.modifier_source, false)
	var batch: Array[StatModifier] = []
	for template in entry.effect.stat_modifiers:
		if template == null:
			continue
		batch.append(StatModifier.make(template.stat, template.flat * entry.stacks,
			template.percent * entry.stacks, entry.modifier_source))
	stats_component.add_modifiers(batch)


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


func _compel_entry() -> Entry:
	var found: Entry = null
	for entry in _active.values():
		if entry.effect.compel_enabled and is_instance_valid(entry.source) and entry.source is Node2D:
			found = entry    # later entries were applied later
	return found


func _key_for(effect: StatusEffect, source: Node) -> String:
	if effect.stack_per_applier:
		return "%s@%d" % [effect.id, source.get_instance_id() if is_instance_valid(source) else 0]
	return str(effect.id)


func _entries_of(effect_id: StringName) -> Array[Entry]:
	var result: Array[Entry] = []
	for entry in _active.values():
		if entry.effect.id == effect_id:
			result.append(entry)
	return result


# The applier's hooks, or null if it's gone. Untyped: it may be freed.
static func _hooks_of(node) -> CombatHooks:
	return CombatHooks.find_on(node) if is_instance_valid(node) else null


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


# Dead, freed or gone: for "ends if the applier dies" rules.
static func is_actor_gone(node) -> bool:
	if not is_instance_valid(node) or not node is Node or not node.is_inside_tree() or node.is_queued_for_deletion():
		return true
	var health = node.get(&"health_component")
	if not health is HealthComponent:
		health = node.get_node_or_null(^"Components/HealthComponent")
	return health is HealthComponent and health.is_dead()
