extends FrontalBlocker
class_name PlacedBarrier

# A projectile-blocking barrier placed in the world (Horace's Shield Wall):
# a FrontalBlocker that faces a fixed direction and stops where it was put.
# Instead of HP it has CHARGES: each enemy projectile it catches uses one
# (whatever its damage); at 0 it drops until one recharges (every
# recharge_time). It lasts `lifetime` seconds. Melee and area blasts pass,
# like any FrontalBlocker. Placed by PlaceBarrierAbility (PlaceBarrierData).
#
# Signals (on top of FrontalBlocker's): charge_used(left), expired.

signal charge_used(left: int)
signal expired

var facing := Vector2.RIGHT
var max_charges: int = 3
var charges: int = 3
var recharge_time: float = 3.0
var lifetime: float = 4.0
var life_left: float = 4.0
var _recharge: float = 0.0
var _ended := false


static func place(owner_node: Node2D, at: Vector2, face: Vector2, settings: Dictionary) -> PlacedBarrier:
	var barrier := PlacedBarrier.new()
	barrier.owner_actor = owner_node
	barrier.facing = face.normalized() if face != Vector2.ZERO else Vector2.RIGHT
	for key in settings:
		barrier.set(key, settings[key])
	barrier.charges = barrier.max_charges
	barrier.life_left = barrier.lifetime
	barrier.hp = barrier.max_hp
	barrier.position = at
	owner_node.get_tree().current_scene.add_child(barrier)
	barrier.global_position = at
	barrier._raised = true
	return barrier


func get_facing() -> Vector2:
	return facing


func is_blocking() -> bool:
	return not _ended and charges > 0


func absorb(info: DamageInfo) -> float:
	if not is_blocking():
		return 0.0
	charges -= 1
	absorbed.emit(info.amount, info)
	charge_used.emit(charges)
	if charges <= 0:
		_recharge = 0.0
		broken.emit()
	queue_redraw()
	return info.amount


func end() -> void:
	if _ended:
		return
	_ended = true
	_raised = false
	expired.emit()
	lowered.emit()
	queue_free()


func _physics_process(delta: float) -> void:
	if _ended:
		return
	if not is_instance_valid(owner_actor):
		end()
		return
	life_left -= delta
	if life_left <= 0.0:
		end()
		return
	if charges < max_charges:
		_recharge += delta
		if _recharge >= recharge_time:
			_recharge = 0.0
			charges += 1
	queue_redraw()


func _draw() -> void:
	var half := deg_to_rad(arc_degrees) / 2.0
	var start := facing.angle() - half
	var ratio := float(charges) / maxf(max_charges, 1)
	var alpha := 0.25 + 0.75 * ratio
	draw_arc(Vector2.ZERO, radius, start, start + half * 2.0, 24, Color(color, color.a * alpha), 16.0, true)
	for i in max_charges:
		var a := start + half * 2.0 * (i + 0.5) / max_charges
		draw_circle(Vector2.from_angle(a) * (radius - 18.0), 5.0, Color(1, 1, 1, 0.9 if i < charges else 0.2))
