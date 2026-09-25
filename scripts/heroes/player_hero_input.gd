extends Node
class_name PlayerHeroInput

# Local keyboard + mouse control for a Hero. It only writes intent (move,
# aim) and requests slots; the Hero and its AbilityController decide what
# actually happens. An AI or a network client would replace this node.
#
# Keys come from GameRules.slots, so rebinding is a data change.
#
# Presses are read in _unhandled_input, so a click on a debug-panel button
# doesn't also swing the sword. Held keys keep requesting every tick while
# held when the ability wants that (Ability.repeats_while_held: a
# hold_to_repeat slot's melee chain, an AUTO gun in any slot); the
# controller's buffer turns that into a smooth combo chain. Releases go to
# hero.release_slot() for hold-to-charge abilities, and hero_reload
# (R by default) calls hero.reload().

const RELOAD_ACTION := &"hero_reload"

var hero: Hero
var _held: Dictionary = {}    # slot id -> true while held


func _ready() -> void:
	hero = get_parent() as Hero


func _physics_process(_delta: float) -> void:
	hero.move_direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_update_aim()
	for slot in GameRules.current().slots:
		var ability := hero.get_ability(slot.id)
		if ability == null or slot.input_action == &"" or not InputMap.has_action(slot.input_action):
			continue
		var pressed := Input.is_action_pressed(slot.input_action)
		# A release can be missed (focus loss, the press was buffered and
		# started after the key came up): a charge never outlives its key.
		if ability.is_charging() and not pressed:
			hero.release_slot(slot.id, hero.aim_point)
		if _held.get(slot.id, false) and ability.repeats_while_held(slot.hold_to_repeat):
			if pressed:
				hero.request_slot(slot.id, hero.aim_point)
			else:
				_held.erase(slot.id)


# Aim is updated every rendered frame as well, so facing feels instant even
# at high frame rates.
func _process(_delta: float) -> void:
	_update_aim()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(RELOAD_ACTION) and event.is_action_pressed(RELOAD_ACTION):
		hero.reload()
		get_viewport().set_input_as_handled()
		return
	for slot in GameRules.current().slots:
		if slot.input_action == &"" or not InputMap.has_action(slot.input_action):
			continue
		if event.is_action_pressed(slot.input_action):
			_update_aim()
			_held[slot.id] = true
			hero.request_slot(slot.id, hero.aim_point)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(slot.input_action):
			_held.erase(slot.id)
			_update_aim()
			hero.release_slot(slot.id, hero.aim_point)


func _update_aim() -> void:
	var mouse := hero.get_global_mouse_position()
	hero.aim_point = mouse
	var offset := mouse - hero.global_position
	if offset.length() > 1.0:
		hero.aim_direction = offset.normalized()
