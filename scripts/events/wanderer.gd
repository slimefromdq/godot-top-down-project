extends NeutralMonster
class_name Wanderer

# The Wanderer: a neutral mote-runner (scenes/match/wanderer.tscn, a
# NeutralMonster with its own brain). It reuses the neutral body: health,
# hurtbox, the placeholder gel look, the "neutral" team both sides can hit, the
# NeutralData for stats / size / colour, and the bots' navigation graph for its
# escape routes. It never attacks.
#
#   WANDER   idles, then ambles to a nearby spot, and idles again
#   FLEE     from its first hurt until calm_time passes without damage: it
#            drops Motes (motes_per_hit per hit that does damage, up to what it
#            holds) and runs at flee_speed, faster than any hero's base speed
#
# Choosing where to run: every wanderer_repath_interval it samples
# wanderer_flee_candidates destinations around it, asks the navigation graph
# for a route to each, and scores it: far from every hero along the route and
# at the end, in OPEN ground (many graph points within a few hops, so a dead
# end scores nothing and a dead-end candidate is dropped), without a long
# detour. Cornered (nothing open to run to, or pinned on a wall) it slows to
# wanderer_cornered_speed_mult. It escapes if it lives too long
# (max_lifetime) or survives escape_time after its first hit.
#
# Every number is in MapEventRules; the WandererDirector spawns it, pays the
# killer and drops what it still holds when it dies.

signal hurt(hero: Hero, dropped: int)
signal escaped

enum Mode { WANDER, FLEE }

var rules: MapEventRules
var director: WandererDirector
var mode: Mode = Mode.WANDER
## Motes it still carries (each hit that hurts drops some).
var holding: int = 0
var cornered := false
var age: float = 0.0
var minimap_fogged := true

var _rng := RandomNumberGenerator.new()
var _nav: BotNavigation
var _path := PackedVector2Array()
var _path_index := 0
var _repath_left: float = 0.0
var _hurt_age: float = INF
var _first_hit_age: float = -1.0
var _drop_cooldown: float = 0.0
var _last_attacker: Hero
var _pause_left: float = 1.0
var _wander_to := Vector2.INF
var _threats: Array[Vector2] = []
var _escaping := false
# The candidate directions are fixed per Wanderer, so re-planning is stable.
var _flee_phase: float = 0.0


func _enter_tree() -> void:
	super._enter_tree()
	add_to_group(&"minimap_objectives")


func _ready() -> void:
	super._ready()
	if rules == null:
		rules = MapEvents.rules_for(get_tree())
	holding = rules.wanderer_max_motes
	movement_component.acceleration = rules.wanderer_acceleration
	_rng.seed = hash("%d/%s/%d" % [director.seed_value() if director != null else 1, "wander", int(home.x) ^ int(home.y)])
	_flee_phase = _rng.randf() * TAU
	_pause_left = rules.wanderer_wander_pause * _rng.randf()


func is_fighting() -> bool:
	return mode == Mode.FLEE    # the look opens its eyes wide


func is_fleeing() -> bool:
	return mode == Mode.FLEE


## Seconds since it was last damaged (INF = never).
func seconds_since_hurt() -> float:
	return _hurt_age


func draw_minimap_icon(canvas: Object, at: Vector2, _viewer_team: StringName) -> void:
	canvas.draw_circle(at, 4.5, Color.BLACK)
	canvas.draw_circle(at, 3.5, Color("fde047") if mode == Mode.FLEE else Color("fef9c3"))


func _physics_process(delta: float) -> void:
	if health_component.is_dead() or _escaping:
		return
	age += delta
	_hurt_age += delta
	_drop_cooldown = maxf(_drop_cooldown - delta, 0.0)
	if _first_hit_age >= 0.0:
		_first_hit_age += delta
	if mode == Mode.FLEE and _hurt_age >= rules.wanderer_calm_time:
		_calm_down()
	if age >= rules.wanderer_max_lifetime or (_first_hit_age >= 0.0 and _first_hit_age >= rules.wanderer_escape_time):
		_escape()
		return
	var steer := _flee_steer(delta) if mode == Mode.FLEE else _wander_steer(delta)
	var speed := rules.wanderer_flee_speed if mode == Mode.FLEE else rules.wanderer_wander_speed
	if cornered:
		speed *= rules.wanderer_cornered_speed_mult
	movement_component.move_speed = speed
	velocity = movement_component.get_velocity(velocity, steer, delta)
	move_and_slide()
	movement_component.after_slide(self)
	if velocity.length() > 20.0:
		aim_direction = velocity.normalized()
	if mode == Mode.FLEE and steer != Vector2.ZERO and velocity.length() < speed * 0.35 and get_slide_collision_count() > 0:
		cornered = true    # pinned on a wall


# --- Damage -----------------------------------------------------------------------------------------

func _on_damage_taken(info: DamageInfo) -> void:
	var hero := hero_of(info.source)
	if hero == null:
		return
	_hurt_age = 0.0
	_last_attacker = hero
	if _first_hit_age < 0.0:
		_first_hit_age = 0.0
	if mode != Mode.FLEE:
		mode = Mode.FLEE
		_repath_left = 0.0
		_path = PackedVector2Array()
	var dropped := 0
	if info.final_amount >= rules.wanderer_min_hit_damage and _drop_cooldown <= 0.0 and holding > 0:
		_drop_cooldown = rules.wanderer_hit_drop_cooldown
		dropped = mini(rules.wanderer_motes_per_hit, holding)
		holding -= dropped
		if director != null:
			director.drop_motes(self, dropped)
	hurt.emit(hero, dropped)


func _calm_down() -> void:
	mode = Mode.WANDER
	cornered = false
	_path = PackedVector2Array()
	_wander_to = Vector2.INF
	_pause_left = rules.wanderer_wander_pause
	_last_attacker = null


func _escape() -> void:
	_escaping = true
	set_physics_process(false)
	hurtbox.set_deferred("monitorable", false)
	escaped.emit()
	var tween := create_tween()
	tween.tween_property(visuals, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)


# --- Wandering ---------------------------------------------------------------------------------------

func _wander_steer(delta: float) -> Vector2:
	if _wander_to == Vector2.INF:
		_pause_left -= delta
		if _pause_left > 0.0:
			return Vector2.ZERO
		var angle := _rng.randf() * TAU
		var candidate := home + Vector2.from_angle(angle) * _rng.randf_range(0.3, 1.0) * rules.wanderer_wander_radius
		_nav = BotNavigation.for_node(self)
		if _nav != null:
			var snapped := _nav.nearest_position(candidate)
			if snapped == Vector2.INF:
				_pause_left = 0.5
				return Vector2.ZERO
			candidate = snapped
			_path = _trim_route(_nav.path(global_position, candidate), global_position)
			_path_index = 0
		_wander_to = candidate
	if global_position.distance_to(_wander_to) < 50.0:
		_wander_to = Vector2.INF
		_pause_left = rules.wanderer_wander_pause * _rng.randf_range(0.5, 1.5)
		return Vector2.ZERO
	return _follow_path(_wander_to)


# --- Fleeing -----------------------------------------------------------------------------------------

func _flee_steer(delta: float) -> Vector2:
	_repath_left -= delta
	if _repath_left <= 0.0 or _path_index >= _path.size():
		_repath_left = rules.wanderer_repath_interval
		_plan_flee()
	if _path_index < _path.size():
		return _follow_path(_path[_path.size() - 1])
	# No graph (a map without one): just run straight away from the threats.
	return _away_from_threats()


func _gather_threats() -> void:
	_threats.clear()
	var radius := rules.wanderer_threat_radius
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		if hero != null and not hero.health_component.is_dead() and hero.global_position.distance_to(global_position) <= radius:
			_threats.append(hero.global_position)
	if is_instance_valid(_last_attacker) and not _last_attacker.health_component.is_dead():
		_threats.append(_last_attacker.global_position)


func _away_from_threats() -> Vector2:
	var away := Vector2.ZERO
	for threat in _threats:
		away += (global_position - threat).normalized() / maxf(global_position.distance_to(threat) / 400.0, 0.5)
	return away.normalized() if away != Vector2.ZERO else Vector2.from_angle(_rng.randf() * TAU)


func _plan_flee() -> void:
	_gather_threats()
	_nav = BotNavigation.for_node(self)
	if _nav == null:
		_path = PackedVector2Array()
		return
	var here := global_position
	var hops := rules.wanderer_openness_hops
	var count := maxi(rules.wanderer_flee_candidates, 1)
	var incumbent := _path[_path.size() - 1] if not _path.is_empty() else Vector2.INF
	var best_path := PackedVector2Array()
	var best_score := -INF
	var best_is_dead_end := true
	# One more candidate than the ring: the escape it is already running to.
	for i in count + 1:
		var is_incumbent := i == count
		if is_incumbent and incumbent == Vector2.INF:
			continue
		var target := incumbent if is_incumbent \
			else here + Vector2.from_angle(_flee_phase + TAU * i / count) * rules.wanderer_flee_distance
		var route := _trim_route(_nav.path(here, target), here)
		if route.size() < 2:
			continue
		var length := _route_length(route)
		var end := route[route.size() - 1]
		var open_end := _nav.openness_at(end, hops)
		var open_mid := _nav.openness_at(route[route.size() / 2], hops)
		var safety := _route_safety(route)
		var detour := maxf(length - here.distance_to(end), 0.0)
		var score := safety * rules.wanderer_threat_weight + (open_end + open_mid) * 0.5 * rules.wanderer_openness_weight \
			- detour * rules.wanderer_detour_weight + (rules.wanderer_flee_stickiness if is_incumbent else 0.0)
		var dead_end := open_end < rules.wanderer_dead_end_cells
		# A dead end only wins when every route is one.
		if (best_is_dead_end and not dead_end) or (dead_end == best_is_dead_end and score > best_score):
			best_score = score
			best_path = route
			best_is_dead_end = dead_end
	_path = best_path
	_path_index = 0
	cornered = best_is_dead_end or _nav.openness_at(here, hops) < rules.wanderer_cornered_cells


# A route starts at the graph point nearest to us, which may lie behind us:
# drop it (and the next ones) while going straight to the following point is
# shorter, so it doesn't turn back before it runs.
func _trim_route(route: PackedVector2Array, from: Vector2) -> PackedVector2Array:
	var trimmed := route.duplicate()
	while trimmed.size() > 2 and from.distance_to(trimmed[1]) <= trimmed[0].distance_to(trimmed[1]):
		trimmed.remove_at(0)
	return trimmed


# The closest a route comes to any threat, sampled along it.
func _route_safety(route: PackedVector2Array) -> float:
	if _threats.is_empty():
		return rules.wanderer_flee_distance
	var closest := INF
	for i in route.size():
		for threat in _threats:
			closest = minf(closest, route[i].distance_to(threat))
	# The end of the route matters most: weigh it in again.
	var end_distance := INF
	for threat in _threats:
		end_distance = minf(end_distance, route[route.size() - 1].distance_to(threat))
	return (closest + end_distance) * 0.5


func _route_length(route: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	return total


func _follow_path(fallback_target: Vector2) -> Vector2:
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) < 60.0:
		_path_index += 1
	var target := _path[_path_index] if _path_index < _path.size() else fallback_target
	var to_target := target - global_position
	return to_target.normalized() if to_target.length() > 1.0 else Vector2.ZERO
