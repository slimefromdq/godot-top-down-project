extends Deployable

# Mochi's tentacle: it copies her shots. When her primary or her RMB fires,
# the ability calls mirror(): the tentacle fires the same projectile, at the
# same damage, from where it stands toward her cursor. Its bolts build
# Madness on its OWN counter (the primary's on_mirrored_hit), so the two
# fill separately. Hittable and killable (DeployData.deploy_health).


func mirror(ability: RangedAttackAbility, at_point: Vector2) -> void:
	if is_gone() or is_disabled():
		return
	var ranged := ability.get_ranged_data()
	var direction := global_position.direction_to(at_point)
	if direction == Vector2.ZERO or ranged.projectile == null:
		return
	var template := DamageInfo.create(ability._shot_damage() * ability._damage_multiplier(false), owner_actor, ranged.damage_type)
	template.label = StringName(str(ranged.get_label()) + "_tentacle")
	template.tags = ranged.tags.duplicate()
	template.add_status(ranged.on_hit_status)
	var shot := Projectile.fire(self, ranged.projectile, global_position + direction * data.body_radius, direction, template)
	if ability.has_method(&"modify_mirrored_hit"):
		shot.hit_modifier = func(info: DamageInfo, hurtbox: HurtboxComponent, _travelled: float) -> DamageInfo:
			return ability.modify_mirrored_hit(info, hurtbox) if is_instance_valid(ability) else info
	shot.hit_landed.connect(func(info: DamageInfo, hurtbox: HurtboxComponent):
		if is_instance_valid(ability) and ability.has_method(&"on_mirrored_hit"):
			ability.on_mirrored_hit(self, info, hurtbox))
	if owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(&"tentacle_fire", {"position": global_position, "direction": direction})


func _draw() -> void:
	super()
	if data.visual_scene == null:
		var aim: Vector2 = owner_actor.get(&"aim_point") if is_instance_valid(owner_actor) else global_position
		var d := global_position.direction_to(aim)
		for i in 4:
			draw_circle(d.rotated(sin(get_age() * 4.0 + i) * 0.3) * (10.0 + i * 12.0), 12.0 - i * 2.0, Color(0.55, 0.2, 0.6))
