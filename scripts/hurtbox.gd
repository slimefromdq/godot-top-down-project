extends Area2D
class_name HurtboxComponent

# The part of an actor that can be hit. Attackers find it (Hitbox queries,
# projectiles) and hand it a DamageInfo; it routes each part of the hit to the
# right component, so an attacker never needs to know what it hit.

@export var health_component: HealthComponent
## Optional. Lets hits apply buffs/debuffs to this target.
@export var status_component: StatusEffectComponent
## Optional. Lets hits knock this target back.
@export var movement_component: MovementComponent
## Radius used for melee arc checks when the shape isn't a circle.
@export var fallback_radius: float = 40.0


func take_damage(amount: float, source: Node = null) -> void:
	take_hit(DamageInfo.create(amount, source))


# Damage first, then statuses and knockback, so a killing blow doesn't also
# stun a corpse, and the target's revive (about_to_die) sees the hit before
# any CC lands.
func take_hit(info: DamageInfo) -> void:
	if health_component == null or is_untargetable():
		return
	health_component.apply_damage(info)
	if health_component.is_dead():
		return
	if status_component != null:
		for effect in info.statuses:
			status_component.apply(effect, info.source, info.direction)
	if movement_component != null and info.knockback != Vector2.ZERO:
		movement_component.apply_knockback(info.knockback)


# Abilities use this to reject targets that are already dead.
func is_valid_target() -> bool:
	return monitorable and health_component != null and not health_component.is_dead() \
		and not is_untargetable()


# An untargetable status (a vanish) makes every attack, zone and status skip us.
func is_untargetable() -> bool:
	return status_component != null and status_component.is_untargetable()


# Team of the actor this hurtbox belongs to (empty = neutral, hit by anyone).
func get_team() -> StringName:
	var root := owner if owner != null else get_parent()
	var team = root.get(&"team") if root != null else null
	return team if team != null else &""


# Rough size, for "does the arc touch this target" checks.
func get_radius() -> float:
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			return child.shape.radius * absf(child.global_scale.x)
	return fallback_radius
