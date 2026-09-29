@tool
extends AbilityData
class_name DeployData

# Data for DeployAbility: place a Deployable (a turret, a healing post, a
# drone, a tentacle) at the cursor or at the caster. The object's own
# behaviour is `deployable_script` (extends Deployable); its numbers live
# here, as fields for the common parts and named `values` for the rest
# (a turret's values/fire_rate, a healer's values/heal_per_second), so the
# debug panel and CSV see them.
#
# Every deployable has an owner (the caster) and a team, optional health
# (hittable and destroyable by enemies), a lifetime, a cap per owner, and is
# removed when its owner dies.

@export_group("Deployable")
## The behaviour. Must extend Deployable (TurretDeployable, AuraDeployable,
## MoteDrone, or a hero's own).
@export var deployable_script: Script
## Max health (from the OWNER's stats at placement). Empty = can't be hit.
@export var deploy_health: ScalingValue
## Seconds it lasts. 0 = until destroyed (or its owner dies).
@export var lifetime: float = 10.0
## Most of this kind one owner may have. Placing another removes the oldest,
## unless block_while_capped.
@export var max_per_owner: int = 1
## At the cap, refuse the cast ("Already deployed") instead of replacing.
@export var block_while_capped: bool = false
## The cooldown starts when the deployable is gone (destroyed or expired),
## not when it is placed (a drone: 20 s after it's shot down).
@export var cooldown_after_gone: bool = false
## Place it at the caster's feet instead of the cursor.
@export var place_at_caster: bool = false
## Farthest placement from the caster (the cursor is clamped). 0 = anywhere.
@export var place_range: float = 500.0
## Body size (hurtbox and drawing).
@export var body_radius: float = 32.0
## Projectile it shoots (turrets, a tentacle), if any.
@export var projectile: ProjectileData
## Placeholder look (drawn when no visual_scene).
@export var color: Color = Color(0.8, 0.8, 0.7, 1)
## Sprite slot: a scene instanced as its look (replaces the drawn shape).
@export var visual_scene: PackedScene


func get_range() -> float:
	if ability_range > 0.0:
		return ability_range
	return 0.0 if place_at_caster else place_range


func get_scaling_values() -> Dictionary:
	var result := super()
	if deploy_health != null:
		result["deploy_health"] = deploy_health
	return result


func get_balance_metrics(_level: int, _weapon: float, _magic: float) -> Dictionary:
	return {"lifetime": lifetime, "max_per_owner": max_per_owner}


func validate() -> PackedStringArray:
	var problems := super()
	if deployable_script == null:
		problems.append("'%s' has no deployable_script" % id)
	if lifetime < 0.0 or place_range < 0.0 or body_radius <= 0.0 or max_per_owner < 1:
		problems.append("'%s' has invalid deployable numbers" % id)
	if projectile != null and projectile.has_negative():
		problems.append("'%s' projectile has negative values" % id)
	return problems
