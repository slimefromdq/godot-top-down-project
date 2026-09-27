extends Node2D
class_name SpawnSanctuary

# A team's spawn area: its own living heroes standing in it heal quickly, so
# spawn camping doesn't pay and anyone can walk home to reset. The
# MatchManager makes one per team from the map's spawn markers (their
# bounding box grown by MatchRules.spawn_area_margin, kept inside the map);
# rates are MatchRules > Spawn. Heals go through HealthComponent.heal with
# the label &"spawn_heal" (no source, so they give no ultimate charge).
#
# Drawn as a soft team-coloured floor with a border.

const GROUP := &"spawn_sanctuaries"
const HEAL_LABEL := &"spawn_heal"

var team: StringName
## The area in global coordinates.
var area := Rect2()

var _tick_left: float = 0.0


static func find_for(tree: SceneTree, for_team: StringName) -> SpawnSanctuary:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as SpawnSanctuary).team == for_team:
			return node
	return null


## An area around `points`, grown by `margin` and clipped to `bounds`.
static func area_around(points: Array[Node2D], margin: float, bounds: Rect2) -> Rect2:
	var rect := Rect2(points[0].global_position, Vector2.ZERO)
	for point in points:
		rect = rect.expand(point.global_position)
	rect = rect.grow(margin)
	return rect.intersection(bounds) if bounds.has_area() else rect


func _ready() -> void:
	add_to_group(GROUP)
	z_index = -1
	queue_redraw()


func contains(point: Vector2) -> bool:
	return area.has_point(point)


func _physics_process(delta: float) -> void:
	var manager := MatchManager.find(get_tree())
	if manager == null or manager.state == MatchManager.State.ENDED:
		return
	var rules := manager.get_rules()
	_tick_left -= delta
	if _tick_left > 0.0 or rules.spawn_heal_interval <= 0.0:
		return
	_tick_left = rules.spawn_heal_interval
	for hero in manager.get_roster(team):
		var health := hero.health_component
		if health.is_dead() or health.current_health >= health.max_health or not contains(hero.global_position):
			continue
		health.heal(health.max_health * rules.spawn_heal_pct_per_second * rules.spawn_heal_interval, null, HEAL_LABEL)


func _draw() -> void:
	var color := MatchManager.team_color(team)
	var local := Rect2(area.position - global_position, area.size)
	draw_rect(local, Color(color, 0.14))
	draw_rect(local, Color(color, 0.7), false, 8.0)
