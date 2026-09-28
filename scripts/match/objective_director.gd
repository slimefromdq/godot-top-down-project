extends Node
class_name ObjectiveDirector

# Runs the map's neutral objectives (a child of MatchManager; it makes one if
# the scene doesn't): every NeutralCamp in the "neutral_camps" group, on the
# match clock, while the match is PLAYING and MatchRules.objectives_enabled.
#
#   schedule  a camp spawns at its data's first_spawn_time, then
#             respawn_time after it's cleared (0 = once: the Nightmare).
#             Announced camps get warning_time of notice first.
#   level     monsters spawn at the average hero level (+ level_bonus).
#   rewards   per monster slain by a hero: killer_gold/xp to the killer,
#             team_gold/xp split over their team, ultimate charge, and a
#             burst of Motes only that team can grab for mote_claim_time.
#             When the last monster of a camp falls, its team_status goes on
#             the killer's whole team (heroes dead then get the rest of it
#             when they respawn).
#
# Signals for the announcer and HUD; cues through the match profiles:
# <id>_warning, <id>_spawn, <id>_slain.

signal objective_warning(camp: NeutralCamp, seconds: float)
signal objective_spawned(camp: NeutralCamp)
## The camp's last monster died. `team` is the killer's (&"" = no hero).
signal objective_cleared(camp: NeutralCamp, team: StringName, killer: Hero)
signal monster_slain(monster: NeutralMonster, killer: Hero)

const GROUP := &"objective_director"
const SMALL_MOTE := "res://resources/match/small_mote.tres"

var manager: MatchManager

# Camps that have a schedule (they may join late: a map loaded after us).
var _scheduled: Dictionary = {}    # NeutralCamp -> true
# Hero -> {effect, until (match clock)}: team statuses owed to dead heroes.
var _owed: Dictionary = {}


static func find(tree: SceneTree) -> ObjectiveDirector:
	return tree.get_first_node_in_group(GROUP) as ObjectiveDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	manager = get_parent() as MatchManager
	if manager != null:
		manager.hero_respawned.connect(_on_hero_respawned)
		manager.clock_jumped.connect(func(_from, to): resync_to_clock(to))


func get_rules() -> MatchRules:
	return manager.get_rules() if manager != null else MatchRules.current()


func get_clock() -> float:
	return manager.clock if manager != null else 0.0


func get_camps() -> Array[NeutralCamp]:
	var camps: Array[NeutralCamp] = []
	for node in get_tree().get_nodes_in_group(NeutralCamp.GROUP):
		var camp := node as NeutralCamp
		if camp != null and camp.data != null:
			camps.append(camp)
	return camps


## Put every camp back on its first-spawn schedule (despawning any monsters).
func reset_schedule() -> void:
	_scheduled.clear()
	for camp in get_camps():
		camp.despawn()
		_schedule(camp)


func _schedule(camp: NeutralCamp) -> void:
	camp.state = NeutralCamp.CampState.WAITING
	camp.next_spawn_time = camp.data.first_spawn_time
	_scheduled[camp] = true


func _physics_process(_delta: float) -> void:
	if manager == null or not manager.is_playing() or not get_rules().objectives_enabled:
		return
	var clock := get_clock()
	for camp in get_camps():
		if not _scheduled.has(camp):
			_schedule(camp)
		match camp.state:
			NeutralCamp.CampState.WAITING:
				var data := camp.data
				if data.announce and data.warning_time > 0.0 \
						and clock >= camp.next_spawn_time - data.warning_time and clock < camp.next_spawn_time:
					_warn(camp)
				elif clock >= camp.next_spawn_time:
					spawn_camp(camp)
			NeutralCamp.CampState.WARNING:
				if clock >= camp.next_spawn_time:
					spawn_camp(camp)


func _warn(camp: NeutralCamp) -> void:
	camp.state = NeutralCamp.CampState.WARNING
	var seconds := maxf(camp.next_spawn_time - get_clock(), 0.0)
	objective_warning.emit(camp, seconds)
	MatchManager.play_world_cue(camp, StringName("%s_warning" % camp.data.id),
		{"position": camp.global_position, "radius": camp.data.size, "duration": seconds})
	get_tree().call_group(&"minimaps", &"add_ping", camp.global_position, &"", &"dream_mote")


## Spawn a camp now (the schedule, or debug), at the heroes' average level.
func spawn_camp(camp: NeutralCamp) -> void:
	if camp.is_alive():
		return
	var level := camp.data.get_level(get_average_level())
	for monster in camp.spawn(level):
		monster.slain.connect(_on_monster_slain.bind(monster, camp))
	objective_spawned.emit(camp)
	MatchManager.play_world_cue(camp, StringName("%s_spawn" % camp.data.id),
		{"position": camp.global_position, "radius": camp.data.size})


func get_average_level() -> float:
	if manager == null:
		return 1.0
	var heroes := manager.get_roster()
	if heroes.is_empty():
		return 1.0
	var total := 0.0
	for hero in heroes:
		total += hero.get_level()
	return total / heroes.size()


func _on_monster_slain(killer: Hero, monster: NeutralMonster, camp: NeutralCamp) -> void:
	var data := monster.data
	if killer != null and manager != null and manager.has_hero(killer):
		_reward(monster, killer)
	else:
		killer = null
	monster_slain.emit(monster, killer)
	if not camp.get_living_monsters().is_empty():
		return
	var team := killer.team if killer != null else &""
	if killer != null and data.team_status != null:
		apply_team_status(team, data.team_status, data.team_status_duration)
	camp.on_cleared(data.respawn_time > 0.0)
	camp.next_spawn_time = get_clock() + data.respawn_time if data.respawn_time > 0.0 else INF
	objective_cleared.emit(camp, team, killer)
	MatchManager.play_world_cue(camp, StringName("%s_slain" % data.id), {"position": monster.global_position})


func _reward(monster: NeutralMonster, killer: Hero) -> void:
	var data := monster.data
	manager.grant_actor(killer, data.killer_gold, data.killer_xp, MatchManager.REASON_OBJECTIVE)
	manager.grant_team(killer.team, data.team_gold, data.team_xp, MatchManager.REASON_OBJECTIVE)
	manager.add_ultimate_charge(killer, data.killer_ult_charge)
	if data.team_ult_charge > 0.0:
		for hero in manager.get_roster(killer.team):
			if not hero.health_component.is_dead():
				manager.add_ultimate_charge(hero, data.team_ult_charge)
	burst_motes(monster.global_position, data, killer.team)


## Motes flying out of a slain neutral, claimed by `team` for a while.
func burst_motes(at: Vector2, data: NeutralData, team: StringName) -> Array[Mote]:
	var motes: Array[Mote] = []
	if data.mote_count <= 0:
		return motes
	var mote_data: MoteData = data.mote_data if data.mote_data != null else load(SMALL_MOTE)
	var mult := 1.0
	var director := MoteDirector.find(get_tree())
	if director != null and get_rules().objective_motes_use_late_mult:
		mult = director.get_value_multiplier()
	var value := roundi(data.mote_value * mult)
	var start := randf() * TAU
	for i in data.mote_count:
		var dir := Vector2.from_angle(start + TAU * i / data.mote_count)
		var distance := data.mote_burst_radius * (0.6 + 0.4 * ((i * 7) % 5) / 4.0)
		var mote := Mote.spawn(self, mote_data, at + dir * distance, value, true, at)
		mote.claim(team, data.mote_claim_time)
		motes.append(mote)
	return motes


## Put `effect` on every hero of `team` (dead ones get the rest of it when
## they respawn). duration <= 0 uses the status's own.
func apply_team_status(team: StringName, effect: StatusEffect, duration: float = 0.0) -> void:
	if manager == null or effect == null:
		return
	var seconds := duration if duration > 0.0 else effect.duration
	for hero in manager.get_roster(team):
		if hero.health_component.is_dead():
			_owed[hero] = {"effect": effect, "until": get_clock() + seconds}
		else:
			hero.status_component.apply(effect, hero, Vector2.ZERO, 1.0, seconds)


func _on_hero_respawned(hero: Hero) -> void:
	var owed: Dictionary = _owed.get(hero, {})
	_owed.erase(hero)
	if owed.is_empty():
		return
	var left: float = owed.until - get_clock()
	if left > 0.0:
		hero.status_component.apply(owed.effect, hero, Vector2.ZERO, 1.0, left)


## Debug: spawn every camp that isn't up (announced ones too, unless
## `jungle_only`). A camp that's gone for good comes back as well.
func force_spawn_all(jungle_only: bool = false) -> void:
	for camp in get_camps():
		if jungle_only and camp.data.announce:
			continue
		if not _scheduled.has(camp):
			_schedule(camp)
		if not camp.is_alive():
			spawn_camp(camp)


## Debug: spawn the announced camps (the Nightmare) now.
func force_spawn_announced() -> void:
	for camp in get_camps():
		if camp.data.announce and not camp.is_alive():
			if not _scheduled.has(camp):
				_schedule(camp)
			spawn_camp(camp)


## Debug: announced camps start their warning now (spawning warning_time
## later), so the whole announce-and-spawn sequence can be watched.
func force_warning() -> void:
	for camp in get_camps():
		if camp.data.announce and not camp.is_alive():
			_scheduled[camp] = true
			camp.state = NeutralCamp.CampState.WAITING
			camp.next_spawn_time = get_clock() + camp.data.warning_time
			_warn(camp)


## Debug: remove every monster. Camps wait out their respawn_time again; a
## once-only camp (the Nightmare) whose time has passed stays gone ("Nightmare
## now" still brings it back), one still ahead keeps its first-spawn time.
## After a clock jump: clear every camp, then put each back as the match
## would have it at `clock`. A camp whose first spawn is still ahead waits for
## it; one that's already due (a jungle camp, or the Nightmare past 10:00)
## spawns at once, fresh, so you can see that moment's map.
func resync_to_clock(clock: float) -> void:
	for camp in get_camps():
		camp.despawn()
		camp.state = NeutralCamp.CampState.WAITING
		camp.next_spawn_time = maxf(camp.data.first_spawn_time, clock)
		_scheduled[camp] = true


func despawn_all() -> void:
	var clock := get_clock()
	for camp in get_camps():
		camp.despawn()
		if camp.data.respawn_time > 0.0:
			camp.state = NeutralCamp.CampState.WAITING
			camp.next_spawn_time = maxf(camp.data.first_spawn_time, clock + camp.data.respawn_time)
		elif camp.data.first_spawn_time > clock:
			camp.state = NeutralCamp.CampState.WAITING
			camp.next_spawn_time = camp.data.first_spawn_time
		else:
			camp.state = NeutralCamp.CampState.GONE
			camp.next_spawn_time = INF
		_scheduled[camp] = true
