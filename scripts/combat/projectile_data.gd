@tool
extends Resource
class_name ProjectileData

# How a projectile flies and what it looks like. How much damage it does is
# decided by whoever fires it (the ability), because the same crescent might
# be fired by different abilities with different ratios.

@export var speed: float = 1200.0
## Seconds before it fizzles. Range = speed * lifetime.
@export var lifetime: float = 0.5
## Extra targets it passes through. 0 = stops at the first; -1 = unlimited.
@export var pierce: int = 0
## Collision radius used to find hurtboxes.
@export var radius: float = 30.0
## Stopped by walls (GameRules.wall_mask).
@export var stops_at_walls: bool = true
## Lobbed (a grenade, a canister): flies over walls and heads to the shooter's
## aim point, at most max range (speed x lifetime) away, hitting nothing on
## the way, and expires there. Pair it with explode_on_expire.
@export var lobbed: bool = false
## Knockback impulse along the flight direction.
@export var knockback: float = 0.0
## Optional status applied to everything it hits.
@export var on_hit_status: StatusEffect

@export_group("Return")
## Boomerang: fly to max range (speed x lifetime) along the aim, then home
## back to the caster's CURRENT position and vanish on reaching them. A wall
## (or running out of pierce) on the way out turns it around early; the way
## back passes through walls so it always comes home. Each target can be
## hit once per pass; return-pass hits carry the tag Projectile.TAG_RETURN.
@export var return_to_caster: bool = false
## Bends both passes into a crescent: the sideways bulge, as a fraction of
## the pass length (0 = straight out and back). Negative bends the other way.
@export var curve_amount: float = 0.0
## Safety net: gone after this many seconds even if it never gets back.
@export var return_timeout: float = 4.0

@export_group("Explosion")
## Explode on the first target hit: the explosion replaces the direct hit,
## so the hit target takes the blast like everyone else (no double hit).
@export var explode_on_hit: bool = false
## Explode where it expires: max range, or a wall.
@export var explode_on_expire: bool = false
## The blast area (a CIRCLE; forward_offset is along the flight).
@export var explosion_shape: HitShape
## Blast damage = the shot's damage x this ...
@export var explosion_damage_multiplier: float = 1.0
## ... unless this is set: its own number, from the firer's stats.
@export var explosion_damage: ScalingValue
## Applied to enemies in the blast (team rules: Hitbox.can_hit).
@export var explosion_status: StatusEffect
## Applied to allies in the blast, the firer included (Hitbox.is_ally).
@export var explosion_ally_status: StatusEffect
## Damage-meter label for the blast. Empty = the shot's label.
@export var explosion_label: StringName = &""
@export var explosion_effect: PackedScene
@export var explosion_sound: SoundCue
## Ground zone left where it explodes (a gas cloud, a fire pool). Its owner is
## the shooter.
@export var explosion_zone: GroundZoneData

@export_subgroup("Split")
## On exploding, fire `split_count` copies of split_projectile in a fan
## from the blast point. Split projectiles never split again.
@export var split_on_explode: bool = false
@export var split_projectile: ProjectileData
@export var split_count: int = 3
## Total fan width in degrees, centred on the flight direction.
@export var split_fan_degrees: float = 60.0
## Each split projectile's damage = the shot's damage x this (a firing
## ability can override it per shot: Projectile.split_damage).
@export var split_damage_multiplier: float = 0.5

@export_group("Presentation")
## Scene instanced as the projectile's look (sprite, particles, trail). It is
## rotated to face the flight direction. Empty = a plain debug circle.
@export var visual_scene: PackedScene
## Spawned where it hits a hurtbox.
@export var hit_effect: PackedScene
## Spawned where it hits a wall or fizzles.
@export var expire_effect: PackedScene
@export var hit_sound: SoundCue
@export var expire_sound: SoundCue


func get_range() -> float:
	return speed * lifetime


func explodes() -> bool:
	return (explode_on_hit or explode_on_expire) and explosion_shape != null


func has_negative() -> bool:
	return speed < 0.0 or lifetime < 0.0 or radius < 0.0 or knockback < 0.0 or pierce < -1 \
		or explosion_damage_multiplier < 0.0 or split_count < 0 or split_fan_degrees < 0.0 \
		or split_damage_multiplier < 0.0 or (explosion_shape != null and explosion_shape.has_negative()) \
		or (explosion_damage != null and explosion_damage.has_negative())


# Problems a designer should fix (RangedAttackData.validate includes these).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if has_negative():
		problems.append("projectile has negative values")
	if (explode_on_hit or explode_on_expire) and explosion_shape == null:
		problems.append("projectile explodes but has no explosion_shape")
	if split_on_explode and (split_projectile == null or not (explode_on_hit or explode_on_expire)):
		problems.append("projectile splits but has no split_projectile or never explodes")
	for effect in [on_hit_status, explosion_status, explosion_ally_status]:
		if effect != null:
			for problem in effect.validate():
				problems.append("projectile " + problem)
	return problems
