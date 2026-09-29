extends Deployable
class_name TurretDeployable

# A placed gun: shoots the data's projectile at the nearest enemy it can see
# within values/range, values/fire_rate shots per second, each shot the
# data's `damage` (owner's stats at placement). Stunned or silenced = holds
# fire. Owner cue: <kind>_fire (context.position, .direction) per shot.

var _cooldown: float = 0.0
var _damage: float = 0.0
var _aim := Vector2.RIGHT


func _deploy_ready() -> void:
	_damage = data.damage.evaluate(get_owner_stats()) if data.damage != null else 0.0


func _deploy_tick(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0 or is_disabled():
		return
	var targets := find_enemies(get_value(&"range"))
	if targets.is_empty():
		return
	_aim = global_position.direction_to(targets[0].global_position)
	fire_projectile(_aim, _damage, data.damage_type, data.get_label())
	var rate := maxf(get_value(&"fire_rate"), 0.01)
	_cooldown += 1.0 / rate
	_cooldown = maxf(_cooldown, 0.0)
	if owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(StringName(str(kind) + "_fire"), {"position": global_position, "direction": _aim})


func _draw() -> void:
	super()
	if data.visual_scene == null:
		draw_line(Vector2.ZERO, _aim * (data.body_radius + 18.0), Color(0.2, 0.2, 0.22), 10.0)
