extends Node2D
class_name BlackMarket

# The Black Market stall in the world (made by the BlackMarketDirector while
# it is open, freed when it closes). Cosmetic and a place to stand: a dim
# awning stall, a ring showing how close you must be, and the despawn
# countdown drawn on it. It is an interactable (press the interact key in
# range) and shows on both teams' minimaps and as an off-screen arrow.
#
# Everything it shows is read from the director's fields (`time_left`).

const GROUP := &"black_markets"
const INTERACTABLES := &"interactables"

var side: StringName = &"left"
## Which open window this is (the schedule's cycle index).
var index: int = 0
var duration: float = 90.0
var time_left: float = 90.0
var interact_radius: float = 320.0
var minimap_fogged := false
var arrow_color := Color("c084fc")

var _t := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(INTERACTABLES)
	add_to_group(&"minimap_objectives")
	add_to_group(&"offscreen_arrows")


func _ready() -> void:
	z_index = -5


# --- Interactable ---------------------------------------------------------------------

func get_prompt(_hero: Hero) -> String:
	return "Black Market"


func can_interact(hero: Hero) -> bool:
	return hero != null and not hero.health_component.is_dead() \
		and hero.global_position.distance_to(global_position) <= interact_radius


func get_interact_radius() -> float:
	return interact_radius


# --- HUD hooks ----------------------------------------------------------------------------

func offscreen_arrow_for(_viewer: Node) -> Dictionary:
	return {"color": arrow_color, "scale": 1.1}


func draw_minimap_icon(canvas: Object, at: Vector2, _viewer_team: StringName) -> void:
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
	canvas.draw_circle(at, 8.5, Color.BLACK)
	canvas.draw_circle(at, 7.0, Color(arrow_color, pulse))
	# A little coin.
	canvas.draw_circle(at, 3.2, Color("fde68a"))
	canvas.draw_circle(at, 1.4, Color(0.3, 0.2, 0.05))


func _process(delta: float) -> void:
	_t += delta
	if ScreenCull.is_near(self, interact_radius + 200.0):
		queue_redraw()


func _draw() -> void:
	var ratio := clampf(time_left / maxf(duration, 0.01), 0.0, 1.0)
	var urgent := time_left <= 10.0
	var glow := Color(arrow_color, 0.10 + (0.12 * (0.5 + 0.5 * sin(_t * 8.0)) if urgent else 0.0))
	draw_circle(Vector2.ZERO, interact_radius, glow)
	draw_arc(Vector2.ZERO, interact_radius, 0.0, TAU, 96, Color(arrow_color, 0.45), 4.0, true)
	# The despawn countdown, a ring that empties.
	draw_arc(Vector2.ZERO, interact_radius + 16.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 96,
		Color("fde68a") if not urgent else Color("fb7185"), 8.0, true)
	# Stall: dark counter, torn awning, a hanging coin.
	draw_rect(Rect2(-120, -10, 240, 76), Color(0, 0, 0, 0.28))
	var counter := Rect2(-110, -20, 220, 70)
	draw_rect(counter, Color("2e1f47"))
	draw_rect(Rect2(counter.position, Vector2(counter.size.x, 16)), Color(1, 1, 1, 0.14))
	draw_rect(counter, Color(0.75, 0.55, 1.0, 0.8), false, 3.0)
	var stripes := 6
	var width := 260.0 / stripes
	for i in stripes:
		var x := -130.0 + i * width
		var sway := sin(_t * 2.4 + i) * 3.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -96), Vector2(x + width, -96),
			Vector2(x + width, -44 + sway), Vector2(x + width * 0.5, -36 + sway), Vector2(x, -44 + sway)]),
			Color("7c3aed") if i % 2 == 0 else Color("1f1235"))
	var coin := Vector2(0, -128 + sin(_t * 3.0) * 4.0)
	draw_circle(coin, 22.0, Color("fde68a"))
	draw_arc(coin, 22.0, 0.0, TAU, 32, Color(0.45, 0.3, 0.05), 3.0, true)
	draw_string(ThemeDB.fallback_font, coin + Vector2(-8, 9), "M", HORIZONTAL_ALIGNMENT_CENTER, -1, 26, Color(0.4, 0.25, 0.05))
	# Countdown text above.
	var text := "%d:%02d" % [floori(time_left / 60.0), floori(fmod(time_left, 60.0))]
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-60, -170), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 34, 8, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-60, -170), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 34,
		Color("fb7185") if urgent else Color.WHITE)
