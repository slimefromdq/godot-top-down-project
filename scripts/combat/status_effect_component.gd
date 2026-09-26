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
#
# Resolve (GameRules.resolve_*): when hard CC (StatusEffect.is_hard_cc) that
# someone else applied ends, the actor gets GameRules.resolve_status; while
# it lasts, new hard CC is shortened by resolve_cc_multiplier. That's the one
# place CC chains are limited, so no hero needs its own diminishing returns.

signal status_applied(effect: StatusEffect)
signal status_removed(effect: StatusEffect)
## A stun landed. AbilityController listens to interrupt the current cast.
signal stunned(effect: StatusEffect)
## The total shield on this actor changed (health bars draw it).
signal shield_changed(total: float)

## Why a status ended (the `reason` of CombatHooks.status_removed).
const REASON_EXPIRED := &"expired"
const REASON_REMOVED := &"removed"         ## remove()/remove_from()/clear(): a cleanse, a zone exit
const REASON_TARGET_DIED := &"target_died"
const REASON_APPLIER_DIED := &"applier_died"
const REASON_SHIELD_BROKEN := &"shield_broken"   ## its shield was used up
const REASON_BROKEN_FREE := &"broken_free"       ## a follower broke out of a formation

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
# StatusEffect.VfxVisibleTo.LISTED: status id -> actors allowed to see its VFX.
var _vfx_viewers: Dictionary = {}
# clear() ends everything at once (a reset or death): it grants no Resolve.
var _clearing := false


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
	# Duration the fade runs over (time_left / full_duration = fade ratio).
	var full_duration: float = 0.0
	# How strongly this application applies (multipliers and shield).
	var strength: float = 1.0
	var shield_remaining: float = 0.0
	# carry_enabled: where the target rides relative to the applier.
	var carry_offset := Vector2.ZERO


# `source` is who applied it (for DoT kill credit and snapshotting their
# stats); `direction` is the hit direction (for ALONG_HIT displacement).
# `strength` scales the stat multipliers' distance from 1.0 and the shield
# (a half-charged buff = 0.5). `duration_override` >= 0 replaces the
# resource's duration for this application.
func apply(effect: StatusEffect, source: Node = null, direction: Vector2 = Vector2.ZERO,
		strength: float = 1.0, duration_override: float = -1.0) -> void:
	if effect == null:
		return
	var key := _key_for(effect, source)
	var entry: Entry = _active.get(key)
	var is_new := entry == null
	var first_of_id := is_new and not has_status(effect.id)
	var previous_source = null    # untyped: may have been freed
	var duration := duration_override if duration_override >= 0.0 else effect.duration
	if _resolve_applies(effect, source) and is_resolved():
		duration *= GameRules.current().resolve_cc_multiplier
	var shield := effect.shield_amount.evaluate(StatsComponent.find_on(source)) * strength \
		if effect.shield_amount != null else 0.0
	if is_new:
		entry = Entry.new()
		entry.key = key
		entry.effect = effect
		entry.time_left = duration
		entry.shield_remaining = shield
		_active[key] = entry
	else:
		previous_source = entry.source
		match effect.stack_rule:
			StatusEffect.StackRule.IGNORE_IF_ACTIVE:
				return
			StatusEffect.StackRule.REFRESH:
				entry.time_left = duration
				entry.shield_remaining = maxf(entry.shield_remaining, shield)
			StatusEffect.StackRule.EXTEND:
				entry.time_left += duration
				if effect.max_duration > 0.0:
					entry.time_left = minf(entry.time_left, effect.max_duration)
				entry.shield_remaining = maxf(entry.shield_remaining, shield)
			StatusEffect.StackRule.STACK:
				entry.stacks = mini(entry.stacks + 1, effect.max_stacks)
				entry.time_left = duration
				entry.shield_remaining += shield
	entry.full_duration = maxf(entry.time_left, 0.0001)
	# A refresh keeps the stronger application (a weaker hit doesn't
	# downgrade a stronger mark); STACK takes the latest.
	if is_new or effect.stack_rule == StatusEffect.StackRule.STACK:
		entry.strength = strength
	else:
		entry.strength = maxf(entry.strength, strength)
	if effect.shield_amount != null:
		shield_changed.emit(get_shield_total())
	if effect.compel_enabled and effect.compel_follow_trail and (is_new or previous_source != source):
		if is_instance_valid(previous_source):
			TrailRecorder.leave(previous_source, _get_root())
		TrailRecorder.join(source, _get_root())

	if effect.carry_enabled and (is_new or previous_source != source):
		entry.carry_offset = _carry_offset_for(effect, source)
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
	_clearing = true
	for entry in _active.values():
		_end(entry, REASON_REMOVED)
	_clearing = false


# --- Resolve -----------------------------------------------------------------

# True while new hard CC on this actor is shortened.
func is_resolved() -> bool:
	var status := GameRules.current().resolve_status
	return status != null and has_status(status.id)


# Hard CC from someone else: the kind Resolve shortens and grants.
func _resolve_applies(effect: StatusEffect, source) -> bool:    # untyped: may be freed
	return effect.is_hard_cc() and not (is_instance_valid(source) and source == _get_root())


func _grant_resolve() -> void:
	var rules := GameRules.current()
	if rules.resolve_status == null or rules.resolve_duration <= 0.0:
		return
	if health_component != null and health_component.is_dead():
		return
	apply(rules.resolve_status, null, Vector2.ZERO, 1.0, rules.resolve_duration)


# --- Viewer-filtered VFX ------------------------------------------------------

# Who may see a LISTED status's attached VFX (StatusEffect.VfxVisibleTo).
# The list lasts until the status fully ends.
func set_vfx_viewers(effect_id: StringName, viewers: Array) -> void:
	_vfx_viewers[effect_id] = viewers.duplicate()


func get_vfx_viewers(effect_id: StringName) -> Array:
	return _vfx_viewers.get(effect_id, [])


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


# Product of every active multiplier for `stat`. Each application's
# distance from 1.0 is scaled by its strength and, with fade_multipliers,
# by how much of its duration is left.
func get_multiplier(stat: StringName) -> float:
	var result := 1.0
	for entry in _active.values():
		var full: float = entry.effect.get_stat_multiplier(stat)
		if full == 1.0:
			continue
		var scale: float = entry.strength
		if entry.effect.fade_multipliers:
			scale *= _fade_of(entry)
		result *= pow(1.0 + (full - 1.0) * scale, entry.stacks)
	return result


# Fraction of the status's duration left (1 = just applied, 0 = ending);
# the largest among its applications. 0 if not active. A fading status's
# multipliers are at this fraction of their full strength.
func get_fade_ratio(effect_id: StringName) -> float:
	var result := 0.0
	for entry in _entries_of(effect_id):
		result = maxf(result, _fade_of(entry))
	return result


func _fade_of(entry: Entry) -> float:
	return clampf(entry.time_left / entry.full_duration, 0.0, 1.0) if entry.full_duration > 0.0 else 0.0


# --- Shields -----------------------------------------------------------------

func get_shield_total() -> float:
	var total := 0.0
	for entry in _active.values():
		total += entry.shield_remaining
	return total


# Soak up to `amount` damage with active shields, soonest-expiring first.
# Returns what was absorbed. Depleted shields end their status. Every bit
# absorbed is reported to CombatEvents.damage_absorbed (meters credit the
# shield's applier). HealthComponent calls this; nothing else should.
func absorb_damage(amount: float, info: DamageInfo = null) -> float:
	var shielded: Array = _active.values().filter(func(e): return e.shield_remaining > 0.0)
	if shielded.is_empty() or amount <= 0.0:
		return 0.0
	shielded.sort_custom(func(a, b): return a.time_left < b.time_left)
	var absorbed := 0.0
	for entry in shielded:
		var take := minf(entry.shield_remaining, amount - absorbed)
		entry.shield_remaining -= take
		absorbed += take
		CombatEvents.damage_absorbed.emit(take, entry.source if is_instance_valid(entry.source) else null,
			_get_root(), entry.effect.id, info)
		if entry.shield_remaining <= 0.0:
			_end(entry, REASON_SHIELD_BROKEN)
		if absorbed >= amount:
			break
	shield_changed.emit(get_shield_total())
	return absorbed


# --- Formations ----------------------------------------------------------------

# Break out of every breakable formation (follow-trail compel). The AI's
# "struggle free" call; the player does it with opposing input.
func break_formation() -> bool:
	var broke := false
	for entry in _active.values():
		if entry.effect.compel_enabled and entry.effect.compel_follow_trail and entry.effect.compel_breakable:
			_end(entry, REASON_BROKEN_FREE)
			broke = true
	return broke


# Ability calls this when a movement ability starts on this actor.
func on_movement_ability_used() -> void:
	for entry in _active.values():
		var effect: StatusEffect = entry.effect
		if effect.compel_enabled and effect.compel_follow_trail and effect.compel_breakable \
				and effect.compel_break_on_movement_ability:
			_end(entry, REASON_BROKEN_FREE)


func is_stunned() -> bool:
	return _any(func(e: StatusEffect): return e.stuns)


func is_rooted() -> bool:
	return _any(func(e: StatusEffect): return e.roots or e.stuns)


# Hurtboxes ignore hits and statuses while this is true (StatusEffect.untargetable).
func is_untargetable() -> bool:
	return _any(func(e: StatusEffect): return e.untargetable)


# Seen through bushes (StatusEffect.reveals; see CombatQueries).
func is_revealed() -> bool:
	return _any(func(e: StatusEffect): return e.reveals)


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


# The carry currently dragging this actor (the most recently applied one), or
# null. MovementComponent reads these every physics tick.
func get_carry_effect() -> StatusEffect:
	var entry := _carry_entry()
	return entry.effect if entry != null else null


func get_carrier() -> Node2D:
	var entry := _carry_entry()
	return entry.source as Node2D if entry != null else null


# Where the carried actor rides, relative to the carrier.
func get_carry_offset() -> Vector2:
	var entry := _carry_entry()
	return entry.carry_offset if entry != null else Vector2.ZERO


func is_carried() -> bool:
	return _carry_entry() != null


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
	if entry.effect.compel_enabled and entry.effect.compel_follow_trail and is_instance_valid(entry.source):
		TrailRecorder.leave(entry.source, _get_root())
	if entry.shield_remaining > 0.0 or reason == REASON_SHIELD_BROKEN:
		shield_changed.emit(get_shield_total())
	if entry.modifier_source != &"" and stats_component != null:
		# Removing a modifier never grants current HP (see HealthComponent).
		stats_component.remove_modifiers_from(entry.modifier_source, false)
	if reason == REASON_EXPIRED:
		var hooks := _hooks_of(entry.source)
		if hooks != null:
			hooks.status_expired.emit(entry.effect.id, _get_root())
	_notify_removed(entry.source, entry.effect.id, reason)
	if not has_status(entry.effect.id):
		_vfx_viewers.erase(entry.effect.id)
		status_removed.emit(entry.effect)
	if reason != REASON_TARGET_DIED and not _clearing and _resolve_applies(entry.effect, entry.source):
		_grant_resolve()


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


func _carry_entry() -> Entry:
	var found: Entry = null
	for entry in _active.values():
		if entry.effect.carry_enabled and is_instance_valid(entry.source) and entry.source is Node2D:
			found = entry
	return found


func _carry_offset_for(effect: StatusEffect, source: Node) -> Vector2:
	var root := _get_root() as Node2D
	var source_2d := source as Node2D
	if root == null or source_2d == null:
		return Vector2.ZERO
	var offset := root.global_position - source_2d.global_position
	return offset.limit_length(effect.carry_max_offset) if effect.carry_max_offset > 0.0 else offset


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
