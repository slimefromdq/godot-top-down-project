extends Ability
class_name ChargeAbility

# Generic telegraphed charge driven by ChargeData.
#
#   windup    the telegraph: the hero plants (slowed by the feel preset) and a
#             line shows where the charge will go, so opponents can react
#   active    the dash: an exact forced move of `distance` toward the aim,
#             dropping trail zones every `trail_spacing` pixels
#   recovery  from the feel preset
#
# Walls stop the dash (it's a normal forced move), and a stun during the
# telegraph or the dash cancels it.
#
# Cues: <id>_windup carries context.target_position and context.duration for
# the telegraph; <id>_active marks the launch; <id>_end fires on arrival.

var _last_trail_point := Vector2.ZERO
var _dashing := false
# MOVE_INPUT_OR_AIM: the direction chosen when the cast started.
var _move_direction := Vector2.ZERO


func get_charge_data() -> ChargeData:
	return data as ChargeData


func is_movement_ability() -> bool:
	return true


func _get_cast_feel() -> AttackFeel:
	# The preset supplies windup, recovery and the telegraph slow; the dash
	# length decides the active time. Work on a copy so the shared preset
	# (used by other abilities) isn't changed.
	var feel: AttackFeel = super().duplicate()
	feel.active = get_charge_data().get_dash_time()
	feel.lunge_distance = 0.0
	return feel


func _activate(_target_position: Vector2) -> String:
	var charge := get_charge_data()
	if charge == null:
		return "No charge data"
	_move_direction = Vector2.ZERO
	if charge.direction_mode == ChargeData.DirectionMode.MOVE_INPUT_OR_AIM:
		_move_direction = actor.move_direction.normalized() if actor.move_direction != Vector2.ZERO \
			else cast_direction
		cast_direction = _move_direction
	return ""


# The dash direction: the aim (which may follow the mouse during the
# telegraph), or the walking direction fixed at cast start.
func get_dash_direction() -> Vector2:
	return _move_direction if _move_direction != Vector2.ZERO else cast_direction


func _cue_context() -> Dictionary:
	var context := super()
	var charge := get_charge_data()
	context["target_position"] = actor.global_position + get_dash_direction() * charge.distance
	context["direction"] = get_dash_direction()
	context["distance"] = charge.distance
	return context


func _on_active_start() -> void:
	var charge := get_charge_data()
	_dashing = true
	actor.movement_component.displace(get_dash_direction(), charge.distance, charge.get_dash_time(), charge.carry_momentum)
	if charge.invulnerable_duration > 0.0:
		actor.health_component.set_invulnerable_for(charge.invulnerable_duration)
	elif charge.invulnerable_while_dashing:
		actor.health_component.set_invulnerable_for(charge.get_dash_time())
	_last_trail_point = actor.global_position
	_drop_trail(_last_trail_point)


func _on_active_tick(_delta: float) -> void:
	var charge := get_charge_data()
	if charge.trail_zone == null:
		return
	# Fill in every spacing step we passed this tick, so fast dashes leave an
	# unbroken trail.
	var to_here := actor.global_position - _last_trail_point
	while to_here.length() >= charge.trail_spacing:
		_last_trail_point += to_here.normalized() * charge.trail_spacing
		_drop_trail(_last_trail_point)
		to_here = actor.global_position - _last_trail_point


func _on_active_end() -> void:
	if _dashing and is_instance_valid(actor):
		actor.trigger_cue(StringName(str(ability_id) + "_end"), {"direction": get_dash_direction()})


func _on_recovery_start() -> void:
	_dashing = false


func _on_cast_end(interrupted: bool) -> void:
	# A stun mid-dash stops the body where it is.
	if interrupted and _dashing and is_instance_valid(actor):
		actor.movement_component.stop_forced_move()
	_dashing = false


func _drop_trail(point: Vector2) -> void:
	var charge := get_charge_data()
	if charge.trail_zone != null:
		GroundZone.spawn(actor, charge.trail_zone, point, get_dash_direction(), actor)
