extends Ability
class_name PassiveAbility

# Base for a hero's passive, in the optional "passive" slot (GameRules; no
# input). It never casts; it lives next to the hero's abilities so its
# numbers are an AbilityData like any other (F1 panel, F2 inspector, CSV)
# and it shows on the ability bar (override get_hud_pips for stacks).
# Subclasses connect to the actor's hooks in _ready.


func get_block_reason() -> String:
	return "Passive"


func _is_silent_block(reason: String) -> bool:
	return reason == "Passive" or super(reason)
