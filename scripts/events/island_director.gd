extends Node
class_name IslandDirector

# The Mote Island: one secret portal, a small room behind it, a cache of Motes.
#
#   portal    exactly one IslandPortal, at one of the map's
#             "island_portal_spawn" markers. Which one is drawn from the match
#             seed (differs every game), never the same twice in a row. It is
#             not on the minimap.
#   relocate  every island_relocate_time the portal despawns and reappears at a
#             NEW spot (a pure function of the match seed and the period, so a
#             clock jump lands on the right one). Anyone on the Island is sent
#             home first, the cache refills, and portal_relocated fires: the
#             HUD plays a faint chime and glow with no place in it.
#   enter     request_enter(hero): teleports that hero (and only them) in. It
#             is an open room: everyone who came through is in it together.
#   stay      island_stay_time is the longest a visitor stays; the exit portal
#             (request_leave) or death gets them out sooner. They return to the
#             spot they left from (safe: a free point beside it).
#   cache     island_cache_motes Motes, tagged MoteLedger.ISLAND. Picking them
#             up follows the normal rules (carry cap: the rest stays on the
#             ground until the next relocation). Refilled each relocation.
#
# Bots ignore the Island for now: see bot_can_use_island().

signal portal_spawned(portal: IslandPortal)
## The portal moved (or closed). Carries no position: it is a tell, not a clue.
signal portal_relocated
signal hero_entered(hero: Hero)
signal hero_left(hero: Hero, reason: StringName)

const GROUP := &"island_director"
const SPAWN_GROUP := &"island_portal_spawn"
const LEAVE_TIMEOUT := &"timeout"
const LEAVE_EXIT := &"exit"
const LEAVE_CLOSED := &"closed"
const LEAVE_DIED := &"died"
const SMALL_MOTE := "res://resources/match/small_mote.tres"

var events: MapEvents
var manager: MatchManager
var portal: IslandPortal
var area: IslandArea
## The relocation period the portal is on (-1 = none yet).
var period: int = -1

var _shift: float = 0.0
var _visitors: Dictionary = {}    # Hero -> {return_to: Vector2, left: float}
var _landed: int = 0
var _warned := false


static func find(tree: SceneTree) -> IslandDirector:
	return tree.get_first_node_in_group(GROUP) as IslandDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	events = get_parent() as MapEvents
	manager = events.manager if events != null else null
	if manager != null:
		manager.clock_jumped.connect(func(_from, _to): _shift = 0.0)


func get_rules() -> MapEventRules:
	return MapEvents.rules_for(get_tree())


func get_clock() -> float:
	return (manager.clock if manager != null else 0.0) + _shift


func has_portal() -> bool:
	return portal != null and is_instance_valid(portal)


## Seconds until the portal moves.
func get_time_to_relocate() -> float:
	var rules := get_rules()
	var into := get_clock() - rules.island_first_spawn_time
	if into < 0.0:
		return -into
	return rules.island_relocate_time - fmod(into, rules.island_relocate_time)


## The relocation period at `clock` (-1 = the portal isn't up yet).
func period_at(clock: float) -> int:
	var rules := get_rules()
	if clock < rules.island_first_spawn_time:
		return -1
	return int(floorf((clock - rules.island_first_spawn_time) / rules.island_relocate_time))


## The marker index (into spots()) the portal uses in period `p`: from the
## match seed, and never the one it used in period p - 1.
func spot_index(p: int) -> int:
	var count := spots().size()
	if count == 0 or p < 0:
		return -1
	if count == 1:
		return 0
	var previous := -1
	var pick := 0
	for k in p + 1:
		pick = (manager.seeded_int("island_spot", k) if manager != null else k) % count
		if pick == previous:
			pick = (pick + 1 + (manager.seeded_int("island_skip", k) if manager != null else k) % (count - 1)) % count
		previous = pick
	return pick


## The markers a portal can appear at, in a fixed order.
func spots() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		if node is Node2D:
			result.append(node)
	result.sort_custom(func(a: Node2D, b: Node2D): return str(a.get_path()) < str(b.get_path()))
	return result


func is_on_island(hero: Hero) -> bool:
	return _visitors.has(hero)


func get_visitors() -> Array[Hero]:
	var heroes: Array[Hero] = []
	for hero in _visitors:
		heroes.append(hero)
	return heroes


## Seconds a visitor has left (INF with no stay limit).
func get_stay_left(hero: Hero) -> float:
	return float((_visitors.get(hero, {}) as Dictionary).get("left", 0.0))


## TODO(bots): bots ignore the Island. When they learn it, this is the hook
## (where to go, when it is worth the stay); keep it false until then.
func bot_can_use_island(_bot: Hero) -> bool:
	return false


func _physics_process(delta: float) -> void:
	var rules := get_rules()
	if manager == null or not manager.is_playing() or not rules.island_enabled or spots().is_empty():
		if has_portal():
			_remove_portal(LEAVE_CLOSED)
		return
	var target := period_at(get_clock())
	if target < 0:
		return
	if target != period or not has_portal():
		_set_period(target)
	_tick_visitors(delta)


func _set_period(target: int) -> void:
	var rules := get_rules()
	var first_time := period < 0 and area == null
	_remove_portal(LEAVE_CLOSED)
	period = target
	var options := spots()
	var index := spot_index(target)
	if index < 0:
		return
	_ensure_area()
	portal = IslandPortal.new()
	portal.name = "IslandPortal"
	portal.rules = rules
	portal.index = target
	portal.spot = index
	get_tree().current_scene.add_child(portal)
	portal.global_position = options[index].global_position
	refill_cache()
	portal_spawned.emit(portal)
	if not first_time:
		portal_relocated.emit()
		MatchManager.play_world_cue(portal, &"island_relocate", {"position": portal.global_position})


func _ensure_area() -> void:
	if area != null and is_instance_valid(area):
		return
	area = IslandArea.new()
	area.name = "IslandArea"
	get_tree().current_scene.add_child(area)
	area.setup(get_rules())


func _remove_portal(reason: StringName) -> void:
	for hero in _visitors.keys():
		_send_home(hero, reason)
	if has_portal():
		portal.queue_free()
	portal = null


# --- Visiting ----------------------------------------------------------------------------------

## "" if `hero` can step through right now, else why not.
func get_enter_block_reason(hero: Hero) -> String:
	if not has_portal():
		return "No portal"
	if hero == null or manager == null or not manager.has_hero(hero) or hero.health_component.is_dead():
		return "Not available"
	if _visitors.has(hero):
		return "Already on the Island"
	if not portal.can_interact(hero):
		return "Too far"
	if hero.is_airborne():
		return "In the air"
	return ""


## Step `hero` through the portal. Returns "" on success, else the reason.
func request_enter(hero: Hero) -> String:
	var reason := get_enter_block_reason(hero)
	if reason != "":
		return reason
	var rules := get_rules()
	var came_from := hero.global_position
	if not hero.teleport_to(area.landing_point(_landed)):
		return "Blocked"
	_landed += 1
	_visitors[hero] = {"return_to": portal.global_position, "left": rules.island_stay_time if rules.island_stay_time > 0.0 else INF}
	hero.remove_from_group(&"minimap_units")    # nobody's minimap shows the Island
	hero.health_component.died.connect(_on_visitor_died.bind(hero), CONNECT_ONE_SHOT)
	MatchManager.play_world_cue(hero, &"island_enter", {"position": came_from})
	hero_entered.emit(hero)
	return ""


## Send `hero` back to the map (the exit portal). Returns "" on success.
func request_leave(hero: Hero) -> String:
	if not _visitors.has(hero):
		return "Not on the Island"
	_send_home(hero, LEAVE_EXIT)
	return ""


func _tick_visitors(delta: float) -> void:
	for hero in _visitors.keys():
		if not is_instance_valid(hero):
			_visitors.erase(hero)
			continue
		_visitors[hero].left -= delta
		if _visitors[hero].left <= 0.0:
			_send_home(hero, LEAVE_TIMEOUT)


func _on_visitor_died(hero: Hero) -> void:
	if _visitors.has(hero):
		# Dead: the MatchManager respawns them at their base; just forget them.
		_forget(hero)
		hero_left.emit(hero, LEAVE_DIED)


func _send_home(hero: Hero, reason: StringName) -> void:
	var record: Dictionary = _visitors.get(hero, {})
	if record.is_empty():
		return
	_forget(hero)
	if is_instance_valid(hero) and not hero.health_component.is_dead():
		var spot := _safe_point(record.return_to, hero)
		if not hero.teleport_to(spot):
			hero.global_position = spot    # a ContainmentRing must not strand them
			hero.velocity = Vector2.ZERO
		MatchManager.play_world_cue(hero, &"island_exit", {"position": spot})
	hero_left.emit(hero, reason)


func _forget(hero: Hero) -> void:
	_visitors.erase(hero)
	if not is_instance_valid(hero):
		return
	if not hero.is_in_group(&"minimap_units"):
		hero.add_to_group(&"minimap_units")
	if hero.health_component.died.is_connected(_on_visitor_died.bind(hero)):
		hero.health_component.died.disconnect(_on_visitor_died.bind(hero))


# A free spot at or beside `point` for a hero body (never inside a wall).
func _safe_point(point: Vector2, hero: Hero) -> Vector2:
	var state := hero.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = 50.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = MapLayers.WALK_BLOCKERS
	query.exclude = [hero.get_rid()]
	for ring in 4:
		for step in (1 if ring == 0 else 8):
			var offset := Vector2.ZERO if ring == 0 else Vector2.from_angle(TAU * step / 8.0) * (100.0 * ring)
			query.transform = Transform2D(0.0, point + offset)
			if state.intersect_shape(query, 1).is_empty():
				return point + offset
	return point


# --- Cache ----------------------------------------------------------------------------------------

func get_cache_motes() -> Array[Mote]:
	var result: Array[Mote] = []
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote != null and mote.source == MoteLedger.ISLAND and not mote.is_queued_for_deletion():
			result.append(mote)
	return result


## Wipe what is left of the cache and lay a fresh one.
func refill_cache() -> Array[Mote]:
	for mote in get_cache_motes():
		mote.queue_free()
	var made: Array[Mote] = []
	if area == null or not is_instance_valid(area):
		return made
	var rules := get_rules()
	var data: MoteData = load(SMALL_MOTE)
	var mult := 1.0
	var director := MoteDirector.find(get_tree())
	if director != null and rules.motes_use_late_mult:
		mult = director.get_value_multiplier()
	for i in rules.island_cache_motes:
		made.append(Mote.spawn(area, data, area.cache_point(i, rules.island_cache_motes),
			roundi(data.value * mult), false, null, null, -1.0, MoteLedger.ISLAND))
	return made


# --- Debug -------------------------------------------------------------------------------------------

## Relocate now: the schedule moves to the start of the next period.
func force_relocate() -> void:
	var rules := get_rules()
	var clock := manager.clock if manager != null else 0.0
	var next_period := maxi(period_at(clock + _shift) + 1, 0)
	_shift = rules.island_first_spawn_time + next_period * rules.island_relocate_time - clock
