extends Ability
class_name SkillshotAbility

# SKILLSHOT: fires a projectile in the aimed direction. It hits whatever is in
# its path, so it rewards leading your target and can miss entirely.
#
# Cues: <ability_id> at the caster when fired. The projectile scene carries
# its own sprite/trail plus hit/wall effects and sounds.

@export var projectile_scene: PackedScene = preload("res://scenes/skillshot_projectile.tscn")
@export_flags_2d_physics var collision_mask: int = 17
@export var damage: float = 60.0
@export var speed: float = 1400.0
@export var pierce: int = 3
@export var knockback: float = 700.0
@export var status_effect: StatusEffect


func _activate(target_position: Vector2) -> String:
	var origin := actor.weapon_component.muzzle.global_position if actor.weapon_component != null \
		else actor.global_position
	var direction := (target_position - actor.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = actor.aim_direction

	var projectile = projectile_scene.instantiate()
	actor.get_tree().current_scene.add_child(projectile)
	projectile.collision_mask = collision_mask
	projectile.global_position = origin
	projectile.global_rotation = direction.angle()
	projectile.bullet_direction = direction
	projectile.bullet_velocity = speed
	projectile.bullet_damage = damage * actor.status_component.get_multiplier(StatusEffect.DAMAGE)
	projectile.pierce = pierce
	projectile.knockback = knockback
	projectile.source = actor
	if status_effect != null:
		projectile.status_effect = status_effect

	actor.trigger_cue(ability_id, {"position": origin, "direction": direction})
	return ""
