extends Node2D
class_name SightLinesOverlay

# Debug overlay (F1 > Tools > Sight lines): a line from the player to every
# nearby non-allied unit, green when the player can see it and red when it's
# blocked (CombatQueries.has_line_of_sight: walls or a bush). DebugTools adds
# it to the current map while the toggle is on.

@export var max_distance: float = 1400.0
@export var clear_color := Color(0.3, 1.0, 0.4, 0.8)
@export var blocked_color := Color(1.0, 0.3, 0.3, 0.8)
@export var width: float = 3.0


func _ready() -> void:
	z_index = 100
	z_as_relative = false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var my_team := CombatQueries.team_of(player)
	for node in get_tree().get_nodes_in_group(&"minimap_units"):
		var unit := node as Node2D
		if unit == null or unit == player or StatusEffectComponent.is_actor_gone(unit):
			continue
		if my_team != &"" and CombatQueries.team_of(unit) == my_team:
			continue
		if unit.global_position.distance_to(player.global_position) > max_distance:
			continue
		var seen := CombatQueries.has_line_of_sight(player, unit)
		draw_line(to_local(player.global_position), to_local(unit.global_position),
			clear_color if seen else blocked_color, width)
