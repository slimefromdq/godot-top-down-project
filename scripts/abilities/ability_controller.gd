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
#   * a stun interrupts the current cast and clears the buffer.
#
# Abilities come from two places: Ability children placed in a scene (the
# original rifle hero), or add_ability() calls from Hero, which builds them
# from its HeroDefinition.

signal abilities_changed
## A buffered press was dropped because its window ran out.
signal buffer_expired(ability: Ability)

var abilities: Array[Ability] = []
## The timed cast in progress, or null.
var current_cast: Ability

var _buffered: Ability
var _buffer_time_left: float = 0.0


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
	add_child(ability)
	_register(ability, slot_id)
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
		_buffered = null
		if current_cast != null:
			current_cast.cancel_recovery()
		# Aim at where the player is aiming NOW, not where they were when
		# they pressed early: a buffered swing should follow the mouse.
		_start(ability, _get_actor().get(&"aim_point"))


func _start(ability: Ability, target_position: Vector2) -> bool:
	var started := ability.start_cast(target_position)
	if started and ability.is_casting():
		current_cast = ability
	return started


func _buffer(ability: Ability) -> void:
	# Latest press wins: if you pressed attack then dash, you meant dash.
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
