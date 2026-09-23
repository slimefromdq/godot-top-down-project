extends ProgressBar
class_name HealthBar

@export var health_component: HealthComponent

func _ready() -> void:
	health_component.health_changed.connect(_on_health_changed)
	max_value = health_component.max_health
	value = health_component.current_health
	

func _on_health_changed(current: float, maximum: float) -> void:
	max_value = maximum
	value = current
