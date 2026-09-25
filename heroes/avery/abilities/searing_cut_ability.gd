extends MeleeAttackAbility

# Searing Cut. The slash itself is a normal MeleeAttackAbility swing; this
# script only adds the healing, and it does that through the hit_dealt hook
# rather than inside the swing code. That's the pattern for any on-hit
# effect: listen to your own actor's CombatHooks, filter to your own attack
# id, react. Core systems stay unaware of Searing Cut.
#
# Numbers live in SearingCutData (searing_cut.tres).

var _targets_healed: int = 0
var _healed_this_slash: float = 0.0


func _ready() -> void:
	super()
	# The actor is set before _ready (see AbilityController.add_ability).
	actor.combat_hooks.hit_dealt.connect(_on_hit_dealt)


func get_searing_data() -> SearingCutData:
	return data as SearingCutData


func _on_active_start() -> void:
	_targets_healed = 0
	_healed_this_slash = 0.0
	super()


func _on_hit_dealt(info: DamageInfo, _target: Node) -> void:
	# Only hits from THIS slash count: not the primary, not burns, not a
	# previous Searing Cut. (_attack_id is set by MeleeAttackAbility before it
	# opens the hitbox, so even hits on the very first tick match.)
	if _attack_id == 0 or info.attack_id != _attack_id:
		return
	var searing := get_searing_data()
	var stats := get_stats()
	_targets_healed += 1
	var amount := searing.heal_for_target(_targets_healed, stats)
	if searing.heal_cap != null:
		amount = minf(amount, searing.heal_cap.evaluate(stats) - _healed_this_slash)
	if amount <= 0.0:
		return
	_healed_this_slash += amount
	actor.health_component.heal(amount, actor, searing.heal_label)
	actor.trigger_cue(&"searing_cut_heal", {"text": roundi(amount), "amount": amount})
