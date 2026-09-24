extends Area2D
class_name HurtboxComponent

@export var health_component: HealthComponent
## Optional. Lets hits apply buffs/debuffs to this target.
@export var status_component: StatusEffectComponent
## Optional. Lets hits knock this target back.
@export var movement_component: MovementComponent


func take_damage(amount: float, source: Node = null) -> void:
	take_hit(HitData.create(amount, source))


func take_hit(hit: HitData) -> void:
	if status_component != null and hit.status_effect != null:
		status_component.apply(hit.status_effect)
	if movement_component != null and hit.knockback != Vector2.ZERO:
		movement_component.apply_knockback(hit.knockback)
	health_component.take_damage(hit.damage, hit.source)


# Abilities use this to reject targets that are already dead.
func is_valid_target() -> bool:
	return monitorable and health_component != null and not health_component.is_dead()
