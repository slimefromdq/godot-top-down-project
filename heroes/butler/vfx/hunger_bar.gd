extends Node2D

# Cosmetic: Butler's Hunger as a thin wine-red bar over his head, drawn for
# everyone (allies know the cloak is about to drop, enemies know when to back
# off). Reads the passive; no gameplay.

var hunger: Node    # the Hunger passive


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(hunger):
		return
	var ratio: float = hunger.get_hud_meter()
	var width := 90.0
	var top := Vector2(-width / 2.0, -118.0)
	draw_rect(Rect2(top, Vector2(width, 8)), Color(0, 0, 0, 0.6))
	var color := Color(0.55, 0.05, 0.12) if not hunger.is_starving() else Color(0.95, 0.15, 0.2)
	draw_rect(Rect2(top, Vector2(width * ratio, 8)), color)
