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
# Groups for later phases (Dreamers, Wake, Buffs) get their fields in the
# phase that uses them.

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

@export_group("Motes")
## Most Motes one hero can carry (a Dream Mote takes one slot).
@export var max_carried: int = 5
## Enemy minimap reveal steps by carried VALUE: at reveal_values[i] or more,
## the carrier pings the enemy minimap every reveal_ping_intervals[i]
## seconds (0 = shown all the time). Ascending.
@export var reveal_values: PackedInt32Array = PackedInt32Array([4, 7, 10])
@export var reveal_ping_intervals: PackedFloat32Array = PackedFloat32Array([6.0, 3.0, 0.0])
## Enemy displacements (pushes, pulls, carries, abductions) needed to jostle
## one Mote loose. Pushes shorter than jostle_min_distance don't count.
@export var jostle_displacements_required: int = 1
@export var jostle_min_distance: float = 100.0
## For jostle_displacements_required > 1: displacements this far apart
## start the count again.
@export var jostle_window: float = 4.0
## Heavy pockets: seconds of extra air time per carried Mote on jump pads
## and trampolines.
@export var heavy_pockets_air_time: float = 0.1
## Death burst: Motes scatter this far from the body.
@export var burst_radius: float = 170.0
## A jostled Mote lands this far from the carrier.
@export var jostle_drop_distance: float = 120.0

@export_group("Spawning")
## Trickle: one small Mote every interval at a free mote_spawn point, while
## fewer than max_loose_motes lie on the map.
@export var trickle_interval: float = 4.0
@export var max_loose_motes: int = 16
## A trickle point is "seen" if a hero is within this range with line of
## sight. Unseen points are preferred.
@export var spawn_sight_range: float = 1300.0
## Dreaming zones: first one at zone_first_time, then every zone_interval
## (counted from the previous zone's start). Announced zone_warning early.
@export var zone_first_time: float = 90.0
@export var zone_interval: float = 120.0
@export var zone_warning: float = 10.0
@export var zone_duration: float = 40.0
## While dreaming, each half spawns a Mote this often, up to
## zone_max_per_half loose Motes in that half.
@export var zone_spawn_interval: float = 1.5
@export var zone_max_per_half: int = 6
## Dream Mote: first at dream_mote_first_time, then dream_mote_interval after
## the previous one is picked up for good (banked, or faded).
@export var dream_mote_first_time: float = 240.0
@export var dream_mote_interval: float = 180.0
@export var dream_mote_warning: float = 15.0

@export_group("Late match")
## After late_match_time, new Motes spawn worth late_match_value_mult times
## as much. This keeps matches from running forever.
@export var late_match_time: float = 900.0
@export var late_match_value_mult: float = 2.0

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


## Seconds between enemy minimap pings for a carried value: -1 = not
## revealed, 0 = shown all the time.
func reveal_interval_for(value: int) -> float:
	var interval := -1.0
	for i in mini(reveal_values.size(), reveal_ping_intervals.size()):
		if value >= reveal_values[i]:
			interval = reveal_ping_intervals[i]
	return interval


func respawn_time(level: int) -> float:
	return respawn_base + respawn_per_level * level
