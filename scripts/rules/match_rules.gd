@tool
extends Resource
class_name MatchRules

# Every number the match objective ("Wake the Dreamer") uses: economy,
# leveling, respawns, and later Motes, Dreamers and the endgame.
#
# One shared instance (resources/rules/match_rules.tres), reached like
# GameRules: MatchRules.current(), or MatchRules.override() for a test or a
# playtest mode. Each MatchManager plays on a private copy, which the
# F1 > Match tab edits live.
#
# Groups for later phases (Motes, Spawning, Dreamers, Wake, Buffs, Late
# match) get their fields in the phase that uses them.

const DEFAULT_PATH := "res://resources/rules/match_rules.tres"

@export_group("Match")
## Countdown before the match starts. Heroes can move, nobody earns anything.
@export var warmup_time: float = 10.0
## Seconds a dead hero waits before respawning: base + per_level x level.
@export var respawn_base: float = 5.0
@export var respawn_per_level: float = 0.8

@export_group("Economy")
## Paid to every hero on a team (alive or dead) while the match is PLAYING.
@export var passive_gold_per_second: float = 2.0
@export var passive_xp_per_second: float = 4.0
## Passive income is paid in chunks this many seconds apart.
@export var passive_tick_interval: float = 1.0
## Paid to the hero who lands the killing blow on an enemy hero.
@export var kill_gold: float = 150.0
@export var kill_xp: float = 200.0
## Paid to each other enemy hero who damaged the victim recently.
@export var assist_gold: float = 60.0
@export var assist_xp: float = 100.0
## How recent that damage must be, in seconds.
@export var assist_window: float = 10.0

@export_group("Leveling")
## XP needed to go from level L to L+1 = base + growth x (L - 1).
## With 300 / 100, level 10 takes 6300 XP in total.
@export var xp_level_base: float = 300.0
@export var xp_level_growth: float = 100.0

@export_group("Cues")
## Match-wide looks and sounds (level_up ...). A hero whose own profile has
## the same cue name plays its own instead.
@export var cue_visuals: VisualProfile
@export var cue_audio: AudioProfile

static var _current: MatchRules


static func current() -> MatchRules:
	if _current == null:
		if ResourceLoader.exists(DEFAULT_PATH):
			_current = load(DEFAULT_PATH)
		else:
			_current = MatchRules.new()
	return _current


# Swap the active rules (tests, alternative playtest modes). null restores
# the default file on the next current().
static func override(rules: MatchRules) -> void:
	_current = rules


func xp_to_next_level(level: int) -> float:
	return xp_level_base + xp_level_growth * (level - 1)


# Total XP from level 1 to reach `level`.
func total_xp_for_level(level: int) -> float:
	var total := 0.0
	for l in range(1, level):
		total += xp_to_next_level(l)
	return total


func respawn_time(level: int) -> float:
	return respawn_base + respawn_per_level * level
