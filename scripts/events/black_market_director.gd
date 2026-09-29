extends Node
class_name BlackMarketDirector

# The Black Market's schedule and shop rules.
#
#   schedule  a pure function of the match clock: it first opens at
#             blackmarket_first_spawn_time, stays open blackmarket_open_time,
#             is gone blackmarket_closed_time, then opens again, and so on.
#             The edge it opens on (left or right) and the exact spot are
#             drawn from the match seed and the window's index, so every
#             machine agrees and a clock jump lands on the right one.
#   stall     a BlackMarket node while it is open, at a "blackmarket_spawn"
#             marker on the chosen edge of the map.
#   shop      purchase(): costs CARRIED Motes plus gold, a hero may buy each
#             item at most blackmarket_max_per_item times per visit (per open
#             window), and only alive, in range, with both in hand. The buff
#             goes on the buyer's TempItems.
#   shopping  begin_shopping()/end_shopping(): the window is open. Damage
#             taken interrupts it (shopping_interrupted) when the rules say so.
#
# Announcements: market_opened / market_closed (the HUD toast, the announcer,
# and a place to hang voice lines later). Server-authoritative shape: the UI
# only calls purchase() / begin_shopping().

signal market_opened(market: BlackMarket)
signal market_closed(market: BlackMarket)
signal purchase_made(hero: Hero, item: BlackMarketItem)
signal shopping_interrupted(hero: Hero)

const GROUP := &"black_market_director"
const SPAWN_GROUP := &"blackmarket_spawn"
const SIDE_LEFT := &"left"
const SIDE_RIGHT := &"right"

enum Phase { WAITING, OPEN, CLOSED }

var events: MapEvents
var manager: MatchManager
var market: BlackMarket
var phase: Phase = Phase.WAITING

# Debug: the schedule is read at clock + _shift (force_open moves it).
var _shift: float = 0.0
var _bought: Dictionary = {}       # Hero -> {item id: count} this visit
var _shoppers: Dictionary = {}     # Hero -> true while their window is open
var _hooked: Dictionary = {}       # Hero -> true once damage is watched
var _warned_no_markers := false


static func find(tree: SceneTree) -> BlackMarketDirector:
	return tree.get_first_node_in_group(GROUP) as BlackMarketDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	events = get_parent() as MapEvents
	manager = events.manager if events != null else null
	if manager != null:
		manager.clock_jumped.connect(func(_from, _to): _shift = 0.0)


func get_rules() -> MapEventRules:
	return MapEvents.rules_for(get_tree())


func get_clock() -> float:
	return (manager.clock if manager != null else 0.0) + _shift


func is_open() -> bool:
	return market != null and is_instance_valid(market)


## Seconds until it opens (WAITING / CLOSED), or until it closes (OPEN).
func get_time_left() -> float:
	return state_at(get_clock()).left


## {phase, index, left}: the schedule at match-clock `clock`. `index` is the
## open window's number (the upcoming one while WAITING / CLOSED).
func state_at(clock: float) -> Dictionary:
	var rules := get_rules()
	var first := rules.blackmarket_first_spawn_time
	if clock < first:
		return {"phase": Phase.WAITING, "index": 0, "left": first - clock}
	var cycle := maxf(rules.market_cycle(), 0.01)
	var t := clock - first
	var index := int(floorf(t / cycle))
	var into := t - index * cycle
	if into < rules.blackmarket_open_time:
		return {"phase": Phase.OPEN, "index": index, "left": rules.blackmarket_open_time - into}
	return {"phase": Phase.CLOSED, "index": index + 1, "left": cycle - into}


## The edge window `index` opens on: a pure function of the match seed.
func side_for(index: int) -> StringName:
	var seed_value := manager.seeded_int("market_side", index) if manager != null else index
	var has_left := not markers_on(SIDE_LEFT).is_empty()
	var has_right := not markers_on(SIDE_RIGHT).is_empty()
	if has_left != has_right:
		return SIDE_LEFT if has_left else SIDE_RIGHT
	return SIDE_LEFT if seed_value % 2 == 0 else SIDE_RIGHT


## The marker window `index` opens at (null if the map has none).
func marker_for(index: int, side: StringName) -> Node2D:
	var options := markers_on(side)
	if options.is_empty():
		return null
	var pick := manager.seeded_int("market_spot", index) if manager != null else index
	return options[pick % options.size()]


func markers_on(side: StringName) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var centre := _map_centre_x()
	for node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		if node is Node2D and ((node.global_position.x < centre) == (side == SIDE_LEFT)):
			result.append(node)
	return result


func _map_centre_x() -> float:
	var map := get_tree().get_first_node_in_group(&"game_map") as GameMap
	return map.to_global(map.bounds.get_center()).x if map != null else 0.0


func _physics_process(_delta: float) -> void:
	var rules := get_rules()
	if manager == null or not manager.is_playing() or not rules.market_enabled:
		if is_open():
			_close()
		phase = Phase.WAITING
		return
	var now := state_at(get_clock())
	phase = now.phase
	if phase == Phase.OPEN:
		if is_open() and market.index != now.index:
			_close()
		if not is_open():
			_open(now.index)
		if is_open():
			market.time_left = now.left
	elif is_open():
		_close()


func _open(index: int) -> void:
	var side := side_for(index)
	var marker := marker_for(index, side)
	if marker == null:
		if not _warned_no_markers:
			_warned_no_markers = true
			push_warning("Black Market: this map has no 'blackmarket_spawn' markers")
		return
	var rules := get_rules()
	market = BlackMarket.new()
	market.name = "BlackMarket"
	market.side = side
	market.index = index
	market.duration = rules.blackmarket_open_time
	market.time_left = rules.blackmarket_open_time
	market.interact_radius = rules.blackmarket_interact_radius
	get_tree().current_scene.add_child(market)
	market.global_position = marker.global_position
	_bought.clear()
	_shoppers.clear()
	market_opened.emit(market)
	MatchManager.play_world_cue(market, &"market_open", {"position": market.global_position,
		"radius": market.interact_radius})


func _close() -> void:
	if not is_open():
		market = null
		return
	var closing := market
	market = null
	for hero in _shoppers.keys():
		shopping_interrupted.emit(hero)
	_shoppers.clear()
	market_closed.emit(closing)
	MatchManager.play_world_cue(closing, &"market_close", {"position": closing.global_position})
	closing.queue_free()


# --- Shop ---------------------------------------------------------------------------------

func get_stock() -> Array[BlackMarketItem]:
	return get_rules().blackmarket_items


func bought_count(hero: Hero, item: BlackMarketItem) -> int:
	return int((_bought.get(hero, {}) as Dictionary).get(item.id, 0))


## "" if `hero` can buy `item` right now, else why not (the buttons' tooltip).
func get_block_reason(hero: Hero, item: BlackMarketItem) -> String:
	if item == null or hero == null or manager == null or not manager.has_hero(hero):
		return "Not available"
	if manager.state == MatchManager.State.ENDED:
		return "Match over"
	if not is_open():
		return "The market is closed"
	if hero.health_component.is_dead():
		return "You are down"
	if not market.can_interact(hero):
		return "Too far from the market"
	if not get_stock().has(item):
		return "Not sold here"
	if bought_count(hero, item) >= get_rules().blackmarket_max_per_item:
		return "Already bought this visit"
	var carrier := MoteCarrier.find_on(hero)
	var carried := carrier.get_spendable_count() if carrier != null else 0
	if carried < item.mote_cost:
		return "Needs %d carried Motes" % item.mote_cost
	if manager.get_gold(hero) + 0.001 < item.gold_cost:
		return "Not enough gold"
	return ""


func can_buy(hero: Hero, item: BlackMarketItem) -> bool:
	return get_block_reason(hero, item) == ""


## Buy `item`: takes its Motes from the hero's carried stack and its gold,
## starts the buff. Returns "" on success, else the reason (nothing changes).
func purchase(hero: Hero, item: BlackMarketItem) -> String:
	var reason := get_block_reason(hero, item)
	if reason != "":
		return reason
	var carrier := MoteCarrier.find_on(hero)
	var ledger := events.ledger if events != null else null
	for taken in carrier.spend(item.mote_cost):
		if ledger != null:
			ledger.record_spent(taken.source, int(taken.value))
	manager.spend_gold(hero, item.gold_cost, MatchManager.REASON_MARKET)
	if not _bought.has(hero):
		_bought[hero] = {}
	_bought[hero][item.id] = bought_count(hero, item) + 1
	TempItems.ensure_on(hero).grant(item)
	manager.play_match_cue(hero, &"market_buy", {"item": item.id})
	purchase_made.emit(hero, item)
	return ""


# --- Shopping window ------------------------------------------------------------------------

func begin_shopping(hero: Hero) -> bool:
	if not is_open() or hero == null or not market.can_interact(hero):
		return false
	_shoppers[hero] = true
	_watch(hero)
	return true


func end_shopping(hero: Hero) -> void:
	_shoppers.erase(hero)


func is_shopping(hero: Hero) -> bool:
	return _shoppers.has(hero)


func _watch(hero: Hero) -> void:
	if _hooked.has(hero):
		return
	_hooked[hero] = true
	hero.health_component.damage_taken.connect(_on_hero_damaged.bind(hero))
	hero.tree_exiting.connect(func(): _hooked.erase(hero); _shoppers.erase(hero), CONNECT_ONE_SHOT)


func _on_hero_damaged(_info: DamageInfo, hero: Hero) -> void:
	if _shoppers.has(hero) and get_rules().blackmarket_close_on_damage:
		_shoppers.erase(hero)
		shopping_interrupted.emit(hero)


# --- Debug -----------------------------------------------------------------------------------

## Open a window now (the schedule continues from it: it closes in
## blackmarket_open_time, and the next one follows the usual gap).
func force_open(side: StringName = &"") -> void:
	var rules := get_rules()
	var clock := manager.clock if manager != null else 0.0
	var now := state_at(clock + _shift)
	if now.phase != Phase.OPEN or side != &"":
		# Start the next window's open phase right now.
		var target_index: int = now.index if now.phase != Phase.OPEN else now.index + 1
		if side != &"":
			# Find the next index that opens on the wanted side.
			while side_for(target_index) != side:
				target_index += 1
		_shift = rules.blackmarket_first_spawn_time + target_index * rules.market_cycle() - clock
		if is_open():
			_close()


func force_close() -> void:
	if not is_open():
		return
	var rules := get_rules()
	var clock := manager.clock if manager != null else 0.0
	var now := state_at(clock + _shift)
	# Jump to the start of the closed gap after this window.
	_shift = rules.blackmarket_first_spawn_time + now.index * rules.market_cycle() + rules.blackmarket_open_time - clock
