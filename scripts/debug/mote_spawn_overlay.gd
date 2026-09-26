extends Node2D
class_name MoteSpawnOverlay

# Debug overlay for the M map view (F1 > Match > "Mote spawns on the map"):
# every trickle point (gold dot, ringed if a Mote sits on it), each dreaming
# zone (outlined, named, the active pair filled) with its spawn points, and
# the Dream Mote spot. Lives in the "map_overview" group, so MapDebugView
# shows it only while zoomed out.


func _ready() -> void:
	add_to_group(&"map_overview")
	z_index = 110
	var view := get_tree().current_scene.get_node_or_null(^"MapDebugView") as MapDebugView
	visible = view != null and view.is_overview()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var director := MoteDirector.find(get_tree())
	for node in get_tree().get_nodes_in_group(DreamZone.GROUP):
		var zone := node as DreamZone
		var shape: CollisionPolygon2D = null
		for child in zone.get_children():
			if child is CollisionPolygon2D:
				shape = child
		if shape == null:
			continue
		var points := zone.global_transform * shape.polygon
		var active := director != null and director.get_active_pair() == zone.pair_id
		if active:
			draw_colored_polygon(points, Color(0.8, 0.6, 1.0, 0.3))
		draw_polyline(points + PackedVector2Array([points[0]]), Color(0.75, 0.55, 1.0, 0.9), 16.0)
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= points.size()
		draw_string(font, center + Vector2(-260, -40), zone.display_name, HORIZONTAL_ALIGNMENT_CENTER, 520, 90,
			Color(0.95, 0.9, 1.0))
		for spawn in zone.get_spawn_points():
			draw_circle(spawn.global_position, 45.0, Color(0.75, 0.55, 1.0, 0.9))
	var loose: Array = director.get_loose_motes(true) if director != null else []
	for node in get_tree().get_nodes_in_group(&"mote_spawn"):
		var at: Vector2 = (node as Node2D).global_position
		draw_circle(at, 55.0, Color(1.0, 0.82, 0.2, 0.95))
		if loose.any(func(m): return m.global_position.distance_to(at) < MoteDirector.POINT_CLEARANCE):
			draw_arc(at, 95.0, 0.0, TAU, 24, Color.WHITE, 12.0)
	var dream := get_tree().get_first_node_in_group(&"dream_mote_spawn") as Node2D
	if dream != null:
		draw_circle(dream.global_position, 110.0, Color(0.95, 0.85, 1.0, 0.9))
		draw_string(font, dream.global_position + Vector2(-300, -150), "Dream Mote", HORIZONTAL_ALIGNMENT_CENTER,
			600, 90, Color.WHITE)
