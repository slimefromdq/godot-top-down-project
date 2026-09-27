extends Control
class_name WakeMeter

# One team's Dreamer on the match HUD, top centre: a face icon (Dawn's has a
# sun, Dusk's a crescent moon, so the two differ by shape as well as colour),
# the wake meter bar, and a Sweet Dreams pip row underneath. While the
# Dreamer stirs the bar flashes, shows the stir countdown, and a second bar
# fills with the Lullaby. Read-only: it polls its Dreamer every frame.

const PIPS := 5
const ICON := 26.0
const LULLABY := Color("c4b5fd")

## Which Dreamer to show.
@export var team: StringName = &"a"
## Icon on the outer side: Dawn's meter sits left of the clock, Dusk's right.
@export var icon_on_left: bool = true

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(320, 70)


func get_dreamer() -> Dreamer:
	return Dreamer.find_for(get_tree(), team)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var dreamer := get_dreamer()
	if dreamer == null:
		return
	var rules := dreamer.get_rules()
	var color := MatchManager.team_color(team)
	var stirring := dreamer.is_stirring()
	var icon_x := ICON + 2.0 if icon_on_left else size.x - ICON - 2.0
	var bar := Rect2(ICON * 2 + 10, 8, size.x - ICON * 2 - 20, 22) if icon_on_left \
		else Rect2(10, 8, size.x - ICON * 2 - 20, 22)
	_draw_face(Vector2(icon_x, 24), color, stirring)

	# The wake bar.
	var flash := 0.5 + 0.5 * sin(_t * 10.0) if stirring else 0.0
	draw_rect(bar, Color(0, 0, 0, 0.55).lerp(Color(1, 1, 1, 0.35), flash * 0.6))
	var fill := bar
	fill.size.x *= dreamer.get_wake_ratio()
	if not icon_on_left:
		fill.position.x = bar.end.x - fill.size.x    # Dusk's fills toward the clock
	draw_rect(fill, color)
	draw_rect(bar, Color(0, 0, 0, 0.8), false, 2.0)
	var font := ThemeDB.fallback_font
	var label := "STIRRING  %d" % ceili(dreamer.stir_left) if stirring \
		else "%d / %d" % [floori(dreamer.wake), roundi(rules.wake_meter_max)]
	draw_string_outline(font, bar.position + Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 15, 4,
		Color(0, 0, 0, 0.9))
	draw_string(font, bar.position + Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 15, Color.WHITE)

	var below := Rect2(bar.position.x, bar.end.y + 6, bar.size.x, 10)
	if stirring:
		# The Lullaby as a second bar (red while contested, dim during grace).
		draw_rect(below, Color(0, 0, 0, 0.5))
		var lullaby := below
		lullaby.size.x *= dreamer.lullaby
		var tint := Color(1.0, 0.5, 0.5) if dreamer.is_lullaby_contested() else LULLABY
		draw_rect(lullaby, tint)
		draw_rect(below, Color(0, 0, 0, 0.8), false, 1.5)
	else:
		# Sweet Dreams pips: one per fifth of the threshold banked.
		var per_pip := rules.sweet_dreams_threshold / PIPS
		var filled := floori(dreamer.sweet / per_pip) if per_pip > 0.0 else 0
		for i in PIPS:
			var at := below.position + Vector2(8 + i * 18, 5)
			draw_circle(at, 6.0, Color(0, 0, 0, 0.6))
			draw_circle(at, 4.5, Color("fde68a") if i < filled else Color(1, 1, 1, 0.15))


func _draw_face(at: Vector2, color: Color, stirring: bool) -> void:
	draw_circle(at, ICON, Color(0, 0, 0, 0.6))
	draw_circle(at, ICON - 3, color.lightened(0.35))
	var ink := Color(0.2, 0.18, 0.28)
	for side in [-1.0, 1.0]:
		var eye := at + Vector2(side * 8, 1)
		if stirring:
			draw_circle(eye, 4, Color(1, 0.95, 0.6))
			draw_circle(eye, 2, ink)
		else:
			draw_arc(eye, 4.5, PI * 0.1, PI * 0.9, 8, ink, 2.0)
	var badge := at + Vector2(0, -ICON + 4)
	if team == &"a":
		for i in 8:
			var a := TAU * i / 8.0
			draw_line(badge + Vector2.from_angle(a) * 5, badge + Vector2.from_angle(a) * 9, color.darkened(0.35), 2.0)
		draw_circle(badge, 4.5, color.darkened(0.2))
	else:
		draw_circle(badge, 7, color.darkened(0.3))
		draw_circle(badge + Vector2(3, -2), 6, color.lightened(0.35))
