@tool
extends Resource
class_name AllyTargeting

# Put one on an AbilityData to make the ability ally-targeted: the cast
# picks the best ally under/near the aim point (closest to it, within
# snap_radius of it and cast_range of the caster). With no valid ally the
# cast fails ("No ally") and spends nothing. The chosen ally is
# Ability.cast_ally for the rest of the cast. Team rules come from
# Hitbox.is_ally (teammates, and the caster itself if allow_self).
#
# The local player's input highlights the candidate while the ability is
# ready (PlayerHeroInput), like the legacy Arc Zap highlight.

## Max distance from the caster to the ally.
@export var cast_range: float = 700.0
## How far from the aim point an ally may be and still be picked.
@export var snap_radius: float = 120.0
@export var allow_self: bool = false
## Walls (GameRules.wall_mask) between caster and ally block the cast.
@export var requires_line_of_sight: bool = true


func has_negative() -> bool:
	return cast_range < 0.0 or snap_radius < 0.0


# The best ally for `caster` near `point`, or null.
func find(caster: Node2D, point: Vector2) -> HurtboxComponent:
	if caster == null or not caster.is_inside_tree():
		return null
	var circle := CircleShape2D.new()
	circle.radius = snap_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = GameRules.current().hurtbox_mask
	var best: HurtboxComponent = null
	var best_distance := INF
	for hit in caster.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var hurtbox := hit.collider as HurtboxComponent
		if hurtbox == null or not Hitbox.is_ally(caster, hurtbox):
			continue
		var is_self := hurtbox.owner == caster or hurtbox.get_parent() == caster
		if is_self and not allow_self:
			continue
		if caster.global_position.distance_to(hurtbox.global_position) > cast_range:
			continue
		if requires_line_of_sight and not is_self and _blocked(caster, hurtbox.global_position):
			continue
		var distance := hurtbox.global_position.distance_to(point)
		if distance < best_distance:
			best = hurtbox
			best_distance = distance
	return best


static func _blocked(caster: Node2D, to: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(caster.global_position, to, GameRules.current().wall_mask)
	return not caster.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()
