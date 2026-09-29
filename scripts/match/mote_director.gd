extends Node
class_name MoteDirector

# Spawns the match's Motes (a child of MatchManager; it makes one if the
# scene doesn't). Runs only while the match is PLAYING, on the match clock.
# Every number is in MatchRules (Spawning, Late match).
#
#   trickle        a small Mote every trickle_interval at a free point in the
#                  "mote_spawn" group, while fewer than max_loose_motes are
#                  loose. Points no hero can see are preferred.
#   dreaming zone  every zone_interval a mirrored pair of DreamZones (both
#                  halves together, never the same pair twice in a row) is
#                  announced zone_warning early, then dreams for
#                  zone_duration, spawning a Mote in each half every
#                  zone_spawn_interval (up to zone_max_per_half each).
#   Dream Mote     first at dream_mote_first_time, announced
#                  dream_mote_warning early at the "dream_mote_spawn" point.
#                  At most one exists (loose or carried). Once it's gone
#                  (faded, or banked in M3) the next comes dream_mote_interval
#                  later.
#   late match     after late_match_time, new Motes are worth
#                  late_match_value_mult times as much.

signal zone_warning(pair_id: StringName, zone_name: String, seconds: float)
signal zone_started(pair_id: StringName, zone_name: String)
signal zone_ended(pair_id: StringName, zone_name: String)
signal dream_mote_warning(position: Vector2, seconds: float)
signal dream_mote_spawned(mote: Mote)
signal dream_mote_picked_up(actor: Hero)
signal dream_mote_dropped(mote: Mote)

const GROUP := &"mote_director"
const SMALL := "res://resources/match/small_mote.tres"
const DREAM := "res://resources/match/dream_mote.tres"
## A spawn point with a loose Mote this close is taken.
const POINT_CLEARANCE := 140.0

var manager: MatchManager
var small_data: MoteData
var dream_data: MoteData

var _trickle_left: float = 0.0
var _next_zone_time: float = 0.0
var _zone_phase: DreamZone.ZoneState = DreamZone.ZoneState.OFF
var _zone_pair: StringName = &""
var _last_pair: StringName = &""
var _zone_start: float = 0.0
var _zone_spawn_left: Dictionary = {}    # DreamZone -> seconds
var _next_dream_time: float = 0.0
var _dream_warned := false
var _dream_out := false


static func find(tree: SceneTree) -> MoteDirector:
	return tree.get_first_node_in_group(GROUP) as MoteDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	manager = get_parent() as MatchManager
	small_data = load(SMALL)
	dream_data = load(DREAM)
	reset_schedule()
	if manager != null:
		manager.clock_jumped.connect(func(_from, to): resync_to_clock(to))


func get_rules() -> MatchRules:
	return manager.get_rules() if manager != null else MatchRules.current()


func get_clock() -> float:
	return manager.clock if manager != null else 0.0


func reset_schedule() -> void:
	var rules := get_rules()
	_trickle_left = rules.trickle_interval
	_next_zone_time = rules.zone_first_time
	_next_dream_time = rules.dream_mote_first_time
	_dream_warned = false


func _physics_process(delta: float) -> void:
	if manager == null or not manager.is_playing():
		return
	_tick_trickle(delta)
	_tick_zones(delta)
	_tick_dream_mote()


# --- Queries -------------------------------------------------------------------

func get_value_multiplier() -> float:
	var rules := get_rules()
	return rules.late_match_value_mult if get_clock() >= rules.late_match_time else 1.0


func get_loose_motes(include_dream: bool = false) -> Array[Mote]:
	var motes: Array[Mote] = []
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote != null and not mote.is_queued_for_deletion() and (include_dream or not mote.is_dream()):
			motes.append(mote)
	return motes


func get_spawn_points() -> Array[Node2D]:
	var points: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(&"mote_spawn"):
		if node is Node2D:
			points.append(node)
	return points


func get_zones() -> Array[DreamZone]:
	var zones: Array[DreamZone] = []
	for node in get_tree().get_nodes_in_group(DreamZone.GROUP):
		if node is DreamZone:
			zones.append(node)
	return zones


## pair id -> [DreamZone, DreamZone]
func get_zone_pairs() -> Dictionary:
	var pairs := {}
	for zone in get_zones():
		if not pairs.has(zone.pair_id):
			pairs[zone.pair_id] = []
		pairs[zone.pair_id].append(zone)
	return pairs


func get_active_pair() -> StringName:
	return _zone_pair


func get_zone_phase() -> DreamZone.ZoneState:
	return _zone_phase


func get_dream_point() -> Vector2:
	var point := get_tree().get_first_node_in_group(&"dream_mote_spawn") as Node2D
	return point.global_position if point != null else Vector2.ZERO


## A Dream Mote is loose on the map or carried by someone.
func dream_mote_exists() -> bool:
	for mote in get_loose_motes(true):
		if mote.is_dream():
			return true
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var carrier := MoteCarrier.find_on(node)
		if carrier != null and carrier.has_dream_mote():
			return true
	return false


func get_next_dream_time() -> float:
	return _next_dream_time


func get_next_zone_time() -> float:
	return _next_zone_time


# --- Spawning ----------------------------------------------------------------

## A new Mote at `at`, worth its data's value times the late-match multiplier.
func spawn_mote(at: Vector2, dream: bool = false, from: Node = null) -> Mote:
	var data := dream_data if dream else small_data
	var source := MoteLedger.DREAM if dream else (MoteLedger.ZONE if from is DreamZone else MoteLedger.TRICKLE)
	var mote := Mote.spawn(self, data, at, roundi(data.value * get_value_multiplier()),
		false, null, null, -1.0, source)
	mote.origin = from
	return mote


## Remove every loose Mote, and empty every carrier (debug).
func clear_motes() -> void:
	for mote in get_loose_motes(true):
		mote.queue_free()
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var carrier := MoteCarrier.find_on(node)
		if carrier != null:
			carrier.clear()


func _tick_trickle(delta: float) -> void:
	var rules := get_rules()
	_trickle_left -= delta
	if _trickle_left > 0.0:
		return
	_trickle_left = rules.trickle_interval
	if get_loose_motes().filter(func(m: Mote): return m.source != MoteLedger.ISLAND).size() >= rules.max_loose_motes:
		return    # (the sealed Island cache doesn't count against the map)
	var point := pick_trickle_point()
	if point != null:
		spawn_mote(point.global_position, false, point)


## A free mote_spawn point, preferring ones no hero can see. null = none free.
func pick_trickle_point() -> Node2D:
	var unseen: Array[Node2D] = []
	var seen: Array[Node2D] = []
	var loose := get_loose_motes(true)
	for point in get_spawn_points():
		if _is_taken(point, loose):
			continue
		if is_point_seen(point):
			seen.append(point)
		else:
			unseen.append(point)
	if not unseen.is_empty():
		return unseen.pick_random()
	return seen.pick_random() if not seen.is_empty() else null


func is_point_seen(point: Node2D) -> bool:
	var range_limit := get_rules().spawn_sight_range
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		if hero.health_component.is_dead():
			continue
		if hero.global_position.distance_to(point.global_position) <= range_limit \
				and CombatQueries.walls_clear(hero, point):
			return true
	return false


func _is_taken(point: Node2D, loose: Array[Mote]) -> bool:
	for mote in loose:
		if mote.global_position.distance_to(point.global_position) < POINT_CLEARANCE:
			return true
	return false


# --- Dreaming zones ------------------------------------------------------------

func _tick_zones(delta: float) -> void:
	var rules := get_rules()
	var clock := get_clock()
	match _zone_phase:
		DreamZone.ZoneState.OFF:
			if clock >= _next_zone_time - rules.zone_warning:
				_begin_warning()
		DreamZone.ZoneState.WARNING:
			if clock >= _next_zone_time:
				_zone_start = clock
				_set_pair_state(DreamZone.ZoneState.DREAMING)
				for zone in _pair_zones():
					_zone_spawn_left[zone] = 0.0
				zone_started.emit(_zone_pair, _pair_name())
				MatchManager.play_world_cue(self, &"zone_start", {"position": _pair_zones()[0].global_position})
		DreamZone.ZoneState.DREAMING:
			for zone in _pair_zones():
				_zone_spawn_left[zone] = float(_zone_spawn_left.get(zone, 0.0)) - delta
				if _zone_spawn_left[zone] <= 0.0:
					_zone_spawn_left[zone] = rules.zone_spawn_interval
					_spawn_in_zone(zone)
			if clock >= _zone_start + rules.zone_duration:
				_set_pair_state(DreamZone.ZoneState.OFF)
				zone_ended.emit(_zone_pair, _pair_name())
				_last_pair = _zone_pair
				_zone_pair = &""
				_next_zone_time = _zone_start + rules.zone_interval


func _begin_warning() -> void:
	var pairs := get_zone_pairs()
	var choices: Array = pairs.keys().filter(func(id): return id != _last_pair and pairs[id].size() == 2)
	if choices.is_empty():
		choices = pairs.keys()
	if choices.is_empty():
		_next_zone_time = INF    # this map has no zones
		return
	_zone_pair = choices.pick_random()
	_zone_phase = DreamZone.ZoneState.WARNING
	_set_pair_state(DreamZone.ZoneState.WARNING, maxf(_next_zone_time - get_clock(), 0.1))
	zone_warning.emit(_zone_pair, _pair_name(), maxf(_next_zone_time - get_clock(), 0.0))


func _set_pair_state(state: DreamZone.ZoneState, fade_in: float = 1.0) -> void:
	_zone_phase = state
	for zone in _pair_zones():
		zone.set_zone_state(state, fade_in)


func _pair_zones() -> Array:
	return get_zone_pairs().get(_zone_pair, [])


func _pair_name() -> String:
	var zones := _pair_zones()
	return zones[0].display_name if not zones.is_empty() else str(_zone_pair)


func _spawn_in_zone(zone: DreamZone) -> void:
	var loose := get_loose_motes(true)
	var in_zone := loose.filter(func(m: Mote): return m.origin == zone).size()
	if in_zone >= get_rules().zone_max_per_half:
		return
	var free: Array[Node2D] = []
	for point in zone.get_spawn_points():
		if not _is_taken(point, loose):
			free.append(point)
	if not free.is_empty():
		spawn_mote(free.pick_random().global_position, false, zone)


## After a clock jump: end any zone in progress and put the next zone and
## Dream Mote on the times the regular schedule would give them. A zone the
## new time falls inside starts dreaming at once (for its full duration).
## A Dream Mote already out stays out.
func resync_to_clock(clock: float) -> void:
	var rules := get_rules()
	if _zone_phase != DreamZone.ZoneState.OFF:
		_set_pair_state(DreamZone.ZoneState.OFF)
		zone_ended.emit(_zone_pair, _pair_name())
		_last_pair = _zone_pair
		_zone_pair = &""
	_next_zone_time = _next_on_schedule(rules.zone_first_time, rules.zone_interval, clock, rules.zone_duration)
	_trickle_left = rules.trickle_interval
	if not _dream_out and not dream_mote_exists():
		_dream_warned = false
		_next_dream_time = _next_on_schedule(rules.dream_mote_first_time, rules.dream_mote_interval, clock, 0.0)


# The first first + k * interval whose [start, start + length) isn't over.
static func _next_on_schedule(first: float, interval: float, clock: float, length: float) -> float:
	if clock < first or interval <= 0.0:
		return first
	var k := floorf((clock - first) / interval)
	var start := first + k * interval
	return start if clock < start + length else start + interval


## Debug: announce the next dreaming zone now.
func force_next_zone() -> void:
	if _zone_phase != DreamZone.ZoneState.OFF:
		return
	_next_zone_time = get_clock() + get_rules().zone_warning
	_begin_warning()


# --- Dream Mote -----------------------------------------------------------------

func _tick_dream_mote() -> void:
	var rules := get_rules()
	var clock := get_clock()
	var exists := dream_mote_exists()
	if _dream_out and not exists:
		# Gone for good (faded or banked): the timer restarts.
		_dream_out = false
		_dream_warned = false
		_next_dream_time = clock + rules.dream_mote_interval
	if _dream_out or exists:
		return
	if not _dream_warned and clock >= _next_dream_time - rules.dream_mote_warning:
		_dream_warned = true
		var seconds := maxf(_next_dream_time - clock, 0.0)
		dream_mote_warning.emit(get_dream_point(), seconds)
		MatchManager.play_world_cue(self, &"dream_mote_warning", {"position": get_dream_point(),
			"radius": dream_data.magnet_radius * 1.6, "duration": seconds})
	if clock >= _next_dream_time:
		var mote := spawn_mote(get_dream_point(), true)
		_dream_out = true
		dream_mote_spawned.emit(mote)


# Every Mote reports in as it enters the world (Mote._ready).
func on_mote_appeared(mote: Mote) -> void:
	if mote.is_dream():
		_dream_out = true
		if mote.dropped:
			dream_mote_dropped.emit(mote)


func on_dream_mote_picked_up(actor: Hero) -> void:
	dream_mote_picked_up.emit(actor)
