extends Node2D
class_name IslandExit

# The Island's one way out besides the timer. An interactable: press the
# interact key beside it to go home at once. The IslandDirector decides who
# may use it (only someone on the Island).

const RADIUS := 200.0

var _t := 0.0


func _enter_tree() -> void:
	add_to_group(MapEvents.INTERACTABLES)
	add_to_group(&"island_exits")


func get_prompt(_hero: Hero) -> String:
	return "Leave the Island"


func get_interact_radius() -> float:
	return RADIUS


func can_interact(hero: Hero) -> bool:
	return hero != null and not hero.health_component.is_dead() \
		and hero.global_position.distance_to(global_position) <= RADIUS


func _process(delta: float) -> void:
	_t += delta
	if ScreenCull.is_near(self, 300.0):
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(6, 10), 90.0, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, 90.0, Color("134e4a"))
	draw_circle(Vector2.ZERO, 72.0, Color("2dd4bf"))
	for k in 3:
		var start := -_t * 2.0 + k * TAU / 3.0
		draw_arc(Vector2.ZERO, 30.0 + 14.0 * k, start, start + 1.5, 16, Color(1, 1, 1, 0.8), 5.0, true)
