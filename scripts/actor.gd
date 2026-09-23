extends CharacterBody2D
class_name Actor

# Shared setup for every character built from actor.tscn. Player and enemy
# scripts extend this and only add their own control logic.

@onready var movement_component: MovementComponent = $Components/MovementComponent

@onready var weapon_component: WeaponComponent = $WeaponPivot/WeaponComponent

@onready var health_component: HealthComponent = $Components/HealthComponent

@onready var weapon_pivot: Node2D = $WeaponPivot


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health_component.died.connect(_on_died)


# Override this to react to death differently, e.g. a game-over screen.
func _on_died() -> void:
	queue_free()
