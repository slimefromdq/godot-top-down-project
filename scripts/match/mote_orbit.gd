extends Node2D
class_name MoteOrbit

# Cosmetic: a MoteCarrier's Motes circling its hero, in rings: the first
# RING_SIZES[0] on an inner ring, the next on a wider one, the rest on the
# outermost, each ring turning the other way. A big stack reads as a swarm at
# a glance (the outer rings use MoteLook's simple drawing, to keep a full
# stack cheap). Each Mote trails soft sparkles; the newest one squashes as it
# lands in the ring; a full stack gets rainbow rims; carrying a Dream Mote
# raises a beam of light over the hero that everyone can see. Added by the
# carrier as a child of the hero; gameplay never reads it.

const RING_RADII: Array[float] = [80.0, 116.0, 150.0]
const RING_SIZES: Array[int] = [8, 9, 99]
const SPIN := 1.6
const SIZE_SCALE := 0.7
const OUTER_SCALE := 0.6
## Sparkles behind each Mote, spaced this many seconds back along its path.
const TRAIL_DOTS := 4
const OUTER_TRAIL_DOTS := 2
const TRAIL_STEP := 0.05
const POP_TIME := 0.3
const BEAM_HEIGHT := 900.0

var carrier: MoteCarrier
var _t := 0.0
var _last_count := 0
var _pop_age := 1.0


func _ready() -> void:
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	_pop_age += delta
	var count := 0
	if carrier != null and is_instance_valid(carrier):
		count = carrier.get_mote_count()
		if count > _last_count:
			_pop_age = 0.0
	# Nothing carried: one last redraw to clear, then idle.
	if count > 0 or _last_count > 0:
		queue_redraw()
	_last_count = count


func _draw() -> void:
	if carrier == null or not is_instance_valid(carrier) or carrier.actor == null:
		return
	var datas := carrier.get_datas()
	var n := datas.size()
	if n == 0 or carrier.actor.health_component.is_dead():
		return
	if carrier.has_dream_mote():
		_draw_beam()
	var full := n >= carrier.get_max()
	var index := 0
	for ring in RING_RADII.size():
		var in_ring := mini(n - index, RING_SIZES[ring])
		if in_ring <= 0:
			break
		var direction := 1.0 if ring % 2 == 0 else -1.0
		var scale_k := SIZE_SCALE if ring == 0 else OUTER_SCALE
		# The outer rings are small and crowded: simple Motes, shorter trails.
		var trail := TRAIL_DOTS if ring == 0 else OUTER_TRAIL_DOTS
		for j in in_ring:
			var data: MoteData = datas[index]
			# Sparkles where it was a moment ago.
			for k in range(trail, 0, -1):
				var past := _orbit_point(ring, j, in_ring, direction, _t - k * TRAIL_STEP)
				var fade := 1.0 - float(k) / (TRAIL_DOTS + 1)
				draw_circle(past, 3.0 * fade + 1.0, Color(1.0, 0.95, 0.7, 0.45 * fade))
			var at := _orbit_point(ring, j, in_ring, direction, _t)
			var squash := Vector2.ONE
			if index == n - 1 and _pop_age < POP_TIME:
				var k := 1.0 - _pop_age / POP_TIME
				squash = Vector2(1.0 + 0.35 * k, 1.0 - 0.3 * k)
			var a := direction * _t * SPIN / (1.0 + ring * 0.4) + TAU * j / in_ring + ring * 0.3
			MoteLook.draw_mote(self, at, data.size * scale_k, _t + index * 1.7,
				Vector2.from_angle(a + PI * 0.5 * direction) * 0.6, 1.0, data.is_dream, 1.0,
				4.0 * sin(_t * 5.0 + index), squash, full, ring > 0)
			index += 1


# Where Mote j of in_ring on `ring` is at time t (squashed a little
# vertically: it reads as a ring around the hero).
func _orbit_point(ring: int, j: int, in_ring: int, direction: float, t: float) -> Vector2:
	var a := direction * t * SPIN / (1.0 + ring * 0.4) + TAU * j / in_ring + ring * 0.3
	return Vector2(cos(a) * RING_RADII[ring], sin(a) * RING_RADII[ring] * 0.7) + Vector2(0, -10)


# The Dream Mote beam: a soft column of light rising from the carrier.
func _draw_beam() -> void:
	var pulse := 0.75 + 0.25 * sin(_t * 3.0)
	for i in 4:
		var w := 70.0 - i * 16.0
		var color := Color.from_hsv(fmod(0.75 + _t * 0.05 + i * 0.05, 1.0), 0.25, 1.0, 0.08 * pulse * (i + 1))
		draw_rect(Rect2(-w / 2.0, -BEAM_HEIGHT, w, BEAM_HEIGHT), color)
	for i in 6:
		var k := fmod(_t * 0.4 + i / 6.0, 1.0)
		draw_circle(Vector2(sin(_t * 2.0 + i) * 18.0, -k * BEAM_HEIGHT), 4.0 * (1.0 - k) + 1.5,
			Color(1, 1, 1, 0.6 * (1.0 - k)))
