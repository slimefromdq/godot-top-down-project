extends Node
class_name MatchManager

# The one authority for a match: its state and clock, the team rosters, gold,
# XP and levels, kill rewards, respawns and the result. It lives in a world
# scene (not an autoload) and is found through the "match_manager" group:
# MatchManager.find(get_tree()).
#
# Everything that changes is announced through a signal, so the HUD, the
# announcer (later) and a future network layer can mirror it without reaching
# in. Nothing here knows about any specific hero.
#
# Teams are &"a" (Dawn, mint, bottom) and &"b" (Dusk, coral, top). The roster
# is every Hero whose `team` is one of those; heroes join on entering the
# tree and leave on exiting it. Records (gold, XP) are kept per hero.
#
# XP is stored as progress toward the next level, and the level itself stays
# in the hero's StatsComponent. So a level set from anywhere else (the debug
# slider, a map switch) is simply the starting point for the next level.

signal state_changed(state: State)
signal gold_changed(actor: Hero, amount: float, reason: StringName)
signal xp_changed(actor: Hero, amount: float, reason: StringName)
signal level_up(actor: Hero, level: int)
signal match_ended(winner_team: StringName)
signal roster_changed
## An enemy hero died. `killer` may be null (no enemy hero landed the last
## hit); `assisters` are the other enemy heroes who damaged them recently.
signal hero_killed(victim: Hero, killer: Hero, assisters: Array[Hero])
signal hero_respawning(actor: Hero, seconds: float)
signal hero_respawned(actor: Hero)

enum State { WARMUP, PLAYING, ENDED }

const GROUP := &"match_manager"
const TEAMS: Array[StringName] = [&"a", &"b"]
const TEAM_NAMES := {&"a": "Dawn", &"b": "Dusk"}
## Dawn mint, Dusk coral (light enough for text on a dark HUD).
const TEAM_COLORS := {&"a": Color("7fe0b8"), &"b": Color("ff9e85")}

const REASON_PASSIVE := &"passive"
const REASON_KILL := &"kill"
const REASON_ASSIST := &"assist"
const REASON_DEBUG := &"debug"

## Empty = a private copy of MatchRules.current(), so the debug panel's live
## edits never touch the .tres.
@export var rules: MatchRules
## Start the warmup countdown on _ready. Tests turn it off and call
## start_warmup() / start_playing() themselves.
@export var auto_start: bool = true

var state: State = State.WARMUP
## Seconds since PLAYING began (0 during warmup).
var clock: float = 0.0
var warmup_left: float = 0.0
var winner: StringName = &""


class Record:
	var gold: float = 0.0
	## Progress toward the next level.
	var xp: float = 0.0
	var total_xp: float = 0.0
	var kills: int = 0
	var deaths: int = 0
	var assists: int = 0
	## Attacker hero -> time of their latest damage (for assists).
	var damaged_by: Dictionary = {}
	## Seconds until respawn while dead (< 0 = not waiting).
	var respawn_left: float = -1.0


var _records: Dictionary = {}    # Hero -> Record
# Monotonic simulation time (warmup included), for assist windows.
var _time: float = 0.0
var _passive_timer: float = 0.0
# Team -> respawn time multiplier (M3's stirring defenders respawn faster).
var _respawn_mult: Dictionary = {}
# The local player's record while the debug panel swaps heroes.
var _swapped_player_record: Record


static func find(tree: SceneTree) -> MatchManager:
	return tree.get_first_node_in_group(GROUP) as MatchManager if tree != null else null


static func team_name(team: StringName) -> String:
	return TEAM_NAMES.get(team, str(team))


static func team_color(team: StringName) -> Color:
	return TEAM_COLORS.get(team, Color.WHITE)


static func other_team(team: StringName) -> StringName:
	return &"b" if team == &"a" else &"a"


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(&"player_listeners")


func _ready() -> void:
	if rules == null:
		rules = MatchRules.current().duplicate()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(&"heroes"):
		_try_register(node)
	# Heroes placed in the scene after us enter the tree before we're ready,
	# but join the "heroes" group in their own _ready: catch those too.
	_register_all.call_deferred()
	if auto_start:
		start_warmup()


func _register_all() -> void:
	for node in get_tree().get_nodes_in_group(&"heroes"):
		_try_register(node)


func get_rules() -> MatchRules:
	return rules if rules != null else MatchRules.current()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func start_warmup() -> void:
	state = State.WARMUP
	clock = 0.0
	warmup_left = get_rules().warmup_time
	winner = &""
	state_changed.emit(state)
	if warmup_left <= 0.0:
		start_playing()


func start_playing() -> void:
	if state == State.PLAYING:
		return
	state = State.PLAYING
	warmup_left = 0.0
	_passive_timer = 0.0
	state_changed.emit(state)


func end_match(winner_team: StringName) -> void:
	if state == State.ENDED:
		return
	winner = winner_team
	state = State.ENDED
	state_changed.emit(state)
	match_ended.emit(winner_team)


func is_playing() -> bool:
	return state == State.PLAYING


func _physics_process(delta: float) -> void:
	_time += delta
	match state:
		State.WARMUP:
			warmup_left -= delta
			if warmup_left <= 0.0:
				start_playing()
		State.PLAYING:
			clock += delta
			_tick_passive(delta)
	_tick_respawns(delta)


func _tick_passive(delta: float) -> void:
	var r := get_rules()
	if r.passive_tick_interval <= 0.0:
		return
	_passive_timer += delta
	while _passive_timer >= r.passive_tick_interval:
		_passive_timer -= r.passive_tick_interval
		for hero in get_roster():
			grant_actor(hero, r.passive_gold_per_second * r.passive_tick_interval,
				r.passive_xp_per_second * r.passive_tick_interval, REASON_PASSIVE)


# ---------------------------------------------------------------------------
# Roster
# ---------------------------------------------------------------------------

## Every hero in the match, or only `team`'s.
func get_roster(team: StringName = &"") -> Array[Hero]:
	var heroes: Array[Hero] = []
	for hero in _records:
		if is_instance_valid(hero) and hero.team in TEAMS and (team == &"" or hero.team == team):
			heroes.append(hero)
	return heroes


func has_hero(hero: Hero) -> bool:
	return _records.has(hero)


# Move a hero to another team (the debug "Play as team" switch).
func set_hero_team(hero: Hero, team: StringName) -> void:
	hero.team = team
	if not _records.has(hero):
		_try_register(hero)
	roster_changed.emit()


func _on_node_added(node: Node) -> void:
	if node is Hero:
		# Its team and definition are set by now, but it isn't ready yet.
		_try_register.call_deferred(node)


func _try_register(node: Node) -> void:
	var hero := node as Hero
	if hero == null or not is_instance_valid(hero) or not hero.is_inside_tree():
		return
	if _records.has(hero) or not (hero.team in TEAMS):
		return
	var record := Record.new()
	if hero.player_controlled and _swapped_player_record != null:
		record = _swapped_player_record
		_swapped_player_record = null
		record.damaged_by.clear()
		record.respawn_left = -1.0
	_records[hero] = record
	hero.respawns = true
	hero.health_component.damage_taken.connect(_on_hero_damaged.bind(hero))
	hero.health_component.died.connect(_on_hero_died.bind(hero))
	hero.tree_exiting.connect(_unregister.bind(hero), CONNECT_ONE_SHOT)
	roster_changed.emit()


func _unregister(hero: Hero) -> void:
	var record: Record = _records.get(hero)
	_records.erase(hero)
	if record != null and hero.player_controlled:
		# The debug panel may be swapping this player for another hero: keep
		# their gold and XP for whoever takes over (on_player_replaced).
		_swapped_player_record = record
	for other in _records.values():
		(other as Record).damaged_by.erase(hero)
	if is_inside_tree():
		roster_changed.emit()


# The debug panel swapped the local player for another hero.
func on_player_replaced(new_player: Actor) -> void:
	_try_register(new_player)


# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------

func get_gold(hero: Hero) -> float:
	var record: Record = _records.get(hero)
	return record.gold if record != null else 0.0


## Progress toward the next level.
func get_xp(hero: Hero) -> float:
	var record: Record = _records.get(hero)
	return record.xp if record != null else 0.0


func get_total_xp(hero: Hero) -> float:
	var record: Record = _records.get(hero)
	return record.total_xp if record != null else 0.0


func get_xp_to_next(hero: Hero) -> float:
	return get_rules().xp_to_next_level(hero.get_level())


func is_max_level(hero: Hero) -> bool:
	return hero.get_level() >= hero.stats_component.get_max_level()


func get_record(hero: Hero) -> Record:
	return _records.get(hero)


## Split gold and XP evenly across `team`'s heroes (dead ones too).
func grant_team(team: StringName, gold: float, xp: float, reason: StringName) -> void:
	var heroes := get_roster(team)
	if heroes.is_empty():
		return
	for hero in heroes:
		grant_actor(hero, gold / heroes.size(), xp / heroes.size(), reason)


## Pay one hero.
func grant_actor(hero: Hero, gold: float, xp: float, reason: StringName) -> void:
	var record: Record = _records.get(hero)
	if record == null or state == State.ENDED:
		return
	if gold != 0.0:
		record.gold = maxf(record.gold + gold, 0.0)
		gold_changed.emit(hero, gold, reason)
	if xp > 0.0:
		add_xp(hero, xp, reason)


func add_xp(hero: Hero, amount: float, reason: StringName) -> void:
	var record: Record = _records.get(hero)
	if record == null or amount <= 0.0:
		return
	record.xp += amount
	record.total_xp += amount
	xp_changed.emit(hero, amount, reason)
	var r := get_rules()
	while not is_max_level(hero) and record.xp >= r.xp_to_next_level(hero.get_level()):
		record.xp -= r.xp_to_next_level(hero.get_level())
		set_level(hero, hero.get_level() + 1)
	if is_max_level(hero):
		# Nothing left to earn toward; keep the bar full rather than banking
		# XP that would all arrive at once if the cap were raised.
		record.xp = minf(record.xp, r.xp_to_next_level(hero.get_level()))


## Set a hero's level through the StatsComponent (capped at
## GameRules.max_level). Each level gained plays the level_up cue.
func set_level(hero: Hero, level: int) -> void:
	var before := hero.get_level()
	hero.stats_component.set_level(level)
	var after := hero.get_level()
	if after > before:
		level_up.emit(hero, after)
		play_match_cue(hero, &"level_up", {"level": after})


# A match cue on a hero: its own profile's entry if it has one, else the
# match-wide default from MatchRules.cue_visuals / cue_audio.
func play_match_cue(hero: Actor, cue: StringName, context: Dictionary = {}) -> void:
	var visuals := VisualsComponent.find_on(hero)
	var audio := AudioComponent.find_on(hero)
	var own_visual := visuals != null and visuals.profile != null and visuals.profile.cues.has(cue)
	var own_audio := audio != null and audio.profile != null and audio.profile.cues.has(cue)
	if own_visual or own_audio:
		hero.trigger_cue(cue, context)
	var r := get_rules()
	context.merge({"position": hero.global_position, "source": hero})
	if not own_visual and visuals != null and r.cue_visuals != null and r.cue_visuals.cues.has(cue):
		visuals.play_definition(r.cue_visuals.cues[cue], context)
	if not own_audio and audio != null and r.cue_audio != null:
		audio.play_sound(r.cue_audio.cues.get(cue), context)


# ---------------------------------------------------------------------------
# Kills and respawns
# ---------------------------------------------------------------------------

func _on_hero_damaged(info: DamageInfo, victim: Hero) -> void:
	var attacker := _hero_of(info.source)
	if attacker == null or attacker == victim or attacker.team == victim.team:
		return
	var record: Record = _records.get(victim)
	if record != null:
		record.damaged_by[attacker] = _time


func _on_hero_died(victim: Hero) -> void:
	var record: Record = _records.get(victim)
	if record == null:
		return
	record.deaths += 1
	var r := get_rules()
	var killer := _hero_of(victim.health_component.last_damage_source)
	if killer != null and (killer == victim or killer.team == victim.team or not _records.has(killer)):
		killer = null
	var assisters: Array[Hero] = []
	for attacker in record.damaged_by:
		if attacker == killer or not is_instance_valid(attacker) or not _records.has(attacker):
			continue
		if _time - float(record.damaged_by[attacker]) <= r.assist_window:
			assisters.append(attacker)
	record.damaged_by.clear()
	if state == State.PLAYING:
		if killer != null:
			(_records[killer] as Record).kills += 1
			grant_actor(killer, r.kill_gold, r.kill_xp, REASON_KILL)
		for hero in assisters:
			(_records[hero] as Record).assists += 1
			grant_actor(hero, r.assist_gold, r.assist_xp, REASON_ASSIST)
	hero_killed.emit(victim, killer, assisters)
	if state != State.ENDED:
		record.respawn_left = get_respawn_time(victim)
		hero_respawning.emit(victim, record.respawn_left)


func get_respawn_time(hero: Hero) -> float:
	return get_rules().respawn_time(hero.get_level()) * float(_respawn_mult.get(hero.team, 1.0))


## Seconds until `hero` respawns, or 0 if they're not waiting.
func get_respawn_left(hero: Hero) -> float:
	var record: Record = _records.get(hero)
	return maxf(record.respawn_left, 0.0) if record != null else 0.0


## Scale a team's respawn times (1 = normal). Applies to deaths from now on.
func set_respawn_multiplier(team: StringName, multiplier: float) -> void:
	_respawn_mult[team] = multiplier


func _tick_respawns(delta: float) -> void:
	if state == State.ENDED:
		return
	for hero in _records.keys():
		var record: Record = _records[hero]
		if record.respawn_left < 0.0:
			continue
		record.respawn_left -= delta
		if record.respawn_left <= 0.0:
			record.respawn_left = -1.0
			respawn_now(hero)


func respawn_now(hero: Hero) -> void:
	if not is_instance_valid(hero) or not hero.health_component.is_dead():
		return
	var record: Record = _records.get(hero)
	if record != null:
		record.respawn_left = -1.0
	hero.respawn(get_spawn_point(hero.team))
	hero_respawned.emit(hero)


## A spawn marker for `team` (random among the map's spawn_<team> points),
## or the map centre if the map has none.
func get_spawn_point(team: StringName) -> Vector2:
	var map := get_tree().get_first_node_in_group(&"game_map") as GameMap
	if map != null:
		var points := map.get_spawn_points(team)
		if not points.is_empty():
			return points.pick_random().global_position
	return Vector2.ZERO


# The hero behind a damage source: the actor itself, or the actor that owns
# the node (a projectile or zone parented to it).
func _hero_of(source: Node) -> Hero:
	var node := source
	while node != null and is_instance_valid(node):
		if node is Hero:
			return node
		node = node.get_parent()
	return null
