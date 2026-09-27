extends Node2D
class_name MoteOrbit

# Cosmetic: a MoteCarrier's Motes circling its hero, in rings: the first
# RING_SIZES[0] on an inner ring, the next on a wider one, the rest on the
# outermost, each ring turning the other way. A big stack reads as a swarm at
# a glance; a Dream Mote rides bigger. Added by the carrier as a child of the
# hero; gameplay never reads it.

const RING_RADII: Array[float] = [80.0, 116.0, 150.0]
const RING_SIZES: Array[int] = [8, 9, 99]
const SPIN := 1.6
const SIZE_SCALE := 0.7
const OUTER_SCALE := 0.6

var carrier: MoteCarrier
var _t := 0.0


func _ready() -> void:
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if carrier == null or not is_instance_valid(carrier) or carrier.actor == null:
		return
	var datas := carrier.get_datas()
	var n := datas.size()
	if n == 0 or carrier.actor.health_component.is_dead():
		return
	var index := 0
	for ring in RING_RADII.size():
		var in_ring := mini(n - index, RING_SIZES[ring])
		if in_ring <= 0:
			break
		var direction := 1.0 if ring % 2 == 0 else -1.0
		var scale_k := SIZE_SCALE if ring == 0 else OUTER_SCALE
		for j in in_ring:
			# Squashed a little vertically: it reads as a ring around the hero.
			var a := direction * _t * SPIN / (1.0 + ring * 0.4) + TAU * j / in_ring + ring * 0.3
			var at := Vector2(cos(a) * RING_RADII[ring], sin(a) * RING_RADII[ring] * 0.7) + Vector2(0, -10)
			var data: MoteData = datas[index]
			MoteLook.draw_mote(self, at, data.size * scale_k, _t + index * 1.7,
				Vector2.from_angle(a + PI * 0.5 * direction) * 0.6, 1.0, data.is_dream, 1.0, 4.0 * sin(_t * 5.0 + index))
			index += 1
