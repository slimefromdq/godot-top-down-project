extends Node2D
class_name GameMap

# Root node of a playable map. Other systems find the map through the
# "game_map" group instead of hard-coded paths (the debug overview uses
# `bounds`; a future match manager would use the spawn points).

## The playable area, in the map's coordinates.
@export var bounds := Rect2(-4800, -4860, 9600, 9720)


func _ready() -> void:
	add_to_group(&"game_map")


## Spawn markers for a team, e.g. &"a" or &"b" (Marker2D nodes in group spawn_<team>).
func get_spawn_points(team: StringName) -> Array[Node2D]:
	var points: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(StringName("spawn_%s" % team)):
		if is_ancestor_of(node):
			points.append(node)
	return points
