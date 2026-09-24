extends Node
class_name AbilityController

# Owns an actor's abilities: every Ability child is a slot, in child order.
# Player input and enemy AI both go through try_activate(), so the same
# ability works for either.

signal abilities_changed

var abilities: Array[Ability] = []


func _ready() -> void:
	var actor := owner as Actor
	for child in get_children():
		if child is Ability:
			child.actor = actor
			abilities.append(child)
	abilities_changed.emit()


func try_activate(ability: Ability, target_position: Vector2) -> bool:
	return ability.try_activate(target_position)


func try_activate_id(ability_id: StringName, target_position: Vector2) -> bool:
	var ability := get_ability(ability_id)
	return ability != null and ability.try_activate(target_position)


func get_ability(ability_id: StringName) -> Ability:
	for ability in abilities:
		if ability.ability_id == ability_id:
			return ability
	return null


# Returns the first ability bound to an input event, or null.
func get_ability_for_event(event: InputEvent) -> Ability:
	for ability in abilities:
		if ability.input_action != &"" and event.is_action_pressed(ability.input_action):
			return ability
	return null
