extends Node
class_name HealthComponent

signal health_changed(current: float, maximum: float)

signal died
@export var max_health: float = 200.0

var current_health: float


func _ready() -> void:
	current_health = max_health



func take_damage(amount: float) -> void:
	if current_health <= 0.0:      # top: "was I ALREADY dead before this hit?"
		return

	current_health -= amount
	current_health = max(current_health, 0.0)
	health_changed.emit(current_health, max_health)

	print("Health: ", current_health)

	if current_health <= 0.0:      # bottom: "did THIS hit kill me?"
		died.emit()
