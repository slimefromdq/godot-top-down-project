extends Area2D

@export var bullet_velocity: float
@export var bullet_damage: float
var bullet_direction = Vector2.RIGHT

func _physics_process(delta: float) -> void:
	global_position += bullet_direction * bullet_velocity * delta

func _on_expiry_timer_timeout() -> void:
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	print("Bullet hit: ", body.name)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		area.take_damage(bullet_damage)
		queue_free()
