extends ChargeAbility

# Wind-Up Dash (Shift). The normal version is the generic ChargeAbility,
# all data: hold to wind (charge), release to dash min_distance..distance,
# bashing enemies on the way (hit_shape, charged damage, on_hit_status =
# the "boop" knockback).
#
# ENCORE (Pre-wound), asked for on the press: no hold. The dash fires at
# once at full distance and full bash damage, and RICOCHETS: when it meets
# a wall or an enemy it reflects off the surface normal (like a wind-up toy
# bumping round a room) up to values/prewound_bounces times, booping each
# enemy once. Each leg is an exact forced move computed when it starts, so
# it stays deterministic.
#
# Cues: <id>_bounce (context.position, .normal) per ricochet.

const KEY := preload("res://heroes/melody/abilities/melody_key.gd")

var _prewound := false
var _leg_direction := Vector2.ZERO
var _leg_time_left: float = 0.0
var _distance_left: float = 0.0
var _bounces_left: int = 0
var _pending_normal := Vector2.ZERO
var _bounced_off: Array[int] = []


func is_prewound() -> bool:
	return _prewound


func _wants_charge_now() -> bool:
	_prewound = false
	var key := KEY.find_on(actor)
	if key != null and key.consume_encore(self) >= 0.0:
		_prewound = true
		_charge_ratio = 1.0    # full bash damage
		return false
	return super()


func get_dash_direction() -> Vector2:
	return _leg_direction if _prewound and _leg_direction != Vector2.ZERO else super()


func _on_active_start() -> void:
	if not _prewound:
		super()
		return
	var charge := get_charge_data()
	_dashing = true
	_distance = charge.distance
	_distance_left = charge.distance
	_bounces_left = roundi(data.get_value(&"prewound_bounces", get_stats()))
	_bounced_off.clear()
	_leg_direction = super.get_dash_direction()
	if charge.invulnerable_duration > 0.0:
		actor.health_component.set_invulnerable_for(charge.invulnerable_duration)
	# Legs may add up to more time than the straight dash's active phase.
	current_feel.active = INF
	_start_bash()
	_start_leg()


func _on_active_tick(delta: float) -> void:
	if not _prewound:
		super(delta)
		return
	_leg_time_left -= delta
	if _leg_time_left > 0.0:
		return
	if _pending_normal != Vector2.ZERO and _bounces_left > 0 and _distance_left > 1.0:
		_bounces_left -= 1
		_leg_direction = _leg_direction.bounce(_pending_normal).normalized()
		actor.trigger_cue(StringName(str(ability_id) + "_bounce"), {
			"position": actor.global_position, "normal": _pending_normal, "direction": _leg_direction})
		_start_leg()
		return
	# Out of distance or bounces: the dash is over.
	_end_bash()
	phase_time = current_feel.active    # let _advance move on to recovery
	current_feel.active = phase_time


func _on_cast_end(interrupted: bool) -> void:
	super(interrupted)
	_prewound = false
	_leg_direction = Vector2.ZERO


# Move until the next wall or enemy (or out of distance), exactly.
func _start_leg() -> void:
	var charge := get_charge_data()
	var length := _distance_left
	_pending_normal = Vector2.ZERO
	var wall := _wall_ahead(length)
	if not wall.is_empty():
		length = wall.distance
		_pending_normal = wall.normal
	var enemy := _enemy_ahead(length)
	if not enemy.is_empty():
		length = enemy.distance
		_pending_normal = enemy.normal
		_bounced_off.append(enemy.id)
	length = maxf(length, 0.0)
	_distance_left -= length
	var duration := length / charge.speed if charge.speed > 0.0 else 0.0
	_leg_time_left = maxf(duration, 1.0 / Engine.physics_ticks_per_second)
	if length > 0.5:
		actor.movement_component.displace(_leg_direction, length, duration, false)


func _body_radius() -> float:
	var shape_node := actor.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	return 40.0


# {distance, normal} to the first wall the body would touch, or {}.
func _wall_ahead(length: float) -> Dictionary:
	var space := actor.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = _body_radius()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, actor.global_position)
	query.motion = _leg_direction * length
	query.collision_mask = GameRules.current().wall_mask
	query.exclude = [actor.get_rid()]
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[0] >= 1.0:
		return {}
	var distance: float = fractions[0] * length
	# Where it touches, ask for the surface normal.
	query.transform = Transform2D(0.0, actor.global_position + _leg_direction * (fractions[1] * length))
	query.motion = Vector2.ZERO
	var rest := space.get_rest_info(query)
	var normal: Vector2 = rest.get("normal", -_leg_direction)
	return {"distance": distance, "normal": normal}


# {distance, normal, id} to the first enemy in the way (not one already
# bounced off), or {}.
func _enemy_ahead(length: float) -> Dictionary:
	var radius := _body_radius()
	var lane := HitShape.line(length, radius * 2.0)
	var best := {}
	for hurtbox in Hitbox.query(actor, actor.global_position, _leg_direction, lane, actor):
		if _bounced_off.has(hurtbox.get_instance_id()):
			continue
		var along := (hurtbox.global_position - actor.global_position).dot(_leg_direction)
		var stop := along - radius - hurtbox.get_radius()
		if stop < 0.0 or stop > length:
			continue
		if best.is_empty() or stop < best.distance:
			var contact := actor.global_position + _leg_direction * stop
			best = {"distance": stop, "normal": (contact - hurtbox.global_position).normalized(),
				"id": hurtbox.get_instance_id()}
	return best
