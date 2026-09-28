extends Node
class_name MovementComponent

# Turns "I want to go this way" into a velocity. Also owns every kind of
# involuntary or scripted motion: dashes, lunges, knockbacks, launches.
#
# Priority each tick:
#   0. carried (StatusEffect.carry_*): dragged along with the applier,
#      holding the offset it had when the status landed (a wave, a grab)
#   1. forced move (dash, lunge, knockback/pull, launch): exact velocity
#   2. stunned or rooted: brake to a stop, ignore input
#   3. cruise (set_cruise): a driven run along a direction the caller
#      steers every tick (a mount, a steered ride), ignoring input
#   4. compelled (StatusEffect.compel_*): walk toward the applier's current
#      position (or, in a formation, to this follower's point on the
#      applier's trail); replaces or adds to the input depending on the
#      status. Holding input against a breakable formation breaks free.
#   5. normal steering, times status multipliers and action multipliers
#
# Every controller (player hero, enemy AI, dummy, jungle creature) steers
# through get_velocity(), so they all obey 0-4 without knowing about them.
#
# Wall slams: while someone else is moving this body (begin_knockback: a hit's
# knockback impulse, a status push or pull), hitting a wall on
# GameRules.wall_impact_mask (hard walls, crystal, ability walls; not pits or
# low cover) at GameRules.wall_impact_min_speed or more emits wall_impact,
# once per knock, and the body's `wall_impact` cue. The body calls
# after_slide() right after move_and_slide().

## Knocked into a wall (see above). `impact_speed` is the speed into the wall
## (px/s), `source` who knocked the body (may be null or freed), `collider`
## the wall.
signal wall_impact(normal: Vector2, impact_speed: float, source: Node, collider: Object)

@export var move_speed: float = 300.0
@export var acceleration: float = 1200.0
@export var friction: float = 1600.0
## Optional. Reads the move_speed multiplier and root/stun from active statuses.
@export var status_component: StatusEffectComponent

# A forced move (dash, pull, launch) replaces steering for its duration.
var _forced_velocity := Vector2.ZERO
var _forced_time_left: float = 0.0
var _just_finished_forced_move := false
# Whether to leave the forced move at running speed (dash) or dead stop
# (knockback, lunge), so displacement distances are exact.
var _forced_carry := true
var _pending_stop := false
# Knockback is added once to the next velocity and then decays naturally
# through acceleration/friction.
var _pending_impulse := Vector2.ZERO
# Speed strips (or any node with boost_velocity(v) -> Vector2 and a
# `multiplier`) currently under the body. A zone may also have a
# `drift_velocity` (Vector2): ground that carries you (a travelator); you
# walk on top of it, and standing still rides it.
var _speed_zones: Array[Node] = []
# "Commitment" slows while attacking. Keyed by whoever asked (an ability), so
# two overlapping requests can't clear each other: the slowest one wins, and
# each requester only removes its own.
var _action_multipliers: Dictionary = {}    # Object -> float
# Seconds of input held against a breakable formation.
var _break_hold: float = 0.0
# Cruise (set_cruise): one requester at a time, the latest wins.
var _cruise_requester: Object
var _cruise_direction := Vector2.ZERO
var _cruise_speed: float = 0.0
var _cruise_acceleration: float = -1.0
# Wall slams: who is knocking this body, for how much longer (s), and
# whether this knock already slammed.
var _knock_source: Node
var _knock_left: float = 0.0
var _knock_reported := false
# The velocity get_velocity() last handed out (before walls cut it).
var _intended_velocity := Vector2.ZERO
# Was carried last tick: stop dead when the carry ends (a drop, not a slide).
var _was_carried := false


# `carry_momentum`: leave at running speed afterwards (dashes feel fluid) or
# stop dead (knockback, lunges: exact distances).
func start_forced_move(velocity: Vector2, duration: float, carry_momentum: bool = true) -> void:
	_forced_velocity = velocity
	_forced_time_left = duration
	_forced_carry = carry_momentum


# End a forced move early without the usual "leave at running speed" carry.
func stop_forced_move() -> void:
	_forced_time_left = 0.0
	_just_finished_forced_move = false
	_pending_stop = false


func is_forced_moving() -> bool:
	return _forced_time_left > 0.0


func get_forced_time_left() -> float:
	return maxf(_forced_time_left, 0.0)


# Move exactly `distance` along `direction` over `duration` seconds. Used by
# dashes, attack lunges and CC displacement. Walls still stop it.
#
# The duration is rounded to whole physics ticks and the speed adjusted to
# match, so the distance comes out the same on every machine.
func displace(direction: Vector2, distance: float, duration: float, carry_momentum: bool = false) -> void:
	if distance <= 0.0 or direction == Vector2.ZERO:
		return
	# A new move of its own ends any knock (a status push calls
	# begin_knockback again right after).
	_knock_left = 0.0
	var tick := 1.0 / Engine.physics_ticks_per_second
	var ticks := maxi(1, roundi(duration / tick))
	duration = ticks * tick
	# Half a tick of slack so float drift can't add or drop a tick.
	start_forced_move(direction.normalized() * distance / duration, duration - tick * 0.5, carry_momentum)


func apply_knockback(impulse: Vector2) -> void:
	_pending_impulse += impulse


## Someone else is now moving this body (a knockback, push or pull) for
## `duration` seconds: a wall hit in that time is a slam (wall_impact).
func begin_knockback(source: Node, duration: float) -> void:
	_knock_source = source
	_knock_left = maxf(duration, 0.0)
	_knock_reported = false


func is_knocked_back() -> bool:
	return _knock_left > 0.0


## Call right after the body's move_and_slide(): checks this tick's wall
## contacts for a slam (see wall_impact).
func after_slide(body: CharacterBody2D) -> void:
	if _knock_left <= 0.0:
		return
	_knock_left -= body.get_physics_process_delta_time()
	if _knock_reported:
		return
	var rules := GameRules.current()
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var wall := hit.get_collider() as CollisionObject2D
		if wall == null or wall.collision_layer & rules.wall_impact_mask == 0:
			continue
		var speed := -_intended_velocity.dot(hit.get_normal())
		if speed < rules.wall_impact_min_speed:
			continue
		_knock_reported = true
		var source := _knock_source if is_instance_valid(_knock_source) else null
		wall_impact.emit(hit.get_normal(), speed, source, wall)
		# A cue for the body's VisualProfile / AudioProfile (a thud, dust).
		if body.has_method(&"trigger_cue"):
			body.trigger_cue(&"wall_impact", {"position": hit.get_position(), "direction": -hit.get_normal(),
				"normal": hit.get_normal(), "impact_speed": speed, "knocked_by": source})
		return


func add_speed_zone(zone: Node) -> void:
	if zone not in _speed_zones:
		_speed_zones.append(zone)


func remove_speed_zone(zone: Node) -> void:
	_speed_zones.erase(zone)


# Slow (or speed up) walking while `requester` is doing something, e.g. 0.4
# while swinging a sword. Call clear_action_multiplier when it's done.
func set_action_multiplier(requester: Object, multiplier: float) -> void:
	_action_multipliers[requester] = multiplier


func clear_action_multiplier(requester: Object) -> void:
	_action_multipliers.erase(requester)


func get_action_multiplier() -> float:
	var result := 1.0
	for value in _action_multipliers.values():
		result = minf(result, value)
	return result


# Drive the body along `direction` at `speed` px/s (times the MOVE_SPEED
# status multiplier, so slows still bite) instead of following input. The
# caller steers by calling this again every tick with a new direction.
# Stuns and roots still stop it and forced moves still take priority.
# `accel` < 0 uses the normal acceleration.
func set_cruise(requester: Object, direction: Vector2, speed: float, accel: float = -1.0) -> void:
	_cruise_requester = requester
	_cruise_direction = direction.normalized()
	_cruise_speed = speed
	_cruise_acceleration = accel


# Only the requester that set the cruise can clear it.
func clear_cruise(requester: Object) -> void:
	if _cruise_requester == requester:
		_cruise_requester = null
		_cruise_direction = Vector2.ZERO


func is_cruising() -> bool:
	return is_instance_valid(_cruise_requester) and _cruise_direction != Vector2.ZERO


func can_walk() -> bool:
	return status_component == null or not status_component.is_rooted()


func get_move_speed() -> float:
	return move_speed \
		* StatusEffectComponent.multiplier_of(status_component, StatusEffect.MOVE_SPEED) \
		* get_action_multiplier()


func get_velocity(
	current_velocity: Vector2,
	input_direction: Vector2,
	delta: float
) -> Vector2:
	_intended_velocity = _steer(current_velocity, input_direction, delta)
	return _intended_velocity


func _steer(current_velocity: Vector2, input_direction: Vector2, delta: float) -> Vector2:

	var carried: Variant = _carry_velocity(delta)
	if carried != null:
		return carried
	if _was_carried:
		# Dropped: land where the carry left us instead of sliding on.
		_was_carried = false
		current_velocity = Vector2.ZERO

	# The countdown happens here, in the same call that applies the forced
	# velocity, so an N-tick move moves exactly N times no matter which node
	# processes first.
	if is_forced_moving():
		_forced_time_left -= delta
		if _forced_time_left <= 0.0:
			_just_finished_forced_move = true
			if not _forced_carry:
				# Stop dead: this tick's motion is the last one.
				_just_finished_forced_move = false
				_pending_stop = true
		return _forced_velocity

	if _pending_stop:
		_pending_stop = false
		current_velocity = Vector2.ZERO

	if not can_walk():
		input_direction = Vector2.ZERO

	var speed := get_move_speed()
	var accel := acceleration
	if can_walk() and is_cruising():
		input_direction = _cruise_direction
		speed = _cruise_speed * StatusEffectComponent.multiplier_of(status_component, StatusEffect.MOVE_SPEED)
		if _cruise_acceleration >= 0.0:
			accel = _cruise_acceleration
	var compel_velocity := Vector2.ZERO
	if can_walk() and status_component != null and not is_cruising():
		var effect := status_component.get_compel_effect()
		if effect != null:
			compel_velocity = _compel_velocity(effect, status_component.get_compel_source(), speed)
			if _struggles_free(effect, input_direction, compel_velocity, delta):
				compel_velocity = Vector2.ZERO
			elif effect.compel_overrides_input:
				input_direction = Vector2.ZERO
		else:
			_break_hold = 0.0
	if _just_finished_forced_move:
		# Leave a dash at normal running speed instead of sliding at dash speed.
		_just_finished_forced_move = false
		current_velocity = current_velocity.limit_length(speed)

	current_velocity += _pending_impulse
	_pending_impulse = Vector2.ZERO

	var target_velocity := input_direction * speed + compel_velocity
	var drift := Vector2.ZERO
	for zone in _speed_zones:
		if is_instance_valid(zone):
			target_velocity = zone.boost_velocity(target_velocity)
			accel *= zone.multiplier
			var carry: Variant = zone.get(&"drift_velocity")
			if carry is Vector2:
				drift += carry
	target_velocity += drift

	if input_direction != Vector2.ZERO or compel_velocity != Vector2.ZERO:
		# Faster than we want to go (e.g. a swing just slowed us): brake with
		# friction rather than acceleration so the slow bites immediately.
		var rate := accel if current_velocity.length() <= target_velocity.length() else maxf(accel, friction)
		return current_velocity.move_toward(target_velocity, rate * delta)

	return current_velocity.move_toward(
		drift,
		friction * delta
	)


# Carried (StatusEffect.carry_enabled): the velocity that puts the body back
# on its carry point this tick, or null when not carried. Replaces every
# other kind of motion, so a carried target can't be knocked or dashed out.
func _carry_velocity(delta: float) -> Variant:
	if status_component == null or delta <= 0.0:
		return null
	var effect := status_component.get_carry_effect()
	var carrier := status_component.get_carrier()
	var body := (owner if owner != null else get_parent()) as Node2D
	if effect == null or carrier == null or body == null:
		return null
	if not _was_carried:
		# Whatever was moving us (a knockback, a dash) is over.
		stop_forced_move()
		_pending_impulse = Vector2.ZERO
	_was_carried = true
	var goal := carrier.global_position + status_component.get_carry_offset()
	return ((goal - body.global_position) / delta).limit_length(effect.carry_max_speed)


# Walk toward `source` at a fraction of our own speed; nothing inside the
# stop distance. Re-aimed every tick, so a moving source is followed.
func _compel_velocity(effect: StatusEffect, source: Node2D, speed: float) -> Vector2:
	var body := (owner if owner != null else get_parent()) as Node2D
	if body == null or source == null:
		return Vector2.ZERO
	var goal := source.global_position
	if effect.compel_follow_trail:
		var recorder := TrailRecorder.find_on(source)
		if recorder != null:
			goal = recorder.get_follow_point(body, effect.compel_trail_spacing)
	var to_source := goal - body.global_position
	var distance := to_source.length()
	if distance <= effect.compel_stop_distance:
		return Vector2.ZERO
	var compel_speed := speed * effect.compel_speed_multiplier
	# Don't overshoot the stop distance in one tick.
	var tick := 1.0 / Engine.physics_ticks_per_second
	compel_speed = minf(compel_speed, (distance - effect.compel_stop_distance) / tick)
	return to_source / distance * compel_speed


# Breakable formations: holding input against the pull for
# compel_break_hold_time breaks free (the status ends). Returns true on
# the tick it breaks.
func _struggles_free(effect: StatusEffect, input_direction: Vector2, pull: Vector2, delta: float) -> bool:
	if not (effect.compel_follow_trail and effect.compel_breakable) or input_direction == Vector2.ZERO:
		_break_hold = 0.0
		return false
	var formation := pull.normalized()
	if formation == Vector2.ZERO:
		var source := status_component.get_compel_source()
		var body := (owner if owner != null else get_parent()) as Node2D
		if source != null and body != null:
			formation = body.global_position.direction_to(source.global_position)
	if formation == Vector2.ZERO or input_direction.normalized().dot(formation) > -0.3:
		_break_hold = 0.0
		return false
	_break_hold += delta
	if _break_hold < effect.compel_break_hold_time:
		return false
	_break_hold = 0.0
	status_component.break_formation()
	return true
