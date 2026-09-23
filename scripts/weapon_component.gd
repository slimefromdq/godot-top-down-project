extends Node2D
class_name WeaponComponent

@export_flags_2d_physics var projectile_collision_mask: int
@export var mag_capacity: int = 30
@export_range(0.01, 100.0, 0.01) var fire_rate: float = 0.8
@export var reload_duration: float = 1.0
@export var damage: float = 20.0
@export var projectile_speed: float = 1000.0
@export_range(0.1, 3.0, 0.1) var projectile_scale: float = 1.0

@onready var muzzle: Marker2D = $Muzzle

var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")

# These paths are relative to WeaponComponent, because the timers are its children.
@onready var fire_cooldown_timer: FireCooldownTimer = $FireCooldownTimer
@onready var reload_timer: ReloadTimer = $ReloadTimer

# These values describe this particular weapon's current state. They are kept
# separate from the exported configuration values above.
var current_ammo: int
var is_reloading: bool = false
var is_disarmed: bool = false

signal ammo_changed(current: float, capacity: float)

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

	if current_ammo <= 0:
		return

	# A running one-shot timer means the previous shot is still cooling down.
	if not fire_cooldown_timer.is_stopped():
		return

	_fire()


func _fire() -> void:
	current_ammo -= 1
	ammo_changed.emit(current_ammo, mag_capacity)

	# fire_rate is expressed as shots per second, so its reciprocal is the
	# number of seconds that must pass before another shot is allowed.
	fire_cooldown_timer.start(1.0 / fire_rate)

	# This confirms the state loop works before projectile spawning is added.
	var new_bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(new_bullet)
	new_bullet.collision_mask = projectile_collision_mask
	new_bullet.global_position = muzzle.global_position
	new_bullet.global_rotation = muzzle.global_rotation
	new_bullet.bullet_direction = muzzle.global_transform.x.normalized()
	new_bullet.scale = Vector2.ONE * projectile_scale
	new_bullet.bullet_velocity = projectile_speed
	new_bullet.bullet_damage = damage


func try_reload() -> void:
	if is_reloading or current_ammo >= mag_capacity:
		return

	is_reloading = true
	reload_timer.start(reload_duration)
	print("Reloading...")


func _on_reload_timer_timeout() -> void:
	# There is no reserve-ammo system yet, so a completed reload fills the
	# magazine. Reserve ammo can be accounted for here later.
	current_ammo = mag_capacity
	ammo_changed.emit(current_ammo, mag_capacity)
	is_reloading = false
	print("Reload complete. Ammo: %d/%d" % [current_ammo, mag_capacity])
