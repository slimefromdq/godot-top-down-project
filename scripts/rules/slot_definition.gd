@tool
extends Resource
class_name SlotDefinition

# One ability slot every hero can fill ("primary", "cc", ...). The list of
# slots lives in GameRules, so adding a new slot type or rebinding a key is a
# data change, not a code change.

## Stable id used as the key in HeroDefinition.abilities. Keep it snake_case.
@export var id: StringName
@export var display_name: String = ""
## Input action (Project Settings > Input Map) that requests this slot.
@export var input_action: StringName
## A hero may leave an optional slot empty without a validation warning.
@export var required: bool = true
## Holding the key keeps re-requesting the ability (a basic-attack chain).
## Off means one press = one request.
@export var hold_to_repeat: bool = false
