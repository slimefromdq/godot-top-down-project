extends Deployable
class_name MoteDrone

# An autonomous agent: a small flying drone that fetches loose Motes for its
# owner. States:
#
#   WANDER   drifts between random points within values/wander_radius of the
#            owner, looking for loose Motes within values/sight_radius
#   COLLECT  flies to the nearest one and picks it up (Mote.take_by_agent),
#            up to values/carry_max
#   RETURN   carrying and full, or nothing else in sight: flies to the owner
#            and hands them over (MoteCarrier.add_mote; what doesn't fit is
#            dropped at the owner's feet)
#   FLEE     hit by an enemy: drops everything it carries where it is
#            (enemies can grab them) and flees away from the attacker for
#            values/flee_time at values/flee_speed
#
# It flies over walls (no body), can be shot (deploy_health) and dies like
# any deployable. Owner cues: <kind>_collect, <kind>_deliver, <kind>_scared.

enum State { WANDER, COLLECT, RETURN, FLEE }

var state: State = State.WANDER
var carried: Array[Dictionary] = []    # {data, value, source}
var _goal := Vector2.ZERO
var _target_mote: Mote
var _flee_left: float = 0.0
var _flee_from := Vector2.ZERO
var _wander_left: float = 0.0
var rng := RandomNumberGenerator.new()


func _deploy_ready() -> void:
	# Deterministic (same wander on every machine), like RangedAttackAbility.rng.
	rng.seed = hash(kind)
	_goal = global_position
	if health_component != null:
		health_component.damage_taken.connect(_on_hit)


func get_carried_count() -> int:
	return carried.size()


func _deploy_tick(delta: float) -> void:
	match state:
		State.FLEE:
			_flee_left -= delta
			var away := (global_position - _flee_from).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			_fly(global_position + away * 200.0, get_value(&"flee_speed"), delta)
			if _flee_left <= 0.0:
				state = State.RETURN if not carried.is_empty() else State.WANDER
		State.RETURN:
			_fly(owner_actor.global_position, get_value(&"speed"), delta)
			if global_position.distance_to(owner_actor.global_position) <= get_value(&"pickup_radius") * 2.0:
				_deliver()
				state = State.WANDER
		State.COLLECT:
			if not is_instance_valid(_target_mote) or _target_mote.is_queued_for_deletion():
				state = State.WANDER
				return
			_fly(_target_mote.global_position, get_value(&"speed"), delta)
			if global_position.distance_to(_target_mote.global_position) <= get_value(&"pickup_radius"):
				var taken := _target_mote.take_by_agent(team)
				_target_mote = null
				if not taken.is_empty():
					carried.append(taken)
					if owner_actor.has_method(&"trigger_cue"):
						owner_actor.trigger_cue(StringName(str(kind) + "_collect"), {"position": global_position,
							"count": carried.size()})
				state = State.RETURN if carried.size() >= int(get_value(&"carry_max")) else State.WANDER
		State.WANDER:
			var mote := _find_mote()
			if mote != null and carried.size() < int(get_value(&"carry_max")):
				_target_mote = mote
				state = State.COLLECT
				return
			if not carried.is_empty():
				state = State.RETURN
				return
			_wander_left -= delta
			if _wander_left <= 0.0 or global_position.distance_to(_goal) < 20.0:
				_wander_left = 2.0
				var r := get_value(&"wander_radius")
				_goal = owner_actor.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0) * r
			_fly(_goal, get_value(&"speed") * 0.6, delta)


func _fly(to: Vector2, speed: float, delta: float) -> void:
	global_position = global_position.move_toward(to, speed * delta)


# The nearest loose Mote it may take, within sight and the wander radius.
func _find_mote() -> Mote:
	var best: Mote = null
	var best_d := get_value(&"sight_radius")
	var leash := get_value(&"wander_radius") + get_value(&"sight_radius")
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote == null or not mote.can_be_taken_by_agent(team):
			continue
		if mote.global_position.distance_to(owner_actor.global_position) > leash:
			continue
		var d := mote.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = mote
	return best


func _deliver() -> void:
	var carrier := MoteCarrier.find_on(owner_actor)
	var delivered := 0
	for m in carried:
		if carrier != null and carrier.add_mote(m.data, m.value, m.source):
			delivered += 1
		else:
			Mote.spawn(self, m.data, owner_actor.global_position + Vector2.from_angle(rng.randf() * TAU) * 60.0,
				m.value, true, global_position, null, -1.0, m.source)
	carried.clear()
	if owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(StringName(str(kind) + "_deliver"), {"position": global_position, "count": delivered})


## Drop everything it carries, scattered around it (grabbable by anyone).
func drop_all() -> int:
	var n := carried.size()
	for i in n:
		var m: Dictionary = carried[i]
		var at := global_position + Vector2.from_angle(TAU * i / maxi(n, 1)) * 70.0
		Mote.spawn(self, m.data, at, m.value, true, global_position, null, -1.0, m.source)
	carried.clear()
	return n


func _on_hit(info: DamageInfo) -> void:
	if is_gone() or health_component.is_dead():
		return
	var dropped := drop_all()
	state = State.FLEE
	_flee_left = get_value(&"flee_time")
	var attacker = info.source    # untyped: may be freed
	_flee_from = attacker.global_position if is_instance_valid(attacker) and attacker is Node2D \
		else global_position - Vector2.RIGHT
	_target_mote = null
	if owner_actor.has_method(&"trigger_cue"):
		owner_actor.trigger_cue(StringName(str(kind) + "_scared"), {"position": global_position, "count": dropped})


func _on_removed(_reason: StringName) -> void:
	drop_all()


func _draw() -> void:
	super()
	for i in carried.size():
		draw_circle(Vector2.from_angle(TAU * i / carried.size() + _age * 3.0) * (data.body_radius + 4.0), 6.0, Color(0.7, 0.9, 1))
	if state == State.FLEE:
		draw_arc(Vector2.ZERO, data.body_radius + 20.0, 0.0, TAU, 24, Color(1, 0.4, 0.3, 0.8), 3.0)
