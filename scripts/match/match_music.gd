extends Node
class_name MatchMusic

# The match's adaptive music (a child of MatchManager; it makes one). Plays
# a MusicLayerSet through AudioManager and picks its tier from the match:
#
#   CALM      the base stems
#   TENSE     either wake meter at tense_wake_ratio or more, or a Dream Mote
#             on the map (loose or carried)
#   STIRRING  any Dreamer stirring: every stem, plus the pulse layer
#   VICTORY   the match ended: the stems fade and the sting plays
#
# Rising is immediate; falling goes one tier at a time and at most once per
# layer_set.min_seconds_per_drop, so it never flickers. With no stems
# assigned it all runs silently. Cosmetic only.

enum Tier { CALM, TENSE, STIRRING }

const DEFAULT_SET := "res://resources/match/match_music.tres"

@export var layer_set: MusicLayerSet
## A wake meter at this share or more makes the music TENSE.
@export_range(0.0, 1.0, 0.05) var tense_wake_ratio: float = 0.5

var manager: MatchManager
var tier: Tier = Tier.CALM
var _since_change: float = 0.0
var _ended := false


func _ready() -> void:
	manager = get_parent() as MatchManager
	if layer_set == null and ResourceLoader.exists(DEFAULT_SET):
		layer_set = load(DEFAULT_SET)
	if manager != null:
		manager.match_ended.connect(_on_match_ended)
	AudioManager.play_layers(layer_set, Tier.CALM)


func _exit_tree() -> void:
	if AudioManager.get_layer_set() == layer_set:
		AudioManager.stop_layers(0.5)


## The tier the match is asking for right now.
func wanted_tier() -> Tier:
	if manager == null:
		return Tier.CALM
	var tense := false
	for team in MatchManager.TEAMS:
		var dreamer := manager.get_dreamer(team)
		if dreamer == null:
			continue
		if dreamer.is_stirring():
			return Tier.STIRRING
		tense = tense or dreamer.get_wake_ratio() >= tense_wake_ratio
	var director := manager.get_node_or_null(^"MoteDirector") as MoteDirector
	if director != null and director.dream_mote_exists():
		tense = true
	return Tier.TENSE if tense else Tier.CALM


func _process(delta: float) -> void:
	if _ended:
		return
	_since_change += delta
	step(wanted_tier())


## Move toward `want`: up at once, down one tier after the hold. Returns the
## tier now playing.
func step(want: Tier) -> Tier:
	var hold := layer_set.min_seconds_per_drop if layer_set != null else 8.0
	if want > tier:
		tier = want
		_since_change = 0.0
	elif want < tier and _since_change >= hold:
		tier = (tier - 1) as Tier
		_since_change = 0.0
	AudioManager.set_music_tier(tier)
	return tier


func _on_match_ended(_winner: StringName) -> void:
	_ended = true
	AudioManager.stop_layers(layer_set.crossfade_time if layer_set != null else 1.0)
	if layer_set != null:
		AudioManager.play_sting(layer_set.victory_sting, layer_set.sting_volume_db)
