extends RangedAttackAbility

# Whisper Bolts: every hit adds a stack of Madness to the target (a
# StackCounter owned by whoever fired: Mochi, or her tentacle, each with its
# own counter). values/madness_hits stacks fill it; it decays after
# values/madness_decay s without hits. Full = the target explodes for
# values/madness_burst MAGIC damage and is immune to that counter for
# values/madness_immunity s.
#
# A shot also makes her tentacle (if out) fire the same bolt at her cursor.
# Cues: madness_stack (context.stacks), madness_burst.

const KEY := &"madness"


func _on_target_hit(_info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	add_madness(actor, hurtbox)


func _on_active_start() -> void:
	super()
	var tentacle := _tentacle()
	if tentacle != null:
		tentacle.mirror(self, actor.aim_point)


# Tentacle bolts land here: same rules, the tentacle's own counter.
func on_mirrored_hit(tentacle: Node, _info: DamageInfo, hurtbox: HurtboxComponent) -> void:
	add_madness(tentacle, hurtbox)


func add_madness(counter_owner: Node, hurtbox: HurtboxComponent) -> void:
	if not is_instance_valid(hurtbox) or not hurtbox.is_valid_target():
		return
	var stats := get_stats()
	var target := ZoneRamp.target_of(hurtbox)
	var full := StackCounter.add(counter_owner, KEY, target, roundi(data.get_value(&"madness_hits", stats)),
		data.get_value(&"madness_decay", stats), data.get_value(&"madness_immunity", stats))
	if not full:
		actor.trigger_cue(&"madness_stack", {"position": hurtbox.global_position, "target": target,
			"stacks": StackCounter.get_stacks(counter_owner, KEY, target)})
		return
	var burst := DamageInfo.create(data.get_value(&"madness_burst", stats)
		* StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE), actor, DamageInfo.Type.MAGIC)
	burst.label = &"madness_burst"
	burst.tags.append(DamageInfo.TAG_AREA)
	burst.hit_position = hurtbox.global_position
	hurtbox.take_hit(burst)
	actor.trigger_cue(&"madness_burst", {"position": hurtbox.global_position, "target": target})


func _tentacle() -> Node:
	for deployable in Deployable.find_owned(actor):
		if deployable.has_method(&"mirror"):
			return deployable
	return null
