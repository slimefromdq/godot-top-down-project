extends SelfStatusAbility

# All Eyes on Me: the generic self status (her damage reduction), plus the
# taunt: every enemy within count_radius gets the data's on_hit_status (a
# compel toward her). Cue: <id>_applied (context.enemies) as usual.


func _on_active_start() -> void:
	super()
	var self_data := get_self_status_data()
	if self_data.on_hit_status == null:
		return
	for hurtbox in Hitbox.query(actor, actor.global_position, Vector2.RIGHT,
			HitShape.circle(self_data.count_radius), actor):
		if hurtbox.status_component != null and hurtbox.is_valid_target():
			hurtbox.status_component.apply(self_data.on_hit_status, actor, actor.global_position.direction_to(hurtbox.global_position))
