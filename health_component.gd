extends Node
class_name HealthComponent

signal died
@export var max_health: float = 200.0

var current_health: float


func _ready() -> void:
	current_health = max_health


func take_damage(amount: float) -> void:
	current_health -= amount
	current_health = max(current_health, 0.0)

	print("Health: ", current_health)

	if current_health <= 0.0:
		died.emit()
