extends Node
class_name MapEvents

# The root of the three map events (a child of the MatchManager; it makes one
# if the scene doesn't): the Black Market, the Mote Island and the Wanderer,
# plus the MoteLedger that counts where Motes come from. All state lives in
# the directors below; the HUD, the cues and the drawn nodes only read it and
# call their request_* / purchase methods, so a server can own the directors
# and clients mirror them later.
#
#   BlackMarketDirector   the stall's schedule and the shop rules
#   IslandDirector        the hidden portal, the Island and its cache
#   WandererDirector      the neutral mote-runner
#   MoteLedger            Motes made / banked / delivered / spent, per source
#
# Every number is in MapEventRules (MatchRules.map_events). Randomness comes
# from MatchManager.match_seed. See docs/MAP_EVENTS.md.

const GROUP := &"map_events"
## Nodes with get_prompt(hero), can_interact(hero) and get_interact_radius():
## the HUD lets the local player press the interact key at the nearest one.
const INTERACTABLES := &"interactables"
const DEFAULT_RULES := "res://resources/rules/map_events.tres"

var manager: MatchManager
var ledger: MoteLedger
var market: BlackMarketDirector
var island: IslandDirector
var wanderer: WandererDirector

static var _fallback: MapEventRules


static func find(tree: SceneTree) -> MapEvents:
	return tree.get_first_node_in_group(GROUP) as MapEvents if tree != null else null


## The rules for whatever this scene is (the match's private copy).
static func rules_for(tree: SceneTree) -> MapEventRules:
	var manager := MatchManager.find(tree)
	var rules := manager.get_rules().map_events if manager != null else MatchRules.current().map_events
	if rules != null:
		return rules
	if _fallback == null:
		_fallback = load(DEFAULT_RULES)
	return _fallback


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	manager = get_parent() as MatchManager
	ledger = _child(MoteLedger, "MoteLedger")
	market = _child(BlackMarketDirector, "BlackMarketDirector")
	island = _child(IslandDirector, "IslandDirector")
	wanderer = _child(WandererDirector, "WandererDirector")
	if manager != null:
		manager.match_ended.connect(_on_match_ended)


func get_rules() -> MapEventRules:
	return MapEvents.rules_for(get_tree())


func get_clock() -> float:
	return manager.clock if manager != null else 0.0


func _child(script: GDScript, node_name: String) -> Node:
	var existing := get_node_or_null(node_name)
	if existing != null:
		return existing
	var made: Node = script.new()
	made.name = node_name
	add_child(made)
	return made


func _on_match_ended(_winner: StringName) -> void:
	if ledger != null and get_rules().log_ledger_on_match_end:
		print("--- Mote sources this match ---\n", ledger.report())


# --- Debug ---------------------------------------------------------------------------

## Open the Black Market now (at a random edge unless `side` is &"left" or &"right").
func force_spawn_market(side: StringName = &"") -> void:
	if manager != null:
		manager.start_playing()
	market.force_open(side)


func force_close_market() -> void:
	market.force_close()


## Move the Island portal to a new hidden spot now (a player on the Island is
## sent home first).
func force_relocate_island() -> void:
	if manager != null:
		manager.start_playing()
	island.force_relocate()


## A Wanderer now (replacing any that is up).
func force_spawn_wanderer() -> void:
	if manager != null:
		manager.start_playing()
	wanderer.force_spawn()
