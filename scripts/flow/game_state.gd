extends Node

# Autoload "GameState": the one route through the menus and into a match.
#
#   main menu -> match setup -> hero select -> match -> end screen -> main menu
#   main menu -> (Practice) hero select -> training grounds
#
# `config` (a MatchConfig) is filled in along the way: the setup screen sets
# mode, team size, bots and map, hero select sets `picks`. start_match()
# builds the world scene with the player's hero already set (Hero applies its
# definition in _enter_tree, so it has to be set before the scene enters the
# tree), then spawns the bots that were picked.
#
# Scenes run on their own too (F5 on a world, the headless tests): with no
# launch in progress nothing here touches them.
#
# Stats hook: when a launched match ends, finish_match() builds a result
# (winner, and a row per hero with K/D/A and Motes banked/delivered), keeps it
# in `last_result` and emits match_finished(result). Progression and
# post-match stats can listen there later.

signal match_finished(result: Dictionary)

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const MATCH_SETUP := "res://scenes/ui/match_setup.tscn"
const HERO_SELECT := "res://scenes/ui/hero_select.tscn"
const DEFAULT_CONFIG := "res://resources/match/default_match_config.tres"

var config: MatchConfig
## True from start_match() / start_practice() until the player leaves.
var in_launched_game := false
var last_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UserSettings.load_and_apply()
	new_config()


func new_config() -> MatchConfig:
	config = (load(DEFAULT_CONFIG) as MatchConfig).duplicate()
	return config


# --- Menus ---------------------------------------------------------------------

func goto_main_menu() -> void:
	in_launched_game = false
	_change_to(MAIN_MENU)


func goto_match_setup() -> void:
	config.practice = false
	_change_to(MATCH_SETUP)


func goto_practice_select() -> void:
	config.practice = true
	_change_to(HERO_SELECT)


func goto_hero_select() -> void:
	_change_to(HERO_SELECT)


# --- Launching -------------------------------------------------------------------

## After hero select: the practice grounds or the match, with config.picks.
func launch() -> void:
	var scene_path := config.practice_scene if config.practice else config.get_map_scene()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("GameState: can't load %s" % scene_path)
		return
	var world := packed.instantiate()
	var player := world.get_node_or_null(^"Player") as Hero
	var definition := BotDraft.find_definition(config.get_player_hero_id())
	if player != null and definition != null:
		player.definition = definition
		player.team = config.player_team
	in_launched_game = true
	last_result = {}
	_reset_time()
	get_tree().change_scene_to_node(world)
	if config.practice:
		return
	# The new scene is in the tree (and its MatchManager registered) after this.
	await get_tree().scene_changed
	_spawn_bots()


func _spawn_bots() -> void:
	var skill := BotDraft.skill_for(config.bot_difficulty)
	var added := 0
	for team in config.picks:
		var ids: Array = config.picks[team]
		for i in ids.size():
			if team == config.player_team and i == 0:
				continue    # the player
			var definition := BotDraft.find_definition(ids[i])
			if definition == null:
				continue
			added += 1
			BotDraft.spawn_bot(get_tree(), definition, team, skill, added, i)


## Pause menu / end screen: back to the main menu.
func leave_match() -> void:
	_reset_time()
	goto_main_menu()


# --- Results ----------------------------------------------------------------------

## The world calls this when a match ends. Returns the result it stored.
func finish_match(manager: MatchManager, winner_team: StringName) -> Dictionary:
	var player := get_tree().get_first_node_in_group(&"player") as Hero
	var rows: Array = []
	for hero in manager.get_roster():
		var record := manager.get_record(hero)
		if record == null:
			continue
		rows.append({
			"hero_id": hero.definition.hero_id if hero.definition != null else &"",
			"name": hero.definition.display_name if hero.definition != null else str(hero.name),
			"team": hero.team,
			"is_player": hero == player,
			"kills": record.kills,
			"deaths": record.deaths,
			"assists": record.assists,
			"motes_banked": record.motes_banked,
			"motes_delivered": record.motes_delivered,
			"gold": record.gold,
		})
	last_result = {
		"winner": winner_team,
		"player_team": player.team if player != null else config.player_team,
		"won": player != null and player.team == winner_team,
		"duration": manager.clock,
		"heroes": rows,
	}
	match_finished.emit(last_result)
	return last_result


# --- Helpers -------------------------------------------------------------------------

func _change_to(path: String) -> void:
	_reset_time()
	get_tree().change_scene_to_file(path)


func _reset_time() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
