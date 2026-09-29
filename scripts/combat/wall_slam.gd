extends RefCounted
class_name WallSlam

# The wall-slam bonus. Any knockback can be made slam-capable by giving its
# push status a StatusEffect.slam_bonus_ratio: HurtboxComponent then arms the
# knock (MovementComponent.arm_slam) with ratio x the hit's damage. If the
# knocked body hits a wall on GameRules.wall_impact_mask during the knock,
# it takes that bonus scaled by impact speed:
#
#   bonus = armed x clamp(impact_speed / GameRules.wall_slam_full_speed, 0, 1)
#
# as PHYSICAL damage from whoever knocked it (label "wall_slam", tag
# "wall_slam"). CombatEvents.wall_slammed and the body's `wall_slam` cue
# report it for VFX and sound. Unflagged knockbacks still thud (wall_impact)
# but deal nothing extra.

const LABEL := &"wall_slam"


static func bonus_for(armed: float, impact_speed: float) -> float:
	var full := maxf(GameRules.current().wall_slam_full_speed, 1.0)
	return armed * clampf(impact_speed / full, 0.0, 1.0)


static func resolve(body: Node2D, source: Node, armed: float, impact_speed: float, at: Vector2, normal: Vector2) -> float:
	var hurtbox := body.get_node_or_null(^"Hurtbox") as HurtboxComponent
	var amount := bonus_for(armed, impact_speed)
	if hurtbox == null or amount <= 0.0 or not hurtbox.is_valid_target():
		return 0.0
	var info := DamageInfo.create(amount, source if is_instance_valid(source) else null)
	info.label = LABEL
	info.tags.append(LABEL)
	info.direction = -normal
	info.hit_position = at
	hurtbox.health_component.apply_damage(info)
	CombatEvents.wall_slammed.emit(body, info.source, info.final_amount, impact_speed, at)
	if body.has_method(&"trigger_cue"):
		body.trigger_cue(&"wall_slam", {"position": at, "direction": -normal, "impact_speed": impact_speed,
			"damage": info.final_amount})
	return info.final_amount
