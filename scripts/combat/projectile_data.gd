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
## Knockback impulse along the flight direction.
@export var knockback: float = 0.0
## Optional status applied to everything it hits.
@export var on_hit_status: StatusEffect

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


func has_negative() -> bool:
	return speed < 0.0 or lifetime < 0.0 or radius < 0.0 or knockback < 0.0 or pierce < -1
