extends Node
class_name WandererDirector

# Runs the Wanderer, the neutral mote-runner (see Wanderer).
#
#   schedule  the first one spawns at wanderer_first_spawn; the next one
#             wanderer_respawn after the last one died OR escaped.
#   place     a seeded pick among the map's "mote_spawn" points (the same
#             open, reachable spots the trickle uses), preferring ones no hero
#             can see. Maps can add "wanderer_spawn" markers to override.
#   level     its stats follow the heroes' average level, like a jungle camp.
#   Motes     each hit that hurts drops wanderer_motes_per_hit loose Motes
#             (anyone can grab them; nothing is banked for a team). Killing it
#             drops whatever it still holds and pays the killer a little gold.
#             Every Mote is tagged MoteLedger.WANDERER.
#
# Signals for the announcer and HUD: wanderer_spawned, wanderer_killed,
# wanderer_escaped.

signal wanderer_spawned(wanderer: Wanderer)
signal wanderer_killed(wanderer: Wanderer, killer: Hero)
signal wanderer_escaped(wanderer: Wanderer)

const GROUP := &"wanderer_director"
const SPAWN_GROUP := &"wanderer_spawn"
const SMALL_MOTE := "res://resources/match/small_mote.tres"
const SCENE := "res://scenes/match/wanderer.tscn"

var events: MapEvents
var manager: MatchManager
var wanderer: Wanderer
## Match-clock time of the next spawn (INF while one is up).
var next_spawn_time: float = 0.0
var spawn_count: int = 0

var _scheduled := false


static func find(tree: SceneTree) -> WandererDirector:
	return tree.get_first_node_in_group(GROUP) as WandererDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	events = get_parent() as MapEvents
	manager = events.manager if events != null else null
	if manager != null:
		manager.clock_jumped.connect(func(_from, to): resync_to_clock(to))


func get_rules() -> MapEventRules:
	return MapEvents.rules_for(get_tree())


func get_clock() -> float:
	return manager.clock if manager != null else 0.0


func seed_value() -> int:
	return manager.match_seed if manager != null else 1


func is_up() -> bool:
	return wanderer != null and is_instance_valid(wanderer) and not wanderer.health_component.is_dead()


func _physics_process(_delta: float) -> void:
	var rules := get_rules()
	if manager == null or not manager.is_playing() or not rules.wanderer_enabled:
		return
	if not _scheduled:
		_scheduled = true
		next_spawn_time = rules.wanderer_first_spawn
	if not is_up() and get_clock() >= next_spawn_time:
		spawn()


func spawn_points() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for group in [SPAWN_GROUP, &"mote_spawn"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node2D:
				result.append(node)
		if not result.is_empty():
			break
	result.sort_custom(func(a: Node2D, b: Node2D): return str(a.get_path()) < str(b.get_path()))
	return result


## The point for the n-th Wanderer: seeded, off the heroes' screens if possible.
func pick_point(n: int) -> Node2D:
	var points := spawn_points()
	if points.is_empty():
		return null
	var mote_director := MoteDirector.find(get_tree())
	var unseen: Array[Node2D] = []
	if mote_director != null:
		unseen = points.filter(func(p: Node2D): return not mote_director.is_point_seen(p))
	var pool := unseen if not unseen.is_empty() else points
	return pool[(manager.seeded_int("wanderer_spot", n) if manager != null else n) % pool.size()]


## Spawn one now (the schedule, or debug), replacing any that is up.
func spawn() -> Wanderer:
	var rules := get_rules()
	var data := rules.wanderer_data
	if data == null:
		return null
	var point := pick_point(spawn_count)
	if point == null:
		next_spawn_time = get_clock() + rules.wanderer_respawn    # nowhere to put it
		return null
	despawn()
	spawn_count += 1
	var objectives := ObjectiveDirector.find(get_tree())
	var level := data.get_level(objectives.get_average_level() if objectives != null else 1.0)
	var body: Wanderer = load(SCENE).instantiate()
	body.data = data
	body.level = level
	body.rules = rules
	body.director = self
	body.home = point.global_position
	body.position = point.global_position
	get_tree().current_scene.add_child(body)
	body.slain.connect(_on_slain.bind(body))
	body.escaped.connect(_on_escaped.bind(body))
	wanderer = body
	next_spawn_time = INF
	wanderer_spawned.emit(body)
	MatchManager.play_world_cue(body, &"wanderer_spawn", {"position": body.global_position})
	return body


## Remove the Wanderer without a reward or a respawn timer (debug, resets).
func despawn() -> void:
	if wanderer != null and is_instance_valid(wanderer):
		wanderer.set_physics_process(false)
		wanderer.queue_free()
	wanderer = null


func force_spawn() -> void:
	spawn()


## After a clock jump: nothing up; the next comes at the later of its first
## time and now.
func resync_to_clock(clock: float) -> void:
	despawn()
	_scheduled = true
	next_spawn_time = maxf(get_rules().wanderer_first_spawn, clock)


func _on_slain(killer: Hero, body: Wanderer) -> void:
	var rules := get_rules()
	var rewarded := killer != null and manager != null and manager.has_hero(killer)
	if rewarded:
		manager.grant_actor(killer, rules.wanderer_gold_reward, 0.0, MatchManager.REASON_OBJECTIVE)
	drop_motes(body, body.holding)
	body.holding = 0
	wanderer_killed.emit(body, killer if rewarded else null)
	MatchManager.play_world_cue(body, &"wanderer_slain", {"position": body.global_position})
	next_spawn_time = get_clock() + rules.wanderer_respawn
	if wanderer == body:
		wanderer = null


func _on_escaped(body: Wanderer) -> void:
	wanderer_escaped.emit(body)
	next_spawn_time = get_clock() + get_rules().wanderer_respawn
	if wanderer == body:
		wanderer = null


## Loose Motes flying out of the Wanderer (for anyone to grab).
func drop_motes(body: Wanderer, count: int) -> Array[Mote]:
	var motes: Array[Mote] = []
	if count <= 0:
		return motes
	var rules := get_rules()
	var data: MoteData = load(SMALL_MOTE)
	var mult := 1.0
	var mote_director := MoteDirector.find(get_tree())
	if mote_director != null and rules.motes_use_late_mult:
		mult = mote_director.get_value_multiplier()
	var value := roundi(data.value * mult)
	var from := body.global_position
	var rng := manager.make_rng("wanderer_drop/%d/%d" % [spawn_count, int(body.age * 10.0)]) if manager != null \
		else RandomNumberGenerator.new()
	var start := rng.randf() * TAU
	for i in count:
		var direction := Vector2.from_angle(start + TAU * i / maxf(count, 1.0))
		var at := from + direction * rng.randf_range(80.0, 150.0)
		motes.append(Mote.spawn(self, data, at, value, true, from, null, -1.0, MoteLedger.WANDERER))
	MatchManager.play_world_cue(body, &"wanderer_drop", {"position": from, "count": count})
	return motes
