extends CanvasLayer
class_name AbilityBar

# Bottom-of-screen ability bar. Builds one AbilitySlot per ability on the
# target actor, in AbilityController order, and rebuilds whenever the
# actor's abilities change (a hero assembling itself, a debug reset).

## Leave empty to follow the actor in the "player" group.
@export var actor: Actor

@onready var slots: HBoxContainer = %Slots


func _ready() -> void:
	if actor == null:
		actor = get_tree().get_first_node_in_group(&"player") as Actor
	if actor == null:
		return
	actor.ability_controller.abilities_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in slots.get_children():
		child.queue_free()
	for ability in actor.ability_controller.abilities:
		var slot := AbilitySlot.new()
		slots.add_child(slot)
		slot.setup(ability)
