extends Node2D
class_name MoteOrbit

# Cosmetic: a MoteCarrier's Motes circling its hero. The ring widens a little
# with each Mote so the stack reads at a glance, and a Dream Mote rides
# bigger. Added by the carrier as a child of the hero; gameplay never reads it.

const BASE_RADIUS := 78.0
const RADIUS_PER_MOTE := 9.0
const SPIN := 1.6
const SIZE_SCALE := 0.72

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
	var radius := BASE_RADIUS + RADIUS_PER_MOTE * n
	# Squashed a little vertically: it reads as a ring around the hero's feet.
	for i in n:
		var a := _t * SPIN + TAU * i / n
		var at := Vector2(cos(a) * radius, sin(a) * radius * 0.7) + Vector2(0, -10)
		var data: MoteData = datas[i]
		MoteLook.draw_mote(self, at, data.size * SIZE_SCALE, _t + i * 1.7, Vector2.from_angle(a + PI * 0.5) * 0.6,
			1.0, data.is_dream, 1.0, 4.0 * sin(_t * 5.0 + i))
