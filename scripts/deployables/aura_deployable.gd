extends Deployable
class_name AuraDeployable

# A placed healing post: every values/tick_interval, allies of the owner
# (the owner included) within values/radius heal values/heal_per_second x
# the interval, credited to the owner (ult charge, meters). Stunned or
# silenced = no healing. Owner cue: <kind>_pulse (context.position, .radius).

var _timer: float = 0.0


func _deploy_tick(delta: float) -> void:
	_timer += delta
	var interval := maxf(get_value(&"tick_interval"), 0.05)
	if _timer < interval:
		return
	_timer -= interval
	if is_disabled():
		return
	var radius := get_value(&"radius")
	var amount := get_value(&"heal_per_second") * interval
	for hurtbox in Hitbox.query(self, global_position, Vector2.RIGHT, HitShape.circle(radius), owner_actor, Hitbox.Affects.ALLIES):
		if hurtbox.owner == self or hurtbox.get_parent() == self:
			continue
		if hurtbox.health_component != null:
			hurtbox.health_component.heal(amount, owner_actor, data.get_label())
	if owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(StringName(str(kind) + "_pulse"), {"position": global_position, "radius": radius})


func _draw() -> void:
	super()
	var radius := get_value(&"radius") if is_instance_valid(owner_actor) else 0.0
	if radius > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(0.4, 1, 0.6, 0.08))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.4, 1, 0.6, 0.45), 2.0, true)
