extends Resource
class_name MatchConfig

# One match's setup, filled in by the menus and handed to the match scene by
# GameState. The defaults live in resources/match/default_match_config.tres;
# GameState works on a copy.
#
#   mode, team_size, bot_fill, bot_difficulty, map    Match setup screen
#   picks                                             Hero select screen

enum Mode { PRACTICE_VS_BOTS, LOBBY }

@export var mode: Mode = Mode.PRACTICE_VS_BOTS
## Heroes per team (6 = 6v6).
@export_range(1, 6) var team_size: int = 6
## Fill empty slots with bots.
@export var bot_fill: bool = true
## 0 easy, 1 normal, 2 hard (BotDraft.SKILL_PATHS).
@export_range(0, 2) var bot_difficulty: int = 1
## The maps you can choose, by display name and world scene. Same order.
@export var map_names: PackedStringArray = PackedStringArray(["Dream Basin"])
@export var map_scenes: PackedStringArray = PackedStringArray(["res://scenes/dream_basin_world.tscn"])
@export var map_index: int = 0
## Practice (the training grounds, no match) world scene.
@export var practice_scene: String = "res://scenes/training_grounds_world.tscn"

@export_group("Hero select")
## Seconds to lock in before the hovered (or a random) hero is locked for you.
@export var hero_select_time: float = 30.0
## Bots lock in one at a time, this far apart.
@export var bot_pick_interval: float = 0.6
## Pause after everyone has locked in, before the match loads.
@export var start_delay: float = 2.0

## Team the local player is on (Dawn).
var player_team: StringName = &"a"
## Team -> Array[StringName] of hero_ids, one per filled slot. The player's
## hero is the first entry of player_team's list.
var picks: Dictionary = {}
## Practice (training grounds) instead of a match.
var practice: bool = false


func get_map_scene() -> String:
	return map_scenes[clampi(map_index, 0, map_scenes.size() - 1)] if not map_scenes.is_empty() else ""


func get_player_hero_id() -> StringName:
	var mine: Array = picks.get(player_team, [])
	return mine[0] if not mine.is_empty() else &""
