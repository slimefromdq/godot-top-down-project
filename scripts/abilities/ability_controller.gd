extends Node
class_name AbilityController

# Owns an actor's abilities and decides WHEN one may start.
#
# Player input and AI both call try_activate(); nothing else starts abilities.
# That's the one place that knows:
#   * only one timed cast runs at a time (you can't slash while dashing);
#   * a cast in its cancel window can be cut short by the next one;
#   * a press that arrives while busy is BUFFERED for a short window and fires
#     the moment it's allowed, so mashing or holding the attack key chains a
#     combo without frame-perfect timing;
#   * a stun interrupts the current cast and clears the buffer;
#   * releases (hold-to-charge) go to the charging ability, or are remembered
#     for a buffered one so a quick tap still ends its charge;
#   * a channel can LOCK the other abilities (lock_abilities): only the slots
#     it allows may start until it unlocks. The lock isn't a cast, so an
#     allowed ability (a dash during a channelled ultimate) runs normally
#     while the channel keeps going.
#
# Abilities come from two places: Ability children placed in a scene (the
# original rifle hero), or add_ability() calls from Hero, which builds them
# from its HeroDefinition.
#
# Forms (swap_slot / restore_slot): a slot can be switched to another
# AbilityData at runtime (a hero's second form). Each form's ability is its
# own node, built on first use and kept: the one swapped out goes DORMANT
# (out of `abilities`, not castable, its cooldown still ticking), so swapping
# back and forth never resets or skips a cooldown. restore_slot() brings back
# the ability the slot started with. abilities_changed fires, so the HUD
# follows.

signal abilities_changed
## A buffered press was dropped because its window ran out.
signal buffer_expired(ability: Ability)
## swap_slot/restore_slot put `ability` in `slot_id`.
signal slot_swapped(slot_id: StringName, ability: Ability)

var abilities: Array[Ability] = []
## The timed cast in progress, or null.
var current_cast: Ability

var _buffered: Ability
var _buffer_time_left: float = 0.0
# The buffered ability's key was already released: release it on start.
var _buffered_released := false
# requester Ability -> Lock
var _locks: Dictionary = {}
# Forms: slot id -> the ability the slot started with, and slot id ->
# {data id -> Ability} for every form built so far.
var _original_forms: Dictionary = {}
var _forms: Dictionary = {}


class Lock:
	var allowed_slots: Array[StringName] = []
	var quiet_slots: Array[StringName] = []


func _ready() -> void:
	for child in get_children():
		if child is Ability:
			_register(child, &"")
	var status := _get_actor().get_node_or_null(^"Components/StatusComponent") as StatusEffectComponent
	if status != null:
		status.stunned.connect(func(_effect): interrupt())
	abilities_changed.emit()


# Adds an ability built at runtime (Hero does this per slot).
func add_ability(ability: Ability, slot_id: StringName = &"") -> void:
	# Register first so the ability already knows its actor in its own _ready
	# (passives like a revive connect to the actor's hooks there).
	_register(ability, slot_id)
	add_child(ability)
	abilities_changed.emit()


func remove_all() -> void:
	interrupt()
	for ability in abilities:
		ability.queue_free()
	abilities.clear()
	abilities_changed.emit()


func try_activate(ability: Ability, target_position: Vector2) -> bool:
	if ability == null:
		return false
	if current_cast != null and current_cast.is_casting():
		# Pressing a charging ability again (a held key repeating, a double
		# click) must not queue a second cast behind the charge.
		if current_cast == ability and ability.is_charging():
			return false
		if current_cast.can_be_cancelled_by(ability):
			current_cast.cancel_recovery()
		else:
			_buffer(ability)
			return false
	return _start(ability, target_position)


func try_activate_id(ability_id: StringName, target_position: Vector2) -> bool:
	return try_activate(get_ability(ability_id), target_position)


func try_activate_slot(slot_id: StringName, target_position: Vector2) -> bool:
	return try_activate(get_ability_for_slot(slot_id), target_position)


# Let go of a hold-to-charge ability. Player input calls this on key release;
# AI calls it when it wants to fire. Returns true if a charge was released.
func release(ability: Ability, target_position: Vector2) -> bool:
	if ability == null:
		return false
	if ability.is_charging():
		return ability.release_charge(target_position)
	if ability.is_held():
		return ability.release_hold(target_position)
	if _buffered == ability:
		_buffered_released = true
	return false


func release_slot(slot_id: StringName, target_position: Vector2) -> bool:
	return release(get_ability_for_slot(slot_id), target_position)


# Drop a charge (no cooldown spent) or a buffered press of `ability`.
func cancel(ability: Ability) -> bool:
	if ability == null:
		return false
	if _buffered == ability:
		_buffered = null
		return true
	if ability.is_charging():
		ability.cancel_charge()
		return true
	return false


# While locked, every ability except `requester` and the `allowed_slots`
# is refused: "Channeling" (a red flash), or silently for `quiet_slots`
# (e.g. a primary whose job the channel has taken over). One lock per
# requester; unlock_abilities() removes it.
func lock_abilities(requester: Ability, allowed_slots: Array[StringName] = [],
		quiet_slots: Array[StringName] = []) -> void:
	var lock := Lock.new()
	lock.allowed_slots = allowed_slots.duplicate()
	lock.quiet_slots = quiet_slots.duplicate()
	_locks[requester] = lock
	if _buffered != null and get_lock_reason(_buffered) != "":
		_buffered = null


func unlock_abilities(requester: Ability) -> void:
	_locks.erase(requester)


func is_locked() -> bool:
	return not _locks.is_empty()


# Why a lock refuses `ability` ("" = it may start). Ability.get_block_reason
# asks this, so AI and player presses are refused the same way.
func get_lock_reason(ability: Ability) -> String:
	for requester in _locks:
		if ability == requester:
			continue
		var lock: Lock = _locks[requester]
		if ability.slot_id != &"" and lock.allowed_slots.has(ability.slot_id):
			continue
		return "Suppressed" if lock.quiet_slots.has(ability.slot_id) else "Channeling"
	return ""


# Stop whatever is being cast (stun, death) and forget buffered presses.
func interrupt() -> void:
	_buffered = null
	if current_cast != null and current_cast.is_casting():
		current_cast.interrupt()
	current_cast = null


func is_busy() -> bool:
	return current_cast != null and current_cast.is_casting()


func get_ability(ability_id: StringName) -> Ability:
	for ability in abilities:
		if ability.ability_id == ability_id:
			return ability
	return null


# --- Forms --------------------------------------------------------------------

# Put the ability for `ability_data` in `slot_id` (built on first use, reused
# after). The one it replaces goes dormant with its cooldown intact. Returns
# the slot's new ability (or the current one if it's already that data).
func swap_slot(slot_id: StringName, ability_data: AbilityData) -> Ability:
	var current := get_ability_for_slot(slot_id)
	if ability_data == null or ability_data.ability_script == null:
		return current
	if current != null and current.ability_id == ability_data.id:
		return current
	if current != null and not _original_forms.has(slot_id):
		_original_forms[slot_id] = current
	var forms: Dictionary = _forms.get(slot_id, {})
	if current != null:
		forms[current.ability_id] = current
	var next: Ability = forms.get(ability_data.id)
	if next == null:
		next = ability_data.ability_script.new()
		next.name = "%s_%s" % [str(slot_id).to_pascal_case(), str(ability_data.id).to_pascal_case()]
		next.input_action = current.input_action if current != null else &""
		next.set_data(ability_data)
		next.actor = _get_actor() as Actor
		next.controller = self
		next.slot_id = slot_id
		forms[ability_data.id] = next
		add_child(next)
	_forms[slot_id] = forms
	_put_in_slot(slot_id, current, next)
	return next


# Back to the ability the slot started with (no-op if never swapped).
func restore_slot(slot_id: StringName) -> Ability:
	var original: Ability = _original_forms.get(slot_id)
	var current := get_ability_for_slot(slot_id)
	if original == null or current == original:
		return current
	_put_in_slot(slot_id, current, original)
	return original


func is_slot_swapped(slot_id: StringName) -> bool:
	return _original_forms.has(slot_id) and get_ability_for_slot(slot_id) != _original_forms[slot_id]


# Every form a slot has had (active or dormant), by data id.
func get_slot_forms(slot_id: StringName) -> Dictionary:
	return _forms.get(slot_id, {})


func _put_in_slot(slot_id: StringName, out: Ability, into: Ability) -> void:
	var index := abilities.size()
	if out != null:
		if current_cast == out:
			interrupt()
		if _buffered == out:
			_buffered = null
		if out.is_held():
			out.release_hold(out.cast_target)
		index = abilities.find(out)
		abilities.erase(out)
		out.set_dormant(true)
	into.set_dormant(false)
	abilities.insert(clampi(index, 0, abilities.size()), into)
	abilities_changed.emit()
	slot_swapped.emit(slot_id, into)


func get_ability_for_slot(slot_id: StringName) -> Ability:
	for ability in abilities:
		if ability.slot_id == slot_id:
			return ability
	return null


# Returns the first ability bound to an input event, or null.
func get_ability_for_event(event: InputEvent) -> Ability:
	for ability in abilities:
		if ability.input_action != &"" and event.is_action_pressed(ability.input_action):
			return ability
	return null


func _physics_process(delta: float) -> void:
	if current_cast != null and not current_cast.is_casting():
		current_cast = null
	if _buffered == null:
		return
	_buffer_time_left -= delta
	if _buffer_time_left <= 0.0:
		buffer_expired.emit(_buffered)
		_buffered = null
		return
	if current_cast == null or current_cast.can_be_cancelled_by(_buffered):
		var ability := _buffered
		var released := _buffered_released
		_buffered = null
		_buffered_released = false
		if current_cast != null:
			current_cast.cancel_recovery()
		# Aim at where the player is aiming NOW, not where they were when
		# they pressed early: a buffered swing should follow the mouse.
		var aim: Vector2 = _get_actor().get(&"aim_point")
		if _start(ability, aim) and released and ability.is_charging():
			ability.release_charge(aim)


func _start(ability: Ability, target_position: Vector2) -> bool:
	var started := ability.start_cast(target_position)
	if started and ability.is_casting():
		current_cast = ability
	return started


func _buffer(ability: Ability) -> void:
	# Latest press wins: if you pressed attack then dash, you meant dash.
	if _buffered != ability:
		_buffered_released = false
	_buffered = ability
	var profile: FeelProfile = _get_actor().get(&"feel_profile")
	_buffer_time_left = profile.get_input_buffer() if profile != null \
		else GameRules.current().default_input_buffer


func _register(ability: Ability, slot_id: StringName) -> void:
	ability.actor = _get_actor() as Actor
	ability.controller = self
	if slot_id != &"":
		ability.slot_id = slot_id
	abilities.append(ability)


func _get_actor() -> Node:
	return owner if owner != null else get_parent().get_parent()
