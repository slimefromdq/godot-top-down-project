extends Node2D
class_name MoteLook

# Placeholder look for a Mote: a round little dream-bug, the young of Cpt.
# Yellow's species. Soft yellow body, fluttering wings,
# bobbing antennae, two big glossy eyes that look toward the nearest hero,
# rosy cheeks and a small smile, in a glossy bubble with a turning shine.
# A Dream Mote is bigger and fluffier, with a slow iridescent swirl. The Mote
# can squash it (a spawn pop, a magnet pull) through get_look_squash().
#
# Cosmetic only: MoteData.look_scene points here, and a sprite scene can
# replace it. The carrier's orbit calls draw_mote() directly so carried and
# loose Motes look the same. The palette matches Cpt. Yellow's bugs, copied
# here because shared code never loads a hero's files.

const BODY := Color(1.0, 0.84, 0.18)
const BODY_DARK := Color(0.93, 0.66, 0.08)
## Antennae and the smile.
const INK := Color(0.2, 0.14, 0.03)
const WING := Color(0.93, 0.98, 1.0, 0.55)
const EYE := Color(1, 1, 1)
const PUPIL := Color(0.1, 0.07, 0.12)
const CHEEK := Color(1.0, 0.55, 0.55, 0.55)
const SHADOW := Color(0, 0, 0, 0.22)

var mote: Node2D
var _t := randf() * 10.0


func setup_mote(owner_mote: Node2D) -> void:
	mote = owner_mote


func _process(delta: float) -> void:
	_t += delta
	if ScreenCull.is_near(self, 60.0):
		queue_redraw()


func _draw() -> void:
	if mote == null:
		return
	var data: MoteData = mote.get(&"data")
	var size := data.size if data != null else 34.0
	var dream := data != null and data.is_dream
	var alpha: float = mote.call(&"get_look_alpha") if mote.has_method(&"get_look_alpha") else 1.0
	var look: Vector2 = mote.call(&"get_look_direction") if mote.has_method(&"get_look_direction") else Vector2.ZERO
	var squash: Vector2 = mote.call(&"get_look_squash") if mote.has_method(&"get_look_squash") else Vector2.ONE
	var bob := sin(_t * 3.0) * size * 0.08
	draw_mote(self, Vector2(0, bob), size, _t, look, alpha, dream, 0.0, bob, squash)


## One Mote at `at`. `t` animates (wings, antennae, shine, shimmer); `look`
## (length 0..1) moves the pupils; `wiggle` 0..1 is extra happy wobble
## (carried); `lift` is how high it floats above its shadow; `squash` scales
## the body (pops and pulls); `rainbow` draws a rainbow rim (a full stack).
static func draw_mote(canvas: CanvasItem, at: Vector2, size: float, t: float, look: Vector2 = Vector2.ZERO,
		alpha: float = 1.0, dream: bool = false, wiggle: float = 0.0, lift: float = 0.0,
		squash: Vector2 = Vector2.ONE, rainbow: bool = false, simple: bool = false) -> void:
	var r := size * 0.5
	var tilt := sin(t * 9.0) * 0.12 * wiggle
	if simple:
		_draw_simple_mote(canvas, at, r, alpha, dream, rainbow)
		return

	# Shadow on the ground, below the floating body.
	canvas.draw_set_transform(at + Vector2(0, r * 0.95 - lift), 0.0, Vector2(squash.x, 0.35))
	canvas.draw_circle(Vector2.ZERO, r * 0.8, _a(SHADOW, alpha))
	canvas.draw_set_transform(Vector2.ZERO)

	if dream:
		# Slow iridescent halo and swirling bands.
		var halo := Color.from_hsv(fmod(t * 0.08, 1.0), 0.35, 1.0, 0.35 * alpha)
		canvas.draw_circle(at, r * 1.6, _a(halo, 0.45))
		for i in 3:
			var a0 := t * (0.7 + 0.2 * i) + TAU * i / 3.0
			canvas.draw_arc(at, r * (1.3 + 0.12 * i), a0, a0 + TAU * 0.35, 24,
				Color.from_hsv(fmod(t * 0.08 + 0.2 * i, 1.0), 0.5, 1.0, 0.65 * alpha), r * 0.1)

	# Wings: two soft ovals behind the body, fluttering.
	var flap := 0.55 + 0.45 * absf(sin(t * (14.0 + 10.0 * wiggle)))
	for side in [-1.0, 1.0]:
		canvas.draw_set_transform(at + Vector2(side * r * 0.72 * squash.x, -r * 0.35 * squash.y), side * (0.5 + tilt),
			Vector2(flap, 0.62))
		canvas.draw_circle(Vector2.ZERO, r * 0.62, _a(WING, alpha))
		canvas.draw_arc(Vector2.ZERO, r * 0.62, 0, TAU, 20, _a(Color(1, 1, 1, 0.8), alpha), 1.5)
	canvas.draw_set_transform(at, tilt, squash)

	# Antennae: two curved stalks with little balls, bobbing.
	for side in [-1.0, 1.0]:
		var sway := sin(t * 4.0 + side) * r * 0.12
		var base := Vector2(side * r * 0.3, -r * 0.82)
		var tip := Vector2(side * r * 0.62 + sway, -r * 1.42)
		canvas.draw_polyline(PackedVector2Array([base, base.lerp(tip, 0.5) + Vector2(side * r * 0.1, -r * 0.05), tip]),
			_a(INK, alpha), maxf(r * 0.08, 1.5))
		canvas.draw_circle(tip, r * 0.13, _a(BODY_DARK, alpha))

	# Fluffy fringe for the Dream Mote.
	if dream:
		for i in 12:
			var a := TAU * i / 12.0 + t * 0.2
			canvas.draw_circle(Vector2.from_angle(a) * r * 0.92, r * 0.2, _a(BODY.lightened(0.25), alpha))

	# Body: a glossy bubble. Rim, fill, a soft lighter top, a turning shine.
	canvas.draw_circle(Vector2.ZERO, r * 1.04, _a(BODY_DARK, alpha))
	canvas.draw_circle(Vector2(0, -r * 0.04), r * 0.96, _a(BODY, alpha))
	canvas.draw_circle(Vector2(0, -r * 0.3), r * 0.66, _a(Color(BODY.lightened(0.3), 0.55), alpha))
	var shine := t * 0.9
	canvas.draw_arc(Vector2.ZERO, r * 0.8, shine, shine + 0.9, 12, _a(Color(1, 1, 1, 0.45), alpha), r * 0.12)
	canvas.draw_circle(Vector2(-r * 0.38, -r * 0.42), r * 0.22, _a(Color(1, 1, 1, 0.6), alpha))
	canvas.draw_circle(Vector2(-r * 0.18, -r * 0.6), r * 0.08, _a(Color(1, 1, 1, 0.75), alpha))
	canvas.draw_arc(Vector2.ZERO, r * 1.1, 0, TAU, 28, _a(Color(1, 1, 1, 0.3), alpha), maxf(r * 0.06, 1.0))
	if rainbow:
		for i in 12:
			var a := TAU * i / 12.0 + t * 1.5
			canvas.draw_arc(Vector2.ZERO, r * 1.2, a, a + TAU / 12.0, 4,
				Color.from_hsv(fmod(i / 12.0 + t * 0.3, 1.0), 0.6, 1.0, 0.8 * alpha), maxf(r * 0.1, 1.5))

	# Big glossy eyes, pupils toward `look`.
	var blink := 1.0 if fmod(t, 3.7) > 0.12 else 0.15
	var gaze := look.limit_length(1.0) * r * 0.11
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * r * 0.33, r * 0.02) * squash
		canvas.draw_set_transform(at + eye.rotated(tilt), tilt, Vector2(squash.x, squash.y * blink))
		canvas.draw_circle(Vector2.ZERO, r * 0.3, _a(EYE, alpha))
		canvas.draw_circle(gaze, r * 0.19, _a(PUPIL, alpha))
		canvas.draw_circle(gaze + Vector2(-r * 0.07, -r * 0.08), r * 0.07, _a(EYE, alpha))
		canvas.draw_circle(gaze + Vector2(r * 0.06, r * 0.06), r * 0.03, _a(EYE, alpha * 0.8))
	canvas.draw_set_transform(at, tilt, squash)

	# Rosy cheeks and a small smile.
	for side in [-1.0, 1.0]:
		canvas.draw_circle(Vector2(side * r * 0.58, r * 0.36), r * 0.13, _a(CHEEK, alpha))
	canvas.draw_arc(Vector2(0, r * 0.32), r * 0.2, PI * 0.15, PI * 0.85, 10, _a(INK, alpha), maxf(r * 0.07, 1.5))
	canvas.draw_set_transform(Vector2.ZERO)


# A far-away or crowded Mote (a carrier's outer orbit rings): the glossy
# body, one shine and two eyes, a fraction of the full drawing's shapes.
static func _draw_simple_mote(canvas: CanvasItem, at: Vector2, r: float, alpha: float, dream: bool,
		rainbow: bool) -> void:
	if dream:
		canvas.draw_circle(at, r * 1.5, _a(Color(1, 1, 1, 0.3), alpha))
	var rim := BODY_DARK
	if rainbow:
		rim = Color.from_hsv(fmod(at.x * 0.002 + at.y * 0.001, 1.0), 0.6, 1.0)
	canvas.draw_circle(at, r * 1.04, _a(rim, alpha))
	canvas.draw_circle(at + Vector2(0, -r * 0.04), r * 0.96, _a(BODY, alpha))
	canvas.draw_circle(at + Vector2(-r * 0.38, -r * 0.42), r * 0.22, _a(Color(1, 1, 1, 0.6), alpha))
	canvas.draw_circle(at + Vector2(-r * 0.33, r * 0.02), r * 0.2, _a(PUPIL, alpha))
	canvas.draw_circle(at + Vector2(r * 0.33, r * 0.02), r * 0.2, _a(PUPIL, alpha))


static func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)
