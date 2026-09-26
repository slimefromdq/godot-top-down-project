extends Node2D

# Cosmetic: Pike's knives orbiting her, one per round left in the gun (her
# ammo counter). The orbit tightens while she's unseen (Obsession).

var gun: RangedAttackAbility
var _angle: float = 0.0


func _process(delta: float) -> void:
	_angle += delta * 2.4
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(gun):
		return
	var count := gun.get_ammo()
	var passive = gun.controller.get_ability_for_slot(&"passive") if gun.controller != null else null
	var tight: bool = passive != null and passive.has_method(&"is_unseen") and passive.is_unseen()
	var radius := 42.0 if tight else 60.0
	for i in count:
		var dir := Vector2.RIGHT.rotated(_angle + TAU * i / maxf(gun.get_max_ammo(), 1.0))
		var at := dir * radius
		draw_line(at - dir.orthogonal() * 9.0, at + dir.orthogonal() * 9.0, Color(0.9, 0.92, 0.96), 3.0, true)
		draw_circle(at - dir.orthogonal() * 11.0, 4.0, Color(1.0, 0.45, 0.7))
