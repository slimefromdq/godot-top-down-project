extends Ability
class_name TargetedAbility

# INSTANT CLICK-CAST: press it with the cursor over a valid target and it
# lands immediately; there is no projectile to dodge. With no target under
# the cursor, out of range, or behind a wall, it fails and costs nothing.
#
# Cues: <ability_id> on the caster with context.target_position (use it for a
# beam), and <ability_id>_hit on the caster with position = the target.

@export var damage: float = 45.0
@export var cast_range: float = 700.0
## How close to the cursor a target has to be, in pixels. Generous values feel better.
@export var pick_radius: float = 70.0
## Which hurtboxes count as valid targets (Enemy Hurtbox for the player).
@export_flags_2d_physics var target_mask: int = 16
## Layers that block line of sight. Set to 0 to ignore walls.
@export_flags_2d_physics var line_of_sight_mask: int = 1
@export var status_effect: StatusEffect

var _pick_shape := CircleShape2D.new()


# Public so the player can highlight whatever is currently targetable.
func find_target(point: Vector2) -> HurtboxComponent:
	_pick_shape.radius = pick_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _pick_shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = target_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var best: HurtboxComponent = null
	var best_distance := INF
	for result in actor.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var hurtbox := result.collider as HurtboxComponent
		if hurtbox == null or not hurtbox.is_valid_target():
			continue
		var distance := hurtbox.global_position.distance_to(point)
		if distance < best_distance:
			best = hurtbox
			best_distance = distance
	return best


func _activate(target_position: Vector2) -> String:
	var target := find_target(target_position)
	if target == null:
		return "No target"
	if actor.global_position.distance_to(target.global_position) > cast_range:
		return "Out of range"
	if _is_blocked(target.global_position):
		return "Blocked"

	var hit := HitData.create(
		damage * actor.status_component.get_multiplier(StatusEffect.DAMAGE), actor)
	hit.status_effect = status_effect
	target.take_hit(hit)

	actor.trigger_cue(ability_id, {
		"target": target.owner,
		"target_position": target.global_position,
		"direction": (target.global_position - actor.global_position).normalized(),
	})
	actor.trigger_cue(StringName(str(ability_id) + "_hit"), {
		"position": target.global_position,
		"target": target.owner,
	})
	return ""


func _is_blocked(point: Vector2) -> bool:
	if line_of_sight_mask == 0:
		return false
	var query := PhysicsRayQueryParameters2D.create(actor.global_position, point, line_of_sight_mask)
	query.exclude = [actor.get_rid()]
	return not actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
