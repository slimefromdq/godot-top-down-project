@tool
extends Resource
class_name AttackStep

# One swing of a melee combo. Each step has its own reach, damage, weight and
# optional projectile, so "the third hit is a big finisher" is just a third
# AttackStep with a bigger arc, more knockback and the "finisher" feel preset.

@export var hit_shape: HitShape
@export var damage: ScalingValue
@export var knockback: float = 0.0
## Feel preset from the hero's FeelProfile (light / heavy / finisher).
@export var feel_preset: StringName = &"light"
@export var feel_override: AttackFeel
## Optional status on hit (adds to the ability's on_hit_status).
@export var on_hit_status: StatusEffect
## Damage-meter label. Empty = the ability's label.
@export var meter_label: StringName = &""

@export_group("Projectile")
## Projectile launched when this swing's active frames start. Empty = use the
## ability's swing_projectile (if any).
@export var projectile: ProjectileData
@export var projectile_damage: ScalingValue


func has_negative() -> bool:
	return knockback < 0.0 \
		or (hit_shape != null and hit_shape.has_negative()) \
		or (feel_override != null and feel_override.has_negative()) \
		or (damage != null and damage.has_negative()) \
		or (projectile != null and projectile.has_negative()) \
		or (projectile_damage != null and projectile_damage.has_negative())
