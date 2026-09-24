extends RefCounted
class_name HitData

# Everything one hit carries. Projectiles and abilities build one of these and
# hand it to a HurtboxComponent, so the target never has to know what hit it.

var damage: float = 0.0
# The actor (or other node) responsible for the hit. Used for kill credit, so
# the attacker's kill effect and kill sound can play on the victim.
var source: Node = null
# World-space impulse. Ignored by targets without a MovementComponent.
var knockback: Vector2 = Vector2.ZERO
# Optional status applied on hit, e.g. a slow.
var status_effect: StatusEffect = null


static func create(amount: float, from: Node = null) -> HitData:
	var hit := HitData.new()
	hit.damage = amount
	hit.source = from
	return hit
