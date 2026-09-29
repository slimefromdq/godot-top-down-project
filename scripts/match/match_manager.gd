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
## Relayed from the Dreamers (see Dreamer), with the Dreamer's team.
signal wake_changed(team: StringName, value: float)
signal stir_started(team: StringName)
signal lullaby_changed(team: StringName, pct: float)
signal settled(team: StringName, how: StringName)
signal woke(team: StringName)
signal wake_milestone(team: StringName, mark: float)
## A hero's ultimate charge changed (UltimateCharge, 0..1).
signal ultimate_charge_changed(actor: Hero, ratio: float)
## Debug: the clock jumped (jump_clock). Schedules re-sync to the new time.
signal clock_jumped(from: float, to: float)

enum State { WARMUP, PLAYING, ENDED }

const GROUP := &"match_manager"
## Nodes in this group get on_clock_jumped(from, to) after jump_clock.
const CLOCK_LISTENERS := &"clock_listeners"
const TEAMS: Array[StringName] = [&"a", &"b"]
const TEAM_NAMES := {&"a": "Dawn", &"b": "Dusk"}
## Dawn mint, Dusk coral (light enough for text on a dark HUD).
const TEAM_COLORS := {&"a": Color("7fe0b8"), &"b": Color("ff9e85")}

const REASON_PASSIVE := &"passive"
const REASON_KILL := &"kill"
const REASON_ASSIST := &"assist"
const REASON_DEBUG := &"debug"
## Buying (negative gold) and selling items.
const REASON_SHOP := &"shop"
## A slain neutral camp or the Nightmare.
const REASON_OBJECTIVE := &"objective"
## Gold paid at the Black Market.
const REASON_MARKET := &"black_market"

## Empty = a private copy of MatchRules.current(), so the debug panel's live
## edits never touch the .tres.
@export var rules: MatchRules
## Start the warmup countdown on _ready. Tests turn it off and call
## start_warmup() / start_playing() themselves.
@export var auto_start: bool = true
## The match's seed. Everything random that must agree between machines (the
## map events' schedule and places) derives from it through make_rng() /
## seeded_int(). 0 = a fresh random seed at _ready. Set it (before _ready, or
## with set_match_seed) to replay a match's events.
@export var match_seed: int = 0

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
	## Mote value this hero put into their own Dreamer / the enemy's.
	var motes_banked: int = 0
	var motes_delivered: int = 0
	## Damage dealt to and taken from enemy heroes, and health given to
	## allies (not self): the MVP screen's numbers.
	var damage_dealt: float = 0.0
	var damage_taken: float = 0.0
	var healing_done: float = 0.0
	## Kills since the last death, and the best run of the match.
	var streak: int = 0
	var best_streak: int = 0
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
var _dreamers: Dictionary = {}    # team -> Dreamer
var _sanctuaries: Dictionary = {}    # team -> SpawnSanctuary
var _sanctuary_map: GameMap


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
		# The map events' numbers are a private copy too (F1 edits never touch the .tres).
		if rules.map_events != null:
			rules.map_events = rules.map_events.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if get_node_or_null(^"MoteDirector") == null:
		var director := MoteDirector.new()
		director.name = "MoteDirector"
		add_child(director)
	if get_node_or_null(^"ObjectiveDirector") == null:
		var objectives := ObjectiveDirector.new()
		objectives.name = "ObjectiveDirector"
		add_child(objectives)
	if match_seed == 0:
		match_seed = int(Time.get_ticks_usec() ^ (randi() << 8)) & 0x7fffffff
		if match_seed == 0:
			match_seed = 1
	if get_node_or_null(^"MapEvents") == null:
		var events := MapEvents.new()
		events.name = "MapEvents"
		add_child(events)
	if get_node_or_null(^"MatchMusic") == null:
		var music := MatchMusic.new()
		music.name = "MatchMusic"
		add_child(music)
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(&"heroes"):
		_try_register(node)
	for node in get_tree().get_nodes_in_group(Dreamer.GROUP):
		register_dreamer(node)
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


## A generator for one purpose ("market", "island" ...), seeded from the match
## seed: two machines with the same match_seed draw the same numbers.
func make_rng(purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/%s" % [match_seed, purpose])
	return rng


## The `index`-th number of the stream (purpose, index): a pure function of the
## match seed, so a schedule can be read at any point (after a clock jump)
## without replaying the draws before it.
func seeded_int(purpose: String, index: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/%s/%d" % [match_seed, purpose, index])
	return rng.randi()


func set_match_seed(value: int) -> void:
	match_seed = maxi(value, 1)
	get_tree().call_group(&"seeded_systems", &"on_match_seed_changed")


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


## Debug: set the match clock to `seconds` (forward or back) and start
## playing if we weren't. Everything scheduled on the clock (dreaming zones,
## the Dream Mote, neutral camps, map pieces, the mood) re-syncs through
## clock_jumped as if the match had reached that time normally: what should
## be on the map at that time is there, what shouldn't be yet is gone. Gold,
## XP and levels are left alone.
func jump_clock(seconds: float) -> void:
	var from := clock
	start_playing()
	clock = maxf(0.0, seconds)
	clock_jumped.emit(from, clock)
	# Map-side listeners (pieces, the mood) that don't hold the manager.
	get_tree().call_group(CLOCK_LISTENERS, &"on_clock_jumped", from, clock)


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
	_make_sanctuaries()
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
			if not hero.health_component.is_dead():
				add_ultimate_charge(hero, r.ult_charge_per_second * r.passive_tick_interval)


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
	_attach_ultimate_charge(hero)
	_attach_inventory(hero)
	hero.health_component.damage_taken.connect(_on_hero_damaged.bind(hero))
	hero.health_component.healed.connect(_on_hero_healed.bind(hero))
	hero.health_component.died.connect(_on_hero_died.bind(hero))
	hero.tree_exiting.connect(_unregister.bind(hero), CONNECT_ONE_SHOT)
	roster_changed.emit()


func _unregister(hero: Hero) -> void:
	var record: Record = _records.get(hero)
	_records.erase(hero)
	var charge := UltimateCharge.find_on(hero)
	if charge != null:
		charge.queue_free()
	var inventory := ItemInventory.find_on(hero)
	if inventory != null:
		inventory.queue_free()
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


## Kills, deaths and assists as (x, y, z); zeros for an unknown hero.
func get_kda(hero: Hero) -> Vector3i:
	var record: Record = _records.get(hero)
	return Vector3i(record.kills, record.deaths, record.assists) if record != null else Vector3i.ZERO


## A team's total kills.
func get_team_kills(team: StringName) -> int:
	var total := 0
	for hero in get_roster(team):
		total += get_kda(hero).x
	return total


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


## Take `amount` gold from a hero (a purchase). False, and nothing taken,
## if they don't have that much.
func spend_gold(hero: Hero, amount: float, reason: StringName = REASON_SHOP) -> bool:
	var record: Record = _records.get(hero)
	if record == null or amount < 0.0 or record.gold + 0.001 < amount:
		return false
	if amount > 0.0:
		record.gold = maxf(record.gold - amount, 0.0)
		gold_changed.emit(hero, -amount, reason)
	return true


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


# A match cue in the world (Motes, zones ...): the match-wide look and sound
# from MatchRules.cue_visuals / cue_audio. context.position says where.
static func play_world_cue(from: Node, cue: StringName, context: Dictionary = {}) -> void:
	if from == null or not from.is_inside_tree():
		return
	var manager := find(from.get_tree())
	var r := manager.get_rules() if manager != null else MatchRules.current()
	var at: Vector2 = context.get("position", (from as Node2D).global_position if from is Node2D else Vector2.ZERO)
	context["position"] = at
	if r.cue_visuals != null and r.cue_visuals.cues.has(cue):
		var definition: VisualCue = r.cue_visuals.cues[cue]
		context.merge({"align": definition.align_to_direction})
		var effect := EffectSpawner.spawn(from, definition.effect_scene, context)
		if effect is Node2D:
			effect.position += definition.offset
			effect.scale *= definition.scale
			effect.modulate *= definition.tint
		_shake_near(from, at, definition.screen_shake)
	if r.cue_audio != null:
		# context.chord: several pitches at once (a deposit's closing chord).
		var pitches: Array = Array(context.get("chord", [context.get("pitch", 1.0)]))
		for pitch in pitches:
			AudioManager.play_sfx(r.cue_audio.cues.get(cue), at, pitch)


# A world cue's screen shake reaches the local camera only when it happened
# on screen (roughly), and ShakeCamera applies the player's shake settings.
static func _shake_near(from: Node, at: Vector2, amount: float) -> void:
	if amount <= 0.0:
		return
	var camera := from.get_viewport().get_camera_2d()
	if camera == null or not camera.has_method(&"add_trauma"):
		return
	if camera.get_screen_center_position().distance_to(at) < 1200.0:
		camera.add_trauma(amount)


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
# Ultimate charge
# ---------------------------------------------------------------------------

func _attach_ultimate_charge(hero: Hero) -> void:
	var r := get_rules()
	if not r.ultimate_charge_enabled or UltimateCharge.find_on(hero) != null:
		return
	var charge := UltimateCharge.new()
	charge.name = "UltimateCharge"
	charge.maximum = r.ult_charge_max
	charge.charge_changed.connect(func(value: float, most: float):
		ultimate_charge_changed.emit(hero, value / most if most > 0.0 else 1.0))
	hero.add_child(charge)


## Add ultimate charge to a hero (only while PLAYING; nothing during the
## warmup or after the end).
func add_ultimate_charge(hero: Hero, amount: float) -> void:
	if state != State.PLAYING or amount <= 0.0 or not _records.has(hero):
		return
	var charge := UltimateCharge.find_on(hero)
	if charge != null:
		charge.add(amount * (hero.definition.ult_charge_rate if hero.definition != null else 1.0))


## 0..1, or -1 when the match doesn't use ultimate charge.
func get_ultimate_ratio(hero: Hero) -> float:
	var charge := UltimateCharge.find_on(hero)
	return charge.get_ratio() if charge != null else -1.0


func _on_hero_healed(amount: float, source: Node, target: Hero) -> void:
	var healer := _hero_of(source)
	if healer == null or healer.team != target.team:
		return
	var r := get_rules()
	if healer != target and _records.has(healer):
		(_records[healer] as Record).healing_done += amount
	var mult := r.ult_charge_self_heal_mult if healer == target else 1.0
	add_ultimate_charge(healer, amount * r.ult_charge_per_heal * mult)


# ---------------------------------------------------------------------------
# Items and shops
# ---------------------------------------------------------------------------

func _attach_inventory(hero: Hero) -> void:
	if ItemInventory.find_on(hero) != null:
		return
	var inventory := ItemInventory.new()
	inventory.name = ItemInventory.NODE_NAME
	inventory.manager = self
	hero.add_child(inventory)


## "" if `hero` may buy and sell right now, else why not: in their own base
## (near their team's Shop, or in its spawn area), or anywhere while dead (MatchRules.shop_while_dead). Warmup counts.
func get_shop_block_reason(hero: Hero) -> String:
	if hero == null or not _records.has(hero):
		return "Not in the match"
	if state == State.ENDED:
		return "Match over"
	var r := get_rules()
	if r.shop_anywhere:
		return ""
	if hero.health_component.is_dead():
		return "" if r.shop_while_dead else "Dead"
	if is_in_base(hero):
		return ""
	return "Return to base to shop"


func can_shop(hero: Hero) -> bool:
	return get_shop_block_reason(hero) == ""


## In the team's base: near one of its Shops, or in its spawn area.
func is_in_base(hero: Hero) -> bool:
	var reach := get_rules().shop_radius
	for shop in Shop.get_all(get_tree(), hero.team):
		if shop.global_position.distance_to(hero.global_position) <= reach:
			return true
	var sanctuary := get_sanctuary(hero.team)
	return sanctuary != null and sanctuary.contains(hero.global_position)


# ---------------------------------------------------------------------------
# Dreamers
# ---------------------------------------------------------------------------

## A Dreamer reports in (Dreamer._ready, or our own _ready for ones placed
## first). Its signals are relayed with its team.
func register_dreamer(dreamer: Dreamer) -> void:
	if _dreamers.get(dreamer.team) == dreamer:
		return
	_dreamers[dreamer.team] = dreamer
	var t := dreamer.team
	dreamer.wake_changed.connect(func(value): wake_changed.emit(t, value))
	dreamer.stir_started.connect(func(): stir_started.emit(t))
	dreamer.lullaby_changed.connect(func(pct): lullaby_changed.emit(t, pct))
	dreamer.settled.connect(func(how): settled.emit(t, how))
	dreamer.woke.connect(func(_attackers): woke.emit(t))
	dreamer.wake_milestone.connect(func(mark): wake_milestone.emit(t, mark))
	dreamer.deposit_finished.connect(_on_deposit_finished)


func _on_deposit_finished(hero: Hero, total: int, delivered: bool) -> void:
	var record: Record = _records.get(hero)
	if record == null:
		return
	if delivered:
		record.motes_delivered += total
	else:
		record.motes_banked += total


func get_dreamer(team: StringName) -> Dreamer:
	var dreamer: Dreamer = _dreamers.get(team)
	return dreamer if is_instance_valid(dreamer) else null


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
		record.damage_taken += info.final_amount
	var dealer: Record = _records.get(attacker)
	if dealer != null:
		dealer.damage_dealt += info.final_amount
	var r := get_rules()
	add_ultimate_charge(attacker, info.final_amount * r.ult_charge_per_damage)
	add_ultimate_charge(victim, (info.final_amount + info.absorbed) * r.ult_charge_per_damage_taken)


func _on_hero_died(victim: Hero) -> void:
	var record: Record = _records.get(victim)
	if record == null:
		return
	record.deaths += 1
	record.streak = 0
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
			var killer_record: Record = _records[killer]
			killer_record.kills += 1
			killer_record.streak += 1
			killer_record.best_streak = maxi(killer_record.best_streak, killer_record.streak)
			grant_actor(killer, r.kill_gold, r.kill_xp, REASON_KILL)
			add_ultimate_charge(killer, r.ult_charge_kill)
		for hero in assisters:
			(_records[hero] as Record).assists += 1
			grant_actor(hero, r.assist_gold, r.assist_xp, REASON_ASSIST)
			add_ultimate_charge(hero, r.ult_charge_assist)
	hero_killed.emit(victim, killer, assisters)
	if state != State.ENDED:
		record.respawn_left = get_respawn_time(victim)
		hero_respawning.emit(victim, record.respawn_left)


func get_respawn_time(hero: Hero) -> float:
	return get_rules().respawn_time(hero.get_level(), clock) * float(_respawn_mult.get(hero.team, 1.0))


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


## The healing spawn area of `team` (null on a map without spawn markers).
func get_sanctuary(team: StringName) -> SpawnSanctuary:
	var sanctuary: SpawnSanctuary = _sanctuaries.get(team)
	return sanctuary if is_instance_valid(sanctuary) else null


# One SpawnSanctuary per team, around the map's spawn markers, made once per
# map (the map may load after us, or be switched: F3).
func _make_sanctuaries() -> void:
	if is_instance_valid(_sanctuary_map):
		return
	var map := get_tree().get_first_node_in_group(&"game_map") as GameMap
	if map == null:
		return
	_sanctuary_map = map
	_sanctuaries.clear()
	for team in TEAMS:
		var points := map.get_spawn_points(team)
		if points.is_empty():
			continue
		var sanctuary := SpawnSanctuary.new()
		sanctuary.name = "SpawnSanctuary_%s" % team
		sanctuary.team = team
		sanctuary.area = SpawnSanctuary.area_around(points, get_rules().spawn_area_margin, map.bounds)
		map.add_child(sanctuary)
		_sanctuaries[team] = sanctuary


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
