extends Node2D
class_name IslandPortal

# The secret door to the Mote Island (made by the IslandDirector at one of the
# map's "island_portal_spawn" markers; freed when it relocates). It is NOT on
# the minimap and has no arrow. The local player finds it by walking near:
#
#   beyond island_shimmer_tiles      nothing at all
#   within island_shimmer_tiles      a faint shimmer in the air, and a soft
#                                    hum now and then
#   within island_visible_tiles      the portal is fully drawn
#   within island_interact_tiles     they can step through (interact key)
#
# The drawing is filtered by distance to the LOCAL player only, like
# LocalView does for other hidden things; gameplay never reads it. The other
# half of the same node is an interactable (see MapEventsHud).

const GROUP := &"island_portals"

## Which relocation this is (the schedule's period index).
var index: int = 0
var spot: int = 0
var rules: MapEventRules
var _t := randf() * 10.0
var _hum_left: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(MapEvents.INTERACTABLES)


func _ready() -> void:
	z_index = -4


# --- Interactable ---------------------------------------------------------------------------------

func get_prompt(_hero: Hero) -> String:
	return "Step through"


func get_interact_radius() -> float:
	return rules.tiles(rules.island_interact_tiles) if rules != null else 240.0


func can_interact(hero: Hero) -> bool:
	return hero != null and not hero.health_component.is_dead() \
		and hero.global_position.distance_to(global_position) <= get_interact_radius()


## 0 (unseen) .. 1 (fully visible) for a viewer `distance` px away.
func visibility_at(distance: float) -> float:
	if rules == null:
		return 1.0
	var far := rules.tiles(rules.island_shimmer_tiles)
	var near := rules.tiles(rules.island_visible_tiles)
	if distance >= far:
		return 0.0
	if distance <= near:
		return 1.0
	return clampf((far - distance) / maxf(far - near, 1.0), 0.0, 1.0) * 0.5


func _local_player() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D


func _process(delta: float) -> void:
	_t += delta
	var player := _local_player()
	if player == null or rules == null:
		return
	var distance := player.global_position.distance_to(global_position)
	if distance < rules.tiles(rules.island_shimmer_tiles):
		queue_redraw()
		_hum_left -= delta
		if _hum_left <= 0.0:
			_hum_left = rules.island_shimmer_sound_interval
			MatchManager.play_world_cue(self, &"island_shimmer", {"position": global_position,
				"pitch": lerpf(1.4, 0.9, visibility_at(distance))})


func _draw() -> void:
	var player := _local_player()
	if player == null:
		return
	var visible_k := visibility_at(player.global_position.distance_to(global_position))
	if visible_k <= 0.0:
		return
	var full := visible_k >= 1.0
	# A shimmer: a few drifting, faint arcs. Fully visible: a swirling door.
	var radius := 90.0
	if not full:
		for i in 4:
			var a := _t * 0.9 + i * TAU / 4.0
			draw_arc(Vector2.ZERO, radius * (0.55 + 0.1 * sin(_t * 2.0 + i)), a, a + 0.9, 12,
				Color(0.85, 0.75, 1.0, visible_k * 0.35), 3.0, true)
		return
	draw_circle(Vector2(6, 10), radius, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, radius, Color("3b1d6e"))
	draw_circle(Vector2.ZERO, radius * 0.8, Color("8b5cf6"))
	for k in 4:
		var start := _t * 2.2 + k * TAU / 4.0
		draw_arc(Vector2.ZERO, radius * (0.25 + 0.13 * k), start, start + 1.6, 18, Color(1, 1, 1, 0.75), 5.0, true)
	draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 48, Color(0.9, 0.8, 1.0, 0.7 + 0.2 * sin(_t * 3.0)), 4.0, true)
