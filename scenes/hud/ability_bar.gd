extends CanvasLayer
class_name AbilityBar

# Bottom-of-screen ability bar. Builds one AbilitySlot per ability on the
# target actor, in AbilityController order.

@export var actor: Actor

@onready var slots: HBoxContainer = %Slots


func _ready() -> void:
	if actor == null:
		return
	# The controller collects its abilities in its own _ready, which has
	# already run by now because the player sits above the HUD in the tree.
	for ability in actor.ability_controller.abilities:
		var slot := AbilitySlot.new()
		slots.add_child(slot)
		slot.setup(ability)
