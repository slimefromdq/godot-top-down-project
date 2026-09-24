extends Node2D
class_name WeaponComponent

@export_flags_2d_physics var projectile_collision_mask: int
@export var mag_capacity: int = 30
@export_range(0.01, 100.0, 0.01) var fire_rate: float = 0.8
@export var reload_duration: float = 1.0
@export var damage: float = 20.0
@export var projectile_speed: float = 1000.0
@export_range(0.1, 3.0, 0.1) var projectile_scale: float = 1.0
## Random spread in degrees on each side of the aim line. Rapid-fire weapons
## feel better with a little spray.
@export_range(0.0, 45.0, 0.5) var spread_degrees: float = 0.0
## Bullet scene to spawn. Swap it for a differently styled projectile.
@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
## Optional. Reads fire_rate and damage multipliers from active status effects.
@export var status_component: StatusEffectComponent

@onready var muzzle: Marker2D = $Muzzle

# These paths are relative to WeaponComponent, because the timers are its children.
@onready var fire_cooldown_timer: FireCooldownTimer = $FireCooldownTimer
@onready var reload_timer: ReloadTimer = $ReloadTimer

# These values describe this particular weapon's current state. They are kept
# separate from the exported configuration values above.
var current_ammo: int
var is_reloading: bool = false
var is_disarmed: bool = false

signal ammo_changed(current: float, capacity: float)
# Presentation hooks. The Actor turns these into "fire", "reload",
# "reload_done" and "dry_fire" cues for the visuals and audio components.
signal fired(muzzle_position: Vector2, direction: Vector2)
signal reload_started
signal reload_finished
signal dry_fired

func _ready() -> void:
	# Initialize this after the scene loads so an Inspector override of
	# mag_capacity is respected.
	current_ammo = mag_capacity
	reload_timer.timeout.connect(_on_reload_timer_timeout)


# This is a public request: callers do not need to know why firing may fail.
func try_fire() -> void:
	if is_reloading:
		return

	if is_disarmed:
		return

	# A running one-shot timer means the previous shot is still cooling down.
	if not fire_cooldown_timer.is_stopped():
		return

	if current_ammo <= 0:
		# Reuse the fire cooldown so a held trigger clicks at the fire rate
		# instead of every frame.
		fire_cooldown_timer.start(0.25)
		dry_fired.emit()
		return

	_fire()


func get_fire_rate() -> float:
	return fire_rate * StatusEffectComponent.multiplier_of(status_component, StatusEffect.FIRE_RATE)


func get_damage() -> float:
	return damage * StatusEffectComponent.multiplier_of(status_component, StatusEffect.DAMAGE)


func _fire() -> void:
	current_ammo -= 1
	ammo_changed.emit(current_ammo, mag_capacity)

	# fire_rate is expressed as shots per second, so its reciprocal is the
	# number of seconds that must pass before another shot is allowed.
	fire_cooldown_timer.start(1.0 / get_fire_rate())

	var direction := muzzle.global_transform.x.normalized()
	if spread_degrees > 0.0:
		direction = direction.rotated(deg_to_rad(randf_range(-spread_degrees, spread_degrees)))

	var new_bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(new_bullet)
	new_bullet.collision_mask = projectile_collision_mask
	new_bullet.global_position = muzzle.global_position
	new_bullet.global_rotation = direction.angle()
	new_bullet.bullet_direction = direction
	new_bullet.scale = Vector2.ONE * projectile_scale
	new_bullet.bullet_velocity = projectile_speed
	new_bullet.bullet_damage = get_damage()
	new_bullet.source = owner

	fired.emit(muzzle.global_position, direction)


# Used by abilities such as Overdrive that top the magazine up instantly.
func refill() -> void:
	reload_timer.stop()
	is_reloading = false
	current_ammo = mag_capacity
	ammo_changed.emit(current_ammo, mag_capacity)


func try_reload() -> void:
	if is_reloading or current_ammo >= mag_capacity:
		return

	is_reloading = true
	reload_timer.start(reload_duration)
	reload_started.emit()


func _on_reload_timer_timeout() -> void:
	# There is no reserve-ammo system yet, so a completed reload fills the
	# magazine. Reserve ammo can be accounted for here later.
	current_ammo = mag_capacity
	ammo_changed.emit(current_ammo, mag_capacity)
	is_reloading = false
	reload_finished.emit()
