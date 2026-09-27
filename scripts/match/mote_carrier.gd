extends Node
class_name MoteCarrier

# The Motes a hero is carrying. Every hero has one (hero_base.tscn,
# Components/MoteCarrier); it only does anything once Motes exist.
#
#   carry       up to MatchRules.max_carried Motes; a Dream Mote takes one
#               slot. Motes are data here (MoteData + value), not nodes: the
#               MoteOrbit child draws them circling the hero, and a drop
#               spawns fresh Motes.
#   death       every Mote bursts out in a ring and lands scattered
#   jostle      an ENEMY displacement (Actor.displaced: a push or pull of at
#               least jostle_min_distance, a carry, an abduction) knocks
#               jostle_drop_fraction of the stack (at least one) loose where
#               the carrier lands, once the forced move, flight,
#               carry or minigame is over. A displacement_taken multiplier
#               of 0 (Iron Will-style) means no jostle.
#   reveal      carried value steps (MatchRules.reveal_values) ping the enemy
#               minimap, then show the carrier all the time; carrying a
#               Dream Mote always shows them
#   heavy       extra_air_time(): jump pads add it to the flight
#   deposits    can_deposit(): not airborne, abducted or inside a
#               ContainmentRing. take_highest() hands Motes to a Dreamer (M3).
#
# Signals: changed(count, value), dropped(position, n), deposit_ready.

signal changed(count: int, value: int)
signal dropped(position: Vector2, count: int)
## can_deposit() just became true while carrying something.
signal deposit_ready

const NODE_NAME := &"MoteCarrier"
const REVEALED_GROUP := &"minimap_revealed"

var actor: Hero
var _values: Array[int] = []
var _datas: Array[MoteData] = []
var _jostles: int = 0
var _last_jostle_time: float = -INF
var _jostle_pending := false
var _jostle_by: Node
var _time: float = 0.0
var _ping_left: float = 0.0
var _was_ready := false
var _orbit: MoteOrbit


static func find_on(node: Node) -> MoteCarrier:
	if node == null or not is_instance_valid(node):
		return null
	var carrier := node.get_node_or_null(NodePath("Components/" + NODE_NAME))
	return carrier as MoteCarrier


## Extra seconds a jump pad adds to `actor`'s flight (heavy pockets).
static func extra_air_time(for_actor: Node) -> float:
	var carrier := find_on(for_actor)
	return carrier.get_mote_count() * carrier.get_rules().heavy_pockets_air_time if carrier != null else 0.0


func _ready() -> void:
	actor = (owner if owner != null else get_parent().get_parent()) as Hero
	if actor == null:
		return
	# The actor's own @onready references aren't set until its _ready, which
	# runs after ours.
	await actor.ready
	actor.health_component.died.connect(_on_died)
	actor.displaced.connect(_on_displaced)
	_orbit = MoteOrbit.new()
	_orbit.name = "MoteOrbit"
	_orbit.carrier = self
	actor.add_child.call_deferred(_orbit)


func get_rules() -> MatchRules:
	var manager := MatchManager.find(get_tree()) if is_inside_tree() else null
	return manager.get_rules() if manager != null else MatchRules.current()


# --- Reading ----------------------------------------------------------------

func get_mote_count() -> int:
	return _values.size()


func get_mote_value() -> int:
	var total := 0
	for v in _values:
		total += v
	return total


func get_max() -> int:
	return get_rules().max_carried


func has_dream_mote() -> bool:
	return _datas.any(func(d: MoteData): return d.is_dream)


func get_datas() -> Array[MoteData]:
	return _datas


func can_pick_up() -> bool:
	# Never `visible`: a bush hides actors on the local screen only.
	if actor == null or actor.health_component.is_dead():
		return false
	if get_mote_count() >= get_max():
		return false
	var host := MinigameHost.find_on(actor)
	return host == null or not host.is_playing()


## Standing somewhere a deposit could tick: not airborne, abducted or inside
## a ContainmentRing, and alive.
func can_deposit() -> bool:
	if actor == null or actor.health_component.is_dead() or actor.is_airborne():
		return false
	var host := MinigameHost.find_on(actor)
	if host != null and host.is_playing():
		return false
	for node in get_tree().get_nodes_in_group(ContainmentRing.GROUP):
		var ring := node as ContainmentRing
		if ring != null and not ring.has_ended() and ring.is_inside(actor.global_position):
			return false
	return true


# --- Changing ----------------------------------------------------------------

## Returns false (and adds nothing) when full.
func add_mote(data: MoteData, value: int) -> bool:
	if get_mote_count() >= get_max():
		return false
	_values.append(value)
	_datas.append(data)
	_emit_changed()
	MatchManager.play_world_cue(actor, &"mote_pickup", {"position": actor.global_position,
		"count": get_mote_count(), "pitch": get_rules().chime_pitch(get_mote_count())})
	var director := MoteDirector.find(get_tree())
	if director != null and data.is_dream:
		director.on_dream_mote_picked_up(actor)
	return true


## Remove and return the most valuable Mote: {"data": MoteData, "value": int},
## or {} when empty. For deposits.
func take_highest() -> Dictionary:
	if _values.is_empty():
		return {}
	var best := 0
	for i in _values.size():
		if _values[i] > _values[best]:
			best = i
	var taken := {"data": _datas[best], "value": _values[best]}
	_values.remove_at(best)
	_datas.remove_at(best)
	_emit_changed()
	return taken


## Drop everything without scattering it (debug, tests).
func clear() -> void:
	_values.clear()
	_datas.clear()
	_jostle_pending = false
	_emit_changed()


## Drop one Mote (the last picked up) `distance` px away, where the carrier can
## reach it. Their own regrab lockout applies.
func drop_one(distance: float = -1.0) -> Mote:
	if _values.is_empty():
		return null
	var data: MoteData = _datas.pop_back()
	var value: int = _values.pop_back()
	var d := distance if distance >= 0.0 else get_rules().jostle_drop_distance
	var at := _clear_point(actor.global_position, Vector2.from_angle(randf() * TAU), d)
	var mote := Mote.spawn(actor, data, at, value, true, actor.global_position, actor)
	_emit_changed()
	MatchManager.play_world_cue(actor, &"mote_drop", {"position": at})
	dropped.emit(at, 1)
	return mote


## Drop the last `n` picked up (a jostle), fanned out around the carrier.
func drop_some(n: int) -> Array[Mote]:
	var spawned: Array[Mote] = []
	var start := randf() * TAU
	var d := get_rules().jostle_drop_distance
	n = mini(n, get_mote_count())
	for i in n:
		var data: MoteData = _datas.pop_back()
		var value: int = _values.pop_back()
		var at := _clear_point(actor.global_position, Vector2.from_angle(start + TAU * i / maxi(n, 1)),
			d * randf_range(0.8, 1.3))
		spawned.append(Mote.spawn(actor, data, at, value, true, actor.global_position, actor))
	if n > 0:
		_emit_changed()
		MatchManager.play_world_cue(actor, &"mote_drop", {"position": actor.global_position, "count": n})
		dropped.emit(actor.global_position, n)
	return spawned


## Every Mote bursts out in a ring (death).
func burst_all() -> Array[Mote]:
	var spawned: Array[Mote] = []
	var n := _values.size()
	if n == 0:
		return spawned
	var from := actor.global_position
	var start := randf() * TAU
	var radius := get_rules().burst_radius
	for i in n:
		var at := _clear_point(from, Vector2.from_angle(start + TAU * i / n), radius * randf_range(0.5, 1.4))
		spawned.append(Mote.spawn(actor, _datas[i], at, _values[i], true, from, actor))
	_values.clear()
	_datas.clear()
	_jostle_pending = false
	_emit_changed()
	MatchManager.play_world_cue(actor, &"mote_burst", {"position": from, "count": n, "radius": radius})
	dropped.emit(from, n)
	return spawned


# --- Ticking -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if actor == null:
		return
	_time += delta
	if _jostle_pending and _is_settled():
		_jostle_pending = false
		if not actor.health_component.is_dead():
			drop_some(get_rules().jostle_drop_count(get_mote_count()))
	var can_now := get_mote_count() > 0 and can_deposit()
	if can_now and not _was_ready:
		deposit_ready.emit()
	_was_ready = can_now
	_update_reveal(delta)


func _update_reveal(delta: float) -> void:
	var interval := get_reveal_interval()
	var always := interval == 0.0 and not actor.health_component.is_dead()
	if always != actor.is_in_group(REVEALED_GROUP):
		if always:
			actor.add_to_group(REVEALED_GROUP)
		else:
			actor.remove_from_group(REVEALED_GROUP)
	if interval > 0.0 and not actor.health_component.is_dead():
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = interval
			get_tree().call_group(&"minimaps", &"add_ping", actor.global_position,
				MatchManager.other_team(actor.team), &"carrier")
	else:
		_ping_left = 0.0


## -1 = hidden, 0 = always shown, > 0 = seconds between enemy minimap pings.
func get_reveal_interval() -> float:
	if get_mote_count() == 0:
		return -1.0
	if has_dream_mote():
		return 0.0
	return get_rules().reveal_interval_for(get_mote_value())


func _on_died() -> void:
	burst_all()


func _on_displaced(source: Node, distance: float) -> void:
	if get_mote_count() == 0 or actor.health_component.is_dead():
		return
	var rules := get_rules()
	var by_team := CombatQueries.team_of(_actor_of(source))
	if by_team == &"" or by_team == actor.team or distance < rules.jostle_min_distance:
		return
	if StatusEffectComponent.multiplier_of(actor.status_component, StatusEffect.DISPLACEMENT_TAKEN) <= 0.0:
		return
	if _time - _last_jostle_time > rules.jostle_window:
		_jostles = 0
	_last_jostle_time = _time
	_jostles += 1
	if _jostles >= maxi(rules.jostle_displacements_required, 1):
		_jostles = 0
		_jostle_pending = true
		_jostle_by = source


func is_jostle_pending() -> bool:
	return _jostle_pending


# Done being moved: the Mote drops where they land.
func _is_settled() -> bool:
	if actor.is_airborne() or actor.movement_component.is_forced_moving():
		return false
	if actor.status_component.is_carried():
		return false
	var host := MinigameHost.find_on(actor)
	return host == null or not host.is_playing()


func _emit_changed() -> void:
	changed.emit(get_mote_count(), get_mote_value())


# A point `distance` along `direction`, pulled back from any wall.
func _clear_point(from: Vector2, direction: Vector2, distance: float) -> Vector2:
	var to := from + direction * distance
	if not actor.is_inside_tree():
		return to
	var query := PhysicsRayQueryParameters2D.create(from, to, GameRules.current().wall_mask | MapLayers.LOW_COVER)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return from + direction * maxf(from.distance_to(hit.position) - 60.0, 0.0)


static func _actor_of(source: Node) -> Node:
	var node := source
	while node != null and is_instance_valid(node):
		if node is Actor:
			return node
		node = node.get_parent()
	return source if is_instance_valid(source) else null
