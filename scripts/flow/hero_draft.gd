extends RefCounted
class_name HeroDraft

# The hero select's rules, without any UI (the screen draws it, the tests
# drive it). Every team has config.team_size slots; the player is slot 0 of
# their team. Bot slots lock in one at a time (config.bot_pick_interval
# apart) through BotDraft.pick, so teams come out with a sensible role mix.
# No hero twice on one team: an ally bot avoids what you're hovering, and if
# you lock a hero a bot already has, that bot picks again. When the timer
# (config.hero_select_time) runs out you're locked into what you're hovering,
# or a random free hero. Once everyone is locked, is_done() after
# config.start_delay.
#
# Practice has one slot: yours.

signal changed

class Slot:
	var team: StringName
	var index: int
	var is_player := false
	## false = an empty slot (bot fill off).
	var is_bot := false
	var hero_id: StringName = &""
	var locked := false

var config: MatchConfig
var definitions: Array[HeroDefinition] = []
## Team -> Array[Slot].
var teams: Dictionary = {}
var hovered: StringName = &""
var time_left: float = 0.0
var start_left: float = -1.0

var _bot_queue: Array[Slot] = []
var _bot_timer: float = 0.0


func _init(match_config: MatchConfig, heroes: Array[HeroDefinition]) -> void:
	config = match_config
	definitions = heroes
	time_left = config.hero_select_time
	_bot_timer = config.bot_pick_interval
	var order: Array[StringName] = [config.player_team]
	if not config.practice:
		order.append(MatchManager.other_team(config.player_team))
	for team in order:
		var slots: Array = []
		var count := 1 if config.practice else maxi(config.team_size, 1)
		for i in count:
			var slot := Slot.new()
			slot.team = team
			slot.index = i
			slot.is_player = team == config.player_team and i == 0
			slot.is_bot = not slot.is_player and config.bot_fill
			slots.append(slot)
		teams[team] = slots
	# Bots take turns across the teams: enemy 1, ally 1, enemy 2 ...
	var turn := order.duplicate()
	turn.reverse()
	for i in (1 if config.practice else config.team_size):
		for team in turn:
			var slot: Slot = teams[team][i]
			if slot.is_bot:
				_bot_queue.append(slot)
	if not definitions.is_empty():
		hovered = definitions[0].hero_id
		get_player_slot().hero_id = hovered


func get_player_slot() -> Slot:
	return teams[config.player_team][0]


func is_player_locked() -> bool:
	return get_player_slot().locked


func hover(hero_id: StringName) -> void:
	if is_player_locked() or hero_id == hovered:
		return
	hovered = hero_id
	get_player_slot().hero_id = hero_id
	changed.emit()


## Lock the player into the hovered hero (or `hero_id`).
func lock_in(hero_id: StringName = &"") -> void:
	if is_player_locked():
		return
	if hero_id != &"":
		hovered = hero_id
	var slot := get_player_slot()
	slot.hero_id = hovered
	slot.locked = true
	# An ally bot that already has it picks again.
	for other: Slot in teams[slot.team]:
		if other != slot and other.locked and other.hero_id == hovered:
			other.hero_id = _bot_choice(other)
	changed.emit()


## An ally bot has locked this hero (you can still take it; they re-pick).
func is_taken_by_ally(hero_id: StringName) -> bool:
	for slot: Slot in teams[config.player_team]:
		if not slot.is_player and slot.locked and slot.hero_id == hero_id:
			return true
	return false


func all_locked() -> bool:
	for team in teams:
		for slot: Slot in teams[team]:
			if (slot.is_player or slot.is_bot) and not slot.locked:
				return false
	return true


func is_done() -> bool:
	return start_left == 0.0


func tick(delta: float) -> void:
	if is_done():
		return
	if start_left > 0.0:
		start_left = maxf(start_left - delta, 0.0)
		return
	time_left = maxf(time_left - delta, 0.0)
	if not _bot_queue.is_empty():
		_bot_timer -= delta
		if _bot_timer <= 0.0:
			_bot_timer = config.bot_pick_interval
			var slot: Slot = _bot_queue.pop_front()
			slot.hero_id = _bot_choice(slot)
			slot.locked = true
			changed.emit()
	if time_left <= 0.0 and not is_player_locked():
		lock_in(hovered if hovered != &"" else _random_free())
		# Bots still waiting lock in at once.
		while not _bot_queue.is_empty():
			var slot: Slot = _bot_queue.pop_front()
			slot.hero_id = _bot_choice(slot)
			slot.locked = true
		changed.emit()
	if start_left < 0.0 and all_locked():
		start_left = maxf(config.start_delay, 0.0)
		changed.emit()


## Team -> Array[StringName] hero_ids for MatchConfig.picks (empty slots left out).
func to_picks() -> Dictionary:
	var picks := {}
	for team in teams:
		var ids: Array[StringName] = []
		for slot: Slot in teams[team]:
			if slot.locked and slot.hero_id != &"":
				ids.append(slot.hero_id)
		picks[team] = ids
	return picks


func find(hero_id: StringName) -> HeroDefinition:
	for definition in definitions:
		if definition.hero_id == hero_id:
			return definition
	return null


func _bot_choice(slot: Slot) -> StringName:
	var have: Array = []
	var used: Array = []
	for other: Slot in teams[slot.team]:
		if other == slot:
			continue
		if other.locked or (other.is_player and other.hero_id != &""):
			have.append(find(other.hero_id))
			used.append(other.hero_id)
	# Don't take what the player is looking at.
	if slot.team == config.player_team and hovered != &"":
		used.append(hovered)
	# The enemy picks from the other end of the list, so mirrors differ.
	var pool := definitions.duplicate()
	if slot.team != config.player_team:
		pool.reverse()
	var choice := BotDraft.pick(pool, have, used)
	if choice == null and not definitions.is_empty():
		choice = definitions[slot.index % definitions.size()]
	return choice.hero_id if choice != null else &""


func _random_free() -> StringName:
	var free: Array[StringName] = []
	for definition in definitions:
		if not is_taken_by_ally(definition.hero_id):
			free.append(definition.hero_id)
	return free.pick_random() if not free.is_empty() else &""
