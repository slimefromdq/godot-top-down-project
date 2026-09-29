@tool
extends Resource
class_name MapEventRules

# Every tunable of the three map events (Black Market, Mote Island, the
# Wanderer) in ONE resource: resources/rules/map_events.tres, referenced by
# MatchRules.map_events. Nothing here is read from a script's constants; the
# directors ask the rules (MatchManager.get_rules().map_events) every time,
# so the debug panel and tests can edit a private copy live.
#
# The names mirror the design spec: BLACKMARKET_OPEN_TIME is
# blackmarket_open_time, ISLAND_CACHE_MOTES is island_cache_motes, and so on.
# The market's stock (BlackMarketItem) and the Wanderer's body (NeutralData)
# are embedded in the same file, so a balance pass touches one .tres.
#
# None of these events touches the base Mote trickle, the dreaming zones, the
# Dream Mote or the banking rules (MatchRules). Each Mote they add is tagged
# with its source and counted by the MoteLedger.

@export_group("General")
## Master switches (a map without the matching markers runs none anyway).
@export var market_enabled: bool = true
@export var island_enabled: bool = true
@export var wanderer_enabled: bool = true
## One "tile" in pixels (the floor grid's spacing): island ranges are in tiles.
@export var tile_size: float = 160.0
## Motes these events add are worth the late-match multiplier too (like every
## other new Mote after MatchRules.late_match_time).
@export var motes_use_late_mult: bool = true
## Print the per-source Mote report when the match ends.
@export var log_ledger_on_match_end: bool = true

@export_group("Black Market")
## Match-clock seconds of the first spawn (5:00).
@export var blackmarket_first_spawn_time: float = 300.0
## Seconds it stays open...
@export var blackmarket_open_time: float = 90.0
## ...then gone for this long, before it comes back at a random edge.
@export var blackmarket_closed_time: float = 60.0
## How long a bought buff lasts (an item's own `duration` above 0 overrides it).
@export var blackmarket_item_duration: float = 60.0
## A hero this close to the stall can open its shop.
@export var blackmarket_interact_radius: float = 320.0
## Taking damage closes the shop window (and the purchase in progress).
@export var blackmarket_close_on_damage: bool = true
## Each hero can buy each item at most this many times per market visit.
@export var blackmarket_max_per_item: int = 1
## The stock: 4 to 5 strong temporary items.
@export var blackmarket_items: Array[BlackMarketItem] = []

@export_subgroup("Bots")
## Bots visit the market only when they can afford at least their cheapest
## wanted item, are healthy, and are not in a fight.
@export var bot_market_enabled: bool = true
@export var bot_market_min_health: float = 0.6
## They never walk further than this to reach the stall.
@export var bot_market_max_distance: float = 5200.0
## A bot that buys nothing waits this long before considering the market again.
@export var bot_market_retry_time: float = 20.0

@export_group("Mote Island")
## The portal shows up at match start (0) or later.
@export var island_first_spawn_time: float = 0.0
## The portal moves to a NEW hidden spot this often (never the same twice
## in a row).
@export var island_relocate_time: float = 180.0
## Motes in the cache (refilled every relocation).
@export var island_cache_motes: int = 8
## Most seconds a visitor stays before being sent home (0 = no limit).
@export var island_stay_time: float = 12.0
## A subtle shimmer and sound for the local player within this many tiles...
@export var island_shimmer_tiles: float = 10.0
## ...and fully visible within this many.
@export var island_visible_tiles: float = 3.0
## Stepping this close (in tiles) lets you use it.
@export var island_interact_tiles: float = 1.5
## The island lives here in world space, far outside the map.
@export var island_origin: Vector2 = Vector2(24000.0, 0.0)
## Its inside size (walls are built around it).
@export var island_size: Vector2 = Vector2(1500.0, 1000.0)
## Where the cache Motes sit, as fractions of half the island's size.
@export var island_cache_spread: float = 0.55
## The portal's colour (warm amber, so it never reads as a purple teleporter).
@export var island_portal_color: Color = Color("f59e0b")
## Seconds between the shimmer sound while you're near the portal.
@export var island_shimmer_sound_interval: float = 2.5

@export_group("Wanderer")
## Match-clock seconds of the first spawn (2:00).
@export var wanderer_first_spawn: float = 120.0
## Seconds after it dies or escapes before the next one.
@export var wanderer_respawn: float = 120.0
## Each hit that hurts it drops this many Motes...
@export var wanderer_motes_per_hit: int = 1
## ...up to this many in total; it dies holding what is left.
@export var wanderer_max_motes: int = 6
## A hit must deal at least this much to drop Motes, and hits closer together
## than the cooldown count as one (damage over time can't farm it).
@export var wanderer_min_hit_damage: float = 1.0
@export var wanderer_hit_drop_cooldown: float = 0.25
## Gold for the killer (a small reward; XP is 0).
@export var wanderer_gold_reward: float = 75.0
## Seconds without damage before it calms down and wanders again.
@export var wanderer_calm_time: float = 6.0
## Speeds in px/s. The flee speed must beat every hero's base move speed.
@export var wanderer_flee_speed: float = 540.0
@export var wanderer_wander_speed: float = 120.0
## How quickly it gets up to speed (px/s^2), so a turn is not a drift.
@export var wanderer_acceleration: float = 3200.0
## Heroes within this many px count as threats to run from.
@export var wanderer_threat_radius: float = 1400.0
## Cornered (nowhere open to run, or pressed against a wall) it moves at this
## share of its flee speed.
@export_range(0.2, 1.0, 0.05) var wanderer_cornered_speed_mult: float = 0.8
## It meanders within this radius of where it spawned.
@export var wanderer_wander_radius: float = 700.0
@export var wanderer_wander_pause: float = 2.0
## It leaves the map if it lives this long since spawning...
@export var wanderer_max_lifetime: float = 150.0
## ...or this long after its first hit (an escape).
@export var wanderer_escape_time: float = 45.0
## Motes it drops use the late-match multiplier only if motes_use_late_mult.
@export var wanderer_announce: bool = true

@export_subgroup("Flee path")
## Candidate escape destinations sampled around it every repath...
@export var wanderer_flee_candidates: int = 16
## ...at about this distance...
@export var wanderer_flee_distance: float = 1500.0
## ...re-planned this often while it is being chased.
@export var wanderer_repath_interval: float = 0.35
## A destination scores: distance from the nearest threat x threat_weight +
## openness x openness_weight - (path length beyond the direct one) x detour_weight.
## Openness = how many nav cells lie within openness_hops of it, so a dead end
## scores near zero.
@export var wanderer_threat_weight: float = 1.0
@export var wanderer_openness_weight: float = 40.0
@export var wanderer_detour_weight: float = 0.6
## The destination it is already running to gets this bonus when it re-plans,
## so it doesn't dither between two equally good escapes.
@export var wanderer_flee_stickiness: float = 250.0
@export var wanderer_openness_hops: int = 4
## A destination with fewer nav cells than this within the hops is a dead end
## and is skipped unless nothing else is left.
@export var wanderer_dead_end_cells: int = 30
## Below this many free cells around it the Wanderer counts as cornered.
@export var wanderer_cornered_cells: int = 20
## The Wanderer's body: stats, size and look (a NeutralData; its schedule and
## fight fields are unused).
@export var wanderer_data: NeutralData


func get_item(id: StringName) -> BlackMarketItem:
	for item in blackmarket_items:
		if item != null and item.id == id:
			return item
	return null


func item_duration(item: BlackMarketItem) -> float:
	return item.duration if item != null and item.duration > 0.0 else blackmarket_item_duration


func market_cycle() -> float:
	return blackmarket_open_time + blackmarket_closed_time


func tiles(count: float) -> float:
	return count * tile_size


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if blackmarket_open_time <= 0.0 or blackmarket_closed_time < 0.0 or blackmarket_first_spawn_time < 0.0:
		problems.append("black market needs a positive open time and non-negative closed / first spawn times")
	if blackmarket_items.size() < 1:
		problems.append("black market has no stock")
	var seen := {}
	for item in blackmarket_items:
		if item == null:
			problems.append("black market has an empty stock slot")
			continue
		if seen.has(item.id):
			problems.append("black market sells '%s' twice" % item.id)
		seen[item.id] = true
		problems.append_array(item.validate())
	if island_relocate_time <= 0.0 or island_cache_motes < 0 or island_stay_time < 0.0:
		problems.append("island needs a positive relocate time and non-negative cache / stay time")
	if island_visible_tiles > island_shimmer_tiles:
		problems.append("island visible range is larger than its shimmer range")
	if island_interact_tiles > island_visible_tiles:
		problems.append("island can be used from further away than it is visible")
	if wanderer_max_motes < 0 or wanderer_motes_per_hit < 0:
		problems.append("wanderer Mote counts are negative")
	if wanderer_data == null:
		problems.append("wanderer has no NeutralData")
	else:
		problems.append_array(wanderer_data.validate())
	if wanderer_flee_speed <= wanderer_wander_speed:
		problems.append("wanderer flees no faster than it wanders")
	return problems
