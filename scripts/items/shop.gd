extends Node2D
class_name Shop

# A team's shop stall, placed in its base (Dream Basin: in each spawn room).
# Heroes of `team` within MatchRules.shop_radius can buy and sell (see
# MatchManager.get_shop_block_reason); dead heroes can shop from anywhere.
# It holds no stock or prices itself: those are MatchRules.shop_catalog.
#
# Placeholder look: a glossy counter under a striped awning in the team
# colour, with the reach ring faintly drawn on the floor. Cosmetic only.

const GROUP := &"shops"

@export var team: StringName = &"a"

var _t := 0.0


static func get_all(tree: SceneTree, for_team: StringName = &"") -> Array[Shop]:
	var result: Array[Shop] = []
	if tree == null:
		return result
	for node in tree.get_nodes_in_group(GROUP):
		var shop := node as Shop
		if shop != null and (for_team == &"" or shop.team == for_team):
			result.append(shop)
	return result


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	z_index = -5


func get_radius() -> float:
	var manager := MatchManager.find(get_tree())
	return (manager.get_rules() if manager != null else MatchRules.current()).shop_radius


func _process(delta: float) -> void:
	_t += delta
	if ScreenCull.is_near(self, get_radius()):
		queue_redraw()


func _draw() -> void:
	var color := MatchManager.team_color(team)
	var radius := get_radius()
	draw_circle(Vector2.ZERO, radius, Color(color, 0.05))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(color, 0.35), 4.0, true)
	# Counter
	var counter := Rect2(-110, -20, 220, 70)
	draw_rect(Rect2(counter.position + Vector2(6, 8), counter.size), Color(0, 0, 0, 0.25))
	draw_rect(counter, Color("fef3c7"))
	draw_rect(Rect2(counter.position, Vector2(counter.size.x, 18)), Color(1, 1, 1, 0.55))
	draw_rect(counter, Color(0.2, 0.15, 0.1, 0.8), false, 3.0)
	# Awning: stripes in the team colour and white.
	var stripes := 6
	var width := 260.0 / stripes
	for i in stripes:
		var x := -130.0 + i * width
		var sway := sin(_t * 2.0 + i) * 2.0
		var stripe := PackedVector2Array([Vector2(x, -90), Vector2(x + width, -90),
			Vector2(x + width, -40 + sway), Vector2(x, -40 + sway)])
		draw_colored_polygon(stripe, color if i % 2 == 0 else Color.WHITE)
	draw_line(Vector2(-130, -90), Vector2(130, -90), Color(0.2, 0.15, 0.1, 0.8), 3.0)
	# A gold coin sign that bobs.
	var coin := Vector2(0, -120 + sin(_t * 3.0) * 4.0)
	draw_circle(coin, 22.0, Color("fbd34d"))
	draw_circle(coin + Vector2(-6, -6), 8.0, Color(1, 1, 1, 0.6))
	draw_arc(coin, 22.0, 0.0, TAU, 32, Color(0.45, 0.3, 0.05), 3.0, true)
