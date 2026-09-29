extends RangedAttackAbility

# Sticky Bomb: the shot sticks its on_hit_status (the bomb, drawn on the
# victim for everyone) to one target. When that status runs its full
# duration it goes off: values/bomb_damage to the victim alone. Cleansing
# it, or the victim dying first, defuses it. Cue: sticky_bomb_boom.


func _ready() -> void:
	super()
	if actor != null and actor.combat_hooks != null:
		actor.combat_hooks.status_expired.connect(_on_status_expired)


func _on_status_expired(id: StringName, target: Node) -> void:
	if data.on_hit_status == null or id != data.on_hit_status.id or not is_instance_valid(target):
		return
	var hurtbox := target.get_node_or_null(^"Hurtbox") as HurtboxComponent
	if hurtbox == null or not hurtbox.is_valid_target():
		return
	var info := DamageInfo.create(data.get_value(&"bomb_damage", get_stats())
		* StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DAMAGE), actor, data.damage_type)
	info.label = &"sticky_bomb_boom"
	info.tags.append(DamageInfo.TAG_AREA)
	info.hit_position = hurtbox.global_position
	hurtbox.take_hit(info)
	actor.trigger_cue(&"sticky_bomb_boom", {"position": hurtbox.global_position, "target": target})
