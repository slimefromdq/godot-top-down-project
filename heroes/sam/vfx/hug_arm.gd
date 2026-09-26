extends Node2D

# Cosmetic, Hug's projectile visual: a long stretchy lilac arm from Sam to the
# hand (the projectile), so the hug reads as reaching across the screen.

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var projectile := get_parent() as Projectile
	if projectile == null or projectile.damage_template == null or not is_instance_valid(projectile.damage_template.source):
		draw_circle(Vector2.ZERO, 16.0, Color(0.8, 0.7, 1.0))
		return
	var from: Vector2 = to_local(projectile.damage_template.source.global_position)
	draw_line(from, Vector2.ZERO, Color(0.78, 0.68, 1.0), 12.0, true)
	draw_circle(Vector2.ZERO, 18.0, Color(0.85, 0.75, 1.0))
