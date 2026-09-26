extends SelfStatusAbility

# Parry: the generic self status (a StatusEffect with `parries`), plus the
# reward. When it catches something (CombatHooks.parried), the cooldown
# drops by values/cooldown_refund of its full length and the rifle's next
# shot is a guaranteed crit.


func _ready() -> void:
	super()
	if actor != null and actor.combat_hooks != null:
		actor.combat_hooks.parried.connect(_on_parried)


func _on_parried(_kind: StringName, _attacker: Node, _info: DamageInfo) -> void:
	reduce_cooldown(get_cooldown() * data.get_value(&"cooldown_refund", get_stats()))
	var rifle := actor.ability_controller.get_ability_for_slot(&"primary")
	if rifle != null and rifle.has_method(&"grant_crit"):
		rifle.grant_crit()
	actor.trigger_cue(StringName(str(ability_id) + "_success"))
