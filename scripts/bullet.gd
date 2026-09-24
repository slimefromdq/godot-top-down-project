extends Area2D

# Shared projectile script for the primary-weapon bullet and the skillshot.
# Everything visual about a projectile lives in its scene (sprite, particles,
# trail); the impact look and sound are set below.

@export var bullet_velocity: float
@export var bullet_damage: float
## How many extra hurtboxes the projectile passes through. 0 = stops on first hit.
@export var pierce: int = 0
## Knockback impulse applied along the flight direction.
@export var knockback: float = 0.0
## Optional status applied to everything it hits.
@export var status_effect: StatusEffect

@export_group("Presentation")
## Spawned where the projectile hits a hurtbox.
@export var hit_effect: PackedScene
## Spawned where the projectile hits a wall or expires against one.
@export var wall_effect: PackedScene
@export var hit_sound: SoundCue
@export var wall_sound: SoundCue

var bullet_direction = Vector2.RIGHT
# The actor that fired this. Set by whoever spawns the projectile.
var source: Node = null

var _already_hit: Array[Area2D] = []


func _physics_process(delta: float) -> void:
	global_position += bullet_direction * bullet_velocity * delta


func _on_expiry_timer_timeout() -> void:
	queue_free()


func _on_body_entered(_body: Node2D) -> void:
	_impact(wall_effect, wall_sound)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if not area is HurtboxComponent or area in _already_hit:
		return
	_already_hit.append(area)

	# The shooter may have died while this was in flight. A freed object can't
	# be passed as a typed Node, so the hit just loses its kill credit.
	var shooter: Node = source if is_instance_valid(source) else null
	var hit := HitData.create(bullet_damage, shooter)
	hit.knockback = bullet_direction * knockback
	hit.status_effect = status_effect
	area.take_hit(hit)
	_impact(hit_effect, hit_sound)

	if _already_hit.size() > pierce:
		queue_free()


func _impact(effect: PackedScene, sound: SoundCue) -> void:
	EffectSpawner.spawn(self, effect, {
		"position": global_position,
		"direction": bullet_direction,
	})
	AudioManager.play_sfx(sound, global_position)
