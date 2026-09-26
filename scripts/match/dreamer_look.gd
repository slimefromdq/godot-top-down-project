extends Node2D
class_name DreamerLook

# Placeholder look for a Dreamer (DreamerData.look_scene): a big sleeping
# blob in its team's pastel, breathing slowly, with closed eyes, floating Zzz
# and a head badge whose SHAPE says the team (Dawn: a little sun, Dusk: a
# crescent moon), so it never relies on colour alone. Around it: the deposit
# ring, an arc showing the wake meter, and while stirring the Lullaby ring
# with its progress. Cosmetic only; M4 replaces it.

const SKIN := {&"a": Color("bff0da"), &"b": Color("ffd0c2")}
const INK := Color(0.22, 0.2, 0.3)
const LULLABY := Color("c4b5fd")

var dreamer: Dreamer
var _t := 0.0


func setup_dreamer(owner_dreamer: Dreamer) -> void:
	dreamer = owner_dreamer
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if dreamer == null:
		return
	var rules := dreamer.get_rules()
	var team_color := MatchManager.team_color(dreamer.team)
	var r := dreamer.data.body_radius
	var wake := dreamer.get_wake_ratio()
	var stirring := dreamer.is_stirring()

	# Rings on the ground.
	var ring_alpha := 0.9 if Dreamer.debug_rings else 0.4
	_dashed_circle(rules.deposit_radius, Color(team_color, ring_alpha), 6.0 if Dreamer.debug_rings else 4.0)
	if stirring or Dreamer.debug_rings:
		var lullaby_color := Color(1.0, 0.45, 0.45, 0.7) if stirring and dreamer.is_lullaby_contested() else LULLABY
		_dashed_circle(rules.lullaby_radius, Color(lullaby_color, 0.6), 5.0)
		if stirring:
			draw_arc(Vector2.ZERO, rules.lullaby_radius, -PI / 2, -PI / 2 + TAU * dreamer.lullaby, 64,
				Color(lullaby_color, 0.95), 14.0)

	# Wake meter arc hugging the body.
	draw_arc(Vector2.ZERO, r + 34, 0, TAU, 48, Color(0, 0, 0, 0.25), 10.0)
	if wake > 0.0:
		draw_arc(Vector2.ZERO, r + 34, -PI / 2, -PI / 2 + TAU * wake, 48, team_color, 10.0)

	# Breathing body: one breath about every 3 s, faster as it wakes.
	var breath_speed := lerpf(1.0, 2.2, wake) * (1.6 if stirring else 1.0)
	var breath := sin(_t * TAU / 3.0 * breath_speed)
	var rock := sin(_t * 7.0) * 0.06 if stirring else 0.0
	var squash := Vector2(1.0 + 0.04 * breath, 1.0 - 0.03 * breath)
	draw_set_transform(Vector2(0, r * 0.25), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.2))
	draw_set_transform(Vector2.ZERO, rock, squash)
	var skin: Color = SKIN.get(dreamer.team, Color.WHITE)
	draw_circle(Vector2.ZERO, r, skin.darkened(0.15))
	draw_circle(Vector2(0, -r * 0.05), r * 0.94, skin)
	draw_circle(Vector2(-r * 0.4, -r * 0.45), r * 0.22, Color(1, 1, 1, 0.55))
	if stirring:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_circle(Vector2.ZERO, r * 1.1, Color(1, 1, 0.8, 0.12 + 0.12 * pulse))

	# Face: closed eyes (curved lids) that crack open and glow when stirring.
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * r * 0.35, -r * 0.05)
		if stirring:
			draw_circle(eye, r * 0.13, Color(1.0, 0.95, 0.6))
			draw_circle(eye, r * 0.06, INK)
		else:
			draw_arc(eye, r * 0.14, PI * 0.1, PI * 0.9, 12, INK, 5.0)
		draw_circle(eye + Vector2(side * r * 0.12, r * 0.22), r * 0.08, Color(1.0, 0.55, 0.6, 0.45))
	draw_circle(Vector2(0, r * 0.3), r * (0.07 + 0.02 * breath), INK)

	# Team badge on the head: Dawn's sun, Dusk's crescent moon.
	var badge := Vector2(0, -r * 0.82)
	if dreamer.team == &"a":
		for i in 8:
			var a := TAU * i / 8.0 + _t * 0.2
			draw_line(badge + Vector2.from_angle(a) * r * 0.2, badge + Vector2.from_angle(a) * r * 0.32, team_color.darkened(0.3), 6.0)
		draw_circle(badge, r * 0.17, team_color.darkened(0.1))
	else:
		draw_circle(badge, r * 0.22, team_color.darkened(0.2))
		draw_circle(badge + Vector2(r * 0.1, -r * 0.06), r * 0.19, skin)
	draw_set_transform(Vector2.ZERO)

	# Zzz while asleep, fewer as it wakes.
	if not stirring:
		var count := 3 if wake < 0.5 else (2 if wake < 0.75 else 1)
		var font := ThemeDB.fallback_font
		for i in count:
			var k := fmod(_t * 0.35 + i / 3.0, 1.0)
			var at := Vector2(r * 0.7 + k * 60.0 + sin(_t + i) * 10.0, -r * 0.8 - k * 150.0)
			draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(40 + 30 * k), Color(INK, 0.8 * (1.0 - k)))
	else:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-80, -r - 70), "%d" % ceili(dreamer.stir_left), HORIZONTAL_ALIGNMENT_CENTER, 160, 64,
			Color(1, 1, 1, 0.95))


func _dashed_circle(radius: float, color: Color, width: float) -> void:
	var segments := 48
	for i in segments:
		if i % 2 == 0:
			var a := TAU * i / segments + _t * 0.05
			draw_arc(Vector2.ZERO, radius, a, a + TAU / segments, 4, color, width)
