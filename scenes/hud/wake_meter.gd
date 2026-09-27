extends Control
class_name WakeMeter

# One team's Dreamer on the match HUD, top centre: a face icon (Dawn's has a
# sun, Dusk's a crescent moon, so the two differ by shape as well as colour),
# the wake meter bar, and a Sweet Dreams pip row underneath. The bar is a
# glossy bubbly fill that eases toward the real value, with a highlight
# sweeping across it; from 75% it glows and cracks. While the Dreamer stirs
# the bar flashes, shows the stir countdown, and a second bar fills with the
# Lullaby. Read-only: it polls its Dreamer every frame.

const PIPS := 5
const ICON := 26.0
const LULLABY := Color("c4b5fd")

## Which Dreamer to show.
@export var team: StringName = &"a"
## Icon on the outer side: Dawn's meter sits left of the clock, Dusk's right.
@export var icon_on_left: bool = true

var _t := 0.0
## The fill shown (eases toward the Dreamer's wake ratio).
var shown: float = 0.0
var _lullaby_shown: float = 0.0
# The shapes of the redraw in progress (see _draw).
var _batch: ShapeBatch
# Redrawn this often rather than every frame.
const REDRAW_INTERVAL := 1.0 / 30.0
var _redraw_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(320, 70)


func get_dreamer() -> Dreamer:
	return Dreamer.find_for(get_tree(), team)


func _process(delta: float) -> void:
	_t += delta
	var dreamer := get_dreamer()
	if dreamer != null:
		var ease_k := 1.0 - exp(-6.0 * delta)
		shown = lerpf(shown, dreamer.get_wake_ratio(), ease_k)
		_lullaby_shown = lerpf(_lullaby_shown, dreamer.lullaby if dreamer.is_stirring() else 0.0, ease_k)
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_INTERVAL
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
	# Shapes go into one batch (one draw call); the rim and text go on top.
	_batch = ShapeBatch.new()
	_draw_face(Vector2(icon_x, 24), color, stirring)

	# The wake bar: a glossy bubble tube.
	var flash := 0.5 + 0.5 * sin(_t * 10.0) if stirring else 0.0
	var high := shown >= 0.75
	if high or stirring:
		var glow := 0.5 + 0.5 * sin(_t * 5.0)
		_pill(bar.grow(4.0 + 3.0 * glow), Color(color, 0.25 + 0.25 * glow))
	_pill(bar, Color(0, 0, 0, 0.55).lerp(Color(1, 1, 1, 0.35), flash * 0.6))
	var fill := bar
	fill.size.x = maxf(bar.size.x * shown, 0.0)
	if not icon_on_left:
		fill.position.x = bar.end.x - fill.size.x    # Dusk's fills toward the clock
	if fill.size.x > 2.0:
		_pill(fill, color)
		_pill(Rect2(fill.position + Vector2(0, fill.size.y * 0.5), Vector2(fill.size.x, fill.size.y * 0.5)),
			color.darkened(0.12))
		_pill(Rect2(fill.position + Vector2(4, 3), Vector2(maxf(fill.size.x - 8, 0), fill.size.y * 0.32)),
			Color(1, 1, 1, 0.45))
		# A highlight sweeping along the fill every few seconds.
		var sweep := fmod(_t * 0.45, 1.6) - 0.3
		var sx := fill.position.x + fill.size.x * sweep
		if sweep > 0.0 and sweep < 1.0:
			_batch.draw_colored_polygon(PackedVector2Array([Vector2(sx, fill.position.y), Vector2(sx + 14, fill.position.y),
				Vector2(sx + 4, fill.end.y), Vector2(sx - 10, fill.end.y)]), Color(1, 1, 1, 0.4))
	if high:
		_draw_cracks(bar, color)
	var below := Rect2(bar.position.x, bar.end.y + 6, bar.size.x, 10)
	if stirring:
		# The Lullaby as a second bar (red while contested, dim during grace).
		_pill(below, Color(0, 0, 0, 0.5))
		var lullaby := below
		lullaby.size.x *= _lullaby_shown
		var tint := Color(1.0, 0.5, 0.5) if dreamer.is_lullaby_contested() else LULLABY
		if lullaby.size.x > 2.0:
			_pill(lullaby, tint)
			_pill(Rect2(lullaby.position + Vector2(2, 1), Vector2(maxf(lullaby.size.x - 4, 0), 3)), Color(1, 1, 1, 0.45))
	else:
		# Sweet Dreams pips: one per fifth of the threshold banked.
		var per_pip := rules.sweet_dreams_threshold / PIPS
		var filled := floori(dreamer.sweet / per_pip) if per_pip > 0.0 else 0
		for i in PIPS:
			var at := below.position + Vector2(8 + i * 18, 5)
			_batch.draw_circle(at, 6.0, Color(0, 0, 0, 0.6))
			_batch.draw_circle(at, 4.5, Color("fde68a") if i < filled else Color(1, 1, 1, 0.15))
	_batch.draw_on(self)
	_batch = null
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.border_color = Color(1, 1, 1, 0.8)
	rim.set_border_width_all(2)
	rim.set_corner_radius_all(int(bar.size.y / 2.0))
	draw_style_box(rim, bar)
	var font := ThemeDB.fallback_font
	var label := "STIRRING  %d" % ceili(dreamer.stir_left) if stirring \
		else "%d / %d" % [floori(dreamer.wake), roundi(rules.wake_meter_max)]
	draw_string_outline(font, bar.position + Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 15, 4,
		Color(0, 0, 0, 0.9))
	draw_string(font, bar.position + Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 15, Color.WHITE)


# A rounded (pill) rect.
func _pill(rect: Rect2, color: Color) -> void:
	_batch.draw_rounded_rect(rect, color, floorf(rect.size.y / 2.0))


# Hairline cracks across the tube from 75%: the Dreamer is close to waking.
func _draw_cracks(bar: Rect2, color: Color) -> void:
	var c := Color(1, 1, 1, 0.75)
	for x in [0.3, 0.55, 0.8]:
		var at := bar.position + Vector2(bar.size.x * x, 0)
		_batch.draw_polyline(PackedVector2Array([at, at + Vector2(5, 7), at + Vector2(-2, 13), at + Vector2(6, bar.size.y)]),
			c, 1.5)
	_batch.draw_circle(bar.position + Vector2(bar.size.x * 0.55 + 3, 10), 3.0, Color(color.lightened(0.5), 0.9))


func _draw_face(at: Vector2, color: Color, stirring: bool) -> void:
	_batch.draw_circle(at, ICON, Color(0, 0, 0, 0.6))
	_batch.draw_circle(at, ICON - 3, color.lightened(0.35))
	var ink := Color(0.2, 0.18, 0.28)
	for side in [-1.0, 1.0]:
		var eye := at + Vector2(side * 8, 1)
		if stirring:
			_batch.draw_circle(eye, 4, Color(1, 0.95, 0.6))
			_batch.draw_circle(eye, 2, ink)
		else:
			_batch.draw_arc(eye, 4.5, PI * 0.1, PI * 0.9, 8, ink, 2.0)
	var badge := at + Vector2(0, -ICON + 4)
	if team == &"a":
		for i in 8:
			var a := TAU * i / 8.0
			_batch.draw_line(badge + Vector2.from_angle(a) * 5, badge + Vector2.from_angle(a) * 9, color.darkened(0.35), 2.0)
		_batch.draw_circle(badge, 4.5, color.darkened(0.2))
	else:
		_batch.draw_circle(badge, 7, color.darkened(0.3))
		_batch.draw_circle(badge + Vector2(3, -2), 6, color.lightened(0.35))
