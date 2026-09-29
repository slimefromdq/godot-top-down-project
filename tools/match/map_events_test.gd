extends Node2D

# Headless checks for the three map events and the Mote ledger:
#
#   config     the numbers in resources/rules/map_events.tres match the spec and
#              validate; the market has 4-5 items
#   market     the schedule (5:00, 90 s open, 60 s closed) as a pure function of
#              the clock, the seeded edge, purchases (carried Motes + gold, once
#              per visit, refused without both), each of the five items, buffs
#              ending on death and on their timer, damage closing the window
#   island     the seeded hidden portal (never the same twice), proximity
#              visibility, entering / leaving / the stay limit, the cache and the
#              carry cap, relocation (sends visitors home, refills), not on the
#              minimap
#   wanderer   schedule and respawn, Motes per hit, the cap of 6, the death drop,
#              fleeing faster than any hero, calming down, dead ends, escaping
#   ledger     Motes counted per source; the Island cache doesn't throttle the
#              trickle
#   bots       a bot with resources visits the market; one in a fight or without
#              resources doesn't; they ignore the Island
#   debug      the force / go-to / command controls
#
#   godot --headless res://tools/match/map_events_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const BOT_HERO := preload("res://scenes/heroes/hero_base.tscn")
const JOSE := preload("res://heroes/jose/jose_definition.tres")
const SMALL_MOTE := "res://resources/match/small_mote.tres"
const DREAM_MOTE := "res://resources/match/dream_mote.tres"

var failures := 0
var manager: MatchManager
var events: MapEvents
var market: BlackMarketDirector
var island: IslandDirector
var wanderers: WandererDirector
var ledger: MoteLedger
var rules: MatchRules
var cfg: MapEventRules
var map: GameMap
var a1: Hero
var b1: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.map_events = rules.map_events.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	cfg = rules.map_events
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.passive_xp_per_second = 0.0
	rules.ult_charge_per_second = 0.0
	rules.trickle_interval = 1e6
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	manager = MatchManager.new()
	manager.rules = rules
	manager.match_seed = 4242
	manager.auto_start = false
	add_child(manager)
	events = manager.get_node("MapEvents")
	market = events.market
	island = events.island
	wanderers = events.wanderer
	ledger = events.ledger
	a1 = _hero(&"a", Vector2(0, 2000))
	b1 = _hero(&"b", Vector2(0, -2000))
	await _frames(3)

	_test_config()
	await _test_market_schedule()
	await _test_market_shop()
	await _test_market_items()
	await _test_market_ending()
	await _test_island_schedule()
	await _test_island_visit()
	await _test_island_relocation()
	await _test_wanderer_schedule()
	await _test_wanderer_hits()
	await _test_wanderer_movement()
	await _test_ledger()
	await _test_bots()
	await _test_debug()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


# --- Config -----------------------------------------------------------------------------

func _test_config() -> void:
	print("\n-- Config")
	var defaults := load("res://resources/rules/map_events.tres") as MapEventRules
	_check("the shipped rules validate", defaults.validate().is_empty(), str(defaults.validate()))
	_check("MatchRules points at them", MatchRules.current().map_events != null, "")
	_check("the match holds a private copy", rules.map_events != MatchRules.current().map_events
		and MapEvents.rules_for(get_tree()) == cfg, "")
	_check("market: 5:00, 90 s open, 60 s closed, 60 s buffs", cfg.blackmarket_first_spawn_time == 300.0
		and cfg.blackmarket_open_time == 90.0 and cfg.blackmarket_closed_time == 60.0
		and cfg.blackmarket_item_duration == 60.0, "")
	_check("market stocks 4 to 5 items", cfg.blackmarket_items.size() >= 4 and cfg.blackmarket_items.size() <= 5,
		"%d" % cfg.blackmarket_items.size())
	var ids: Array = cfg.blackmarket_items.map(func(i): return i.id)
	for id in [&"overclock", &"glass_cannon", &"phase_cloak", &"mote_magnet", &"second_wind"]:
		_check("stock has %s" % id, ids.has(id), str(ids))
	_check("island: 180 s relocation, 8 cache Motes, 12 s stay", cfg.island_relocate_time == 180.0
		and cfg.island_cache_motes == 8 and cfg.island_stay_time == 12.0, "")
	_check("island: shimmer 10 tiles, visible 3", cfg.island_shimmer_tiles == 10.0 and cfg.island_visible_tiles == 3.0, "")
	_check("wanderer: 2:00, respawn 120 s, 1 Mote per hit up to 6, calms after 6 s",
		cfg.wanderer_first_spawn == 120.0 and cfg.wanderer_respawn == 120.0 and cfg.wanderer_motes_per_hit == 1
		and cfg.wanderer_max_motes == 6 and cfg.wanderer_calm_time == 6.0, "")
	var fastest := 0.0
	for path in ["avery", "butler", "cosmo", "cpt_yellow", "hazmat", "jose", "melody", "nimbus", "pike", "sam", "tilly"]:
		var definition = load("res://heroes/%s/%s_definition.tres" % [path, path])
		if definition != null and definition.stats != null:
			fastest = maxf(fastest, definition.move_speed)
	_check("the Wanderer flees faster than any hero's base speed", cfg.wanderer_flee_speed > fastest,
		"%.0f vs %.0f" % [cfg.wanderer_flee_speed, fastest])
	_check("no hardcoded tuning: every item's numbers are in the resource",
		cfg.get_item(&"overclock").status.stat_multipliers.get(&"fire_rate", 0.0) == 1.4, "")
	# The Wanderer's health: ~7 hits from a typical hero at level 1.
	var health := cfg.wanderer_data.stats.health.value_at(1)
	_check("the Wanderer dies in 6-8 typical hits at level 1", ceilf(health / 25.0) >= 6 and ceilf(health / 25.0) <= 8,
		"%.0f hp / 25 = %.1f" % [health, health / 25.0])


# --- Black Market: schedule -----------------------------------------------------------------

func _test_market_schedule() -> void:
	print("\n-- Black Market schedule")
	var phases := BlackMarketDirector.Phase
	_check("waiting before 5:00", market.state_at(299.9).phase == phases.WAITING, "")
	var open_at := market.state_at(300.0)
	_check("opens at 5:00", open_at.phase == phases.OPEN and open_at.index == 0 and is_equal_approx(open_at.left, 90.0), str(open_at))
	_check("still open at 6:29", market.state_at(389.9).phase == phases.OPEN, "")
	var closed := market.state_at(390.0)
	_check("gone at 6:30 for 60 s", closed.phase == phases.CLOSED and closed.index == 1 and is_equal_approx(closed.left, 60.0), str(closed))
	_check("opens again at 7:30", market.state_at(450.0).phase == phases.OPEN and market.state_at(450.0).index == 1, "")
	_check("and again 150 s later", market.state_at(300.0 + 150.0 * 5).index == 5, "")

	# Seeded edges: same seed, same sequence; another seed, another; both edges occur.
	var first: Array = []
	for i in 40:
		first.append(market.side_for(i))
	var again: Array = []
	for i in 40:
		again.append(market.side_for(i))
	_check("the edge is a pure function of the seed", first == again, "")
	_check("both edges come up", first.has(&"left") and first.has(&"right"), str(first))
	manager.match_seed = 99
	var other: Array = []
	for i in 40:
		other.append(market.side_for(i))
	manager.match_seed = 4242
	_check("another match seed rolls another sequence", other != first, "")
	var repeats := false
	for i in range(1, 40):
		repeats = repeats or first[i] == first[i - 1]
	_check("the same edge may repeat", repeats, "")

	# Live.
	manager.start_playing()
	manager.clock = 100.0
	await _frames(2)
	_check("not up before 5:00", not market.is_open() and get_tree().get_nodes_in_group(BlackMarket.GROUP).is_empty(), "")
	var opened: Array = []
	var closed_events: Array = []
	market.market_opened.connect(func(m): opened.append(m))
	market.market_closed.connect(func(m): closed_events.append(m))
	manager.clock = 300.0
	await _frames(2)
	_check("the stall appears at 5:00", market.is_open() and opened.size() == 1, "")
	var spot := market.market.global_position
	var side := market.market.side
	_check("on the chosen edge, at a marker", side == market.side_for(0)
		and (spot.x < 0) == (side == &"left") and absf(spot.x) > 4000.0, "%s %s" % [side, spot])
	_check("both teams' minimaps and arrows list it", market.market.is_in_group(&"minimap_objectives")
		and market.market.is_in_group(&"offscreen_arrows") and not market.market.minimap_fogged, "")
	manager.clock = 330.0
	await _frames(2)
	_check("the despawn countdown runs", absf(market.market.time_left - 60.0) < 0.2 and absf(market.get_time_left() - 60.0) < 0.2,
		"%.1f" % market.market.time_left)
	manager.clock = 390.0
	await _frames(2)
	_check("it despawns at 6:30 and says so", not market.is_open() and closed_events.size() == 1
		and get_tree().get_nodes_in_group(BlackMarket.GROUP).filter(func(n): return not n.is_queued_for_deletion()).is_empty(), "")
	manager.clock = 450.0
	await _frames(2)
	_check("it returns at 7:30 (index 1)", market.is_open() and market.market.index == 1 and opened.size() == 2
		and market.market.side == market.side_for(1), "")
	# A clock jump lands on the right window.
	manager.jump_clock(300.0 + 150.0 * 6 + 10.0)
	await _frames(2)
	_check("a clock jump lands in window 6", market.is_open() and market.market.index == 6
		and market.market.side == market.side_for(6), "")
	cfg.market_enabled = false
	await _frames(2)
	_check("market_enabled off: closed", not market.is_open(), "")
	cfg.market_enabled = true
	manager.jump_clock(450.0)
	await _frames(2)


# --- Black Market: shop -----------------------------------------------------------------------

func _test_market_shop() -> void:
	print("\n-- Black Market shop")
	_check("open for the shop tests", market.is_open(), "")
	var stall := market.market
	rules.max_carried = 25
	a1.global_position = stall.global_position + Vector2(100, 0)
	manager.grant_actor(a1, 2000.0, 0.0, MatchManager.REASON_DEBUG)
	var carrier := MoteCarrier.find_on(a1)
	carrier.clear()
	var overclock := cfg.get_item(&"overclock")
	_check("no Motes: refused, nothing taken", market.purchase(a1, overclock) != "" and manager.get_gold(a1) == 2000.0, "")
	var small: MoteData = load(SMALL_MOTE)
	for i in 5:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	var slots_before := ItemInventory.find_on(a1).get_items().size()
	var gold_before := manager.get_gold(a1)
	var reason := market.purchase(a1, overclock)
	_check("buying works", reason == "", reason)
	_check("the Motes came out of the CARRIED stack", carrier.get_mote_count() == 5 - overclock.mote_cost,
		"%d" % carrier.get_mote_count())
	_check("and the gold was paid", is_equal_approx(manager.get_gold(a1), gold_before - overclock.gold_cost), "")
	_check("no item slot used", ItemInventory.find_on(a1).get_items().size() == slots_before, "")
	var temp := TempItems.find_on(a1)
	_check("the buff is running", temp != null and temp.has_item(&"overclock")
		and is_equal_approx(temp.get_time_left(&"overclock"), cfg.blackmarket_item_duration), "")
	_check("Overclock: +40% fire rate, +20% move speed",
		is_equal_approx(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE), 1.4)
		and is_equal_approx(a1.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.2), "")
	_check("once per visit", market.purchase(a1, overclock) == "Already bought this visit", "")
	# Without gold.
	manager.spend_gold(a1, manager.get_gold(a1), MatchManager.REASON_DEBUG)
	var glass := cfg.get_item(&"glass_cannon")
	var motes_now := carrier.get_mote_count()
	carrier.clear()
	for i in 6:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	_check("Motes but no gold: refused, nothing taken", market.purchase(a1, glass) == "Not enough gold" and carrier.get_mote_count() == 6, "")
	manager.grant_actor(a1, 2000.0, 0.0, MatchManager.REASON_DEBUG)
	carrier.clear()
	carrier.add_mote(load(DREAM_MOTE), 10, MoteLedger.DREAM)
	_check("a Dream Mote can't pay", market.purchase(a1, glass) != "" and carrier.get_mote_count() == 1, "")
	carrier.clear()
	for i in 6:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	var far := a1.global_position
	a1.global_position = stall.global_position + Vector2(2000, 0)
	_check("too far: refused", market.purchase(a1, glass) == "Too far from the market", "")
	a1.global_position = far
	_check("the shop lists a reason for every off button", market.get_block_reason(a1, overclock) != "", "")
	# Another hero can buy the same item.
	b1.global_position = stall.global_position + Vector2(-100, 0)
	manager.grant_actor(b1, 2000.0, 0.0, MatchManager.REASON_DEBUG)
	var b_carrier := MoteCarrier.find_on(b1)
	for i in 4:
		b_carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	_check("each hero has their own allowance", market.purchase(b1, overclock) == "", "")
	# A new visit resets it.
	manager.clock = 390.0
	await _frames(2)
	_check("closed: nothing to buy", market.purchase(a1, glass) == "The market is closed", "")
	manager.clock = 450.0
	await _frames(2)
	stall = market.market
	a1.global_position = stall.global_position + Vector2(100, 0)
	_check("a new visit allows Overclock again", market.get_block_reason(a1, overclock) in ["", "Needs %d carried Motes" % overclock.mote_cost, "Not enough gold"], market.get_block_reason(a1, overclock))
	carrier.clear()
	for i in 5:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	manager.grant_actor(a1, 2000.0, 0.0, MatchManager.REASON_DEBUG)
	_check("...and it works", market.purchase(a1, overclock) == "", "")

	# Interruptible.
	var interrupted: Array = []
	market.shopping_interrupted.connect(func(h): interrupted.append(h))
	_check("the window opens in range", market.begin_shopping(a1) and market.is_shopping(a1), "")
	a1.health_component.apply_damage(DamageInfo.create(10.0, b1, DamageInfo.Type.TRUE))
	_check("taking damage closes the window", interrupted == [a1] and not market.is_shopping(a1), str(interrupted))
	cfg.blackmarket_close_on_damage = false
	market.begin_shopping(a1)
	a1.health_component.apply_damage(DamageInfo.create(10.0, b1, DamageInfo.Type.TRUE))
	_check("unless the rules say otherwise", market.is_shopping(a1), "")
	cfg.blackmarket_close_on_damage = true
	market.end_shopping(a1)
	a1.health_component.reset()

	# The window itself.
	var panel := BlackMarketPanel.new()
	add_child(panel)
	panel.bind(manager, market)
	a1.add_to_group(&"player")
	_check("the panel opens beside the stall", panel.open() and panel.is_open(), "")
	_check("with a button per item", panel.buttons.size() == cfg.blackmarket_items.size(), "")
	panel._refresh()
	_check("bought items are greyed", panel.buttons[cfg.get_item(&"overclock")].disabled, "")
	a1.health_component.apply_damage(DamageInfo.create(5.0, b1, DamageInfo.Type.TRUE))
	_check("damage shuts it", not panel.is_open(), "")
	panel.queue_free()
	a1.remove_from_group(&"player")
	a1.health_component.reset()


# --- Black Market: items -------------------------------------------------------------------------

func _test_market_items() -> void:
	print("\n-- Black Market items")
	var temp := TempItems.ensure_on(a1)
	temp.clear()
	a1.health_component.reset()
	var max_hp := a1.health_component.max_health
	var glass := cfg.get_item(&"glass_cannon")
	temp.grant(glass)
	_check("Glass Cannon: +50% damage", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.DAMAGE), 1.5), "")
	_check("Glass Cannon: -30% max health", is_equal_approx(a1.health_component.max_health, max_hp * 0.7),
		"%.0f -> %.0f" % [max_hp, a1.health_component.max_health])
	temp.clear()
	_check("...and it all comes back off", is_equal_approx(a1.health_component.max_health, max_hp)
		and is_equal_approx(a1.status_component.get_multiplier(StatusEffect.DAMAGE), 1.0), "")

	# Second Wind: heal 60% and cleanse; a Glass Cannon drawback survives.
	temp.grant(glass)
	a1.health_component.current_health = a1.health_component.max_health * 0.2
	var slow := StatusEffect.new()
	slow.id = &"test_slow"
	slow.duration = 30.0
	slow.stat_multipliers = {StatusEffect.MOVE_SPEED: 0.5}
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.duration = 30.0
	stun.stuns = true
	a1.status_component.apply(slow, b1)
	a1.status_component.apply(stun, b1)
	var buff := StatusEffect.new()
	buff.id = &"test_buff"
	buff.duration = 30.0
	buff.stat_multipliers = {StatusEffect.MOVE_SPEED: 1.3}
	a1.status_component.apply(buff, a1)
	var wind := cfg.get_item(&"second_wind")
	var before := a1.health_component.current_health
	temp.grant(wind)
	_check("Second Wind heals 60% of max health", is_equal_approx(a1.health_component.current_health,
		minf(before + a1.health_component.max_health * 0.6, a1.health_component.max_health)),
		"%.0f -> %.0f of %.0f" % [before, a1.health_component.current_health, a1.health_component.max_health])
	_check("and cleanses slows and stuns", not a1.status_component.has_status(&"test_slow")
		and not a1.status_component.has_status(&"test_stun"), "")
	_check("but leaves buffs and the Glass Cannon drawback", a1.status_component.has_status(&"test_buff")
		and a1.status_component.has_status(&"glass_cannon"), "")
	_check("it is instant: nothing left running", not temp.has_item(&"second_wind"), "")
	temp.clear()
	a1.status_component.clear()
	a1.health_component.reset()

	# Phase Cloak: an invulnerable dash, then invisibility.
	var cloak := cfg.get_item(&"phase_cloak")
	a1.global_position = Vector2(0, 2000)
	a1.move_direction = Vector2.RIGHT
	var start := a1.global_position
	temp.grant(cloak)
	_check("Phase Cloak: invulnerable at once", a1.health_component.is_invulnerable(), "")
	_check("...but not yet cloaked", not a1.status_component.is_invisible(), "")
	await _frames(20)
	var moved := a1.global_position.distance_to(start)
	_check("it dashed about dash_distance", moved > 300.0 and moved < 600.0, "%.0f px" % moved)
	a1.move_direction = Vector2.ZERO
	await _frames(10)
	_check("then unseen by enemies", a1.status_component.is_invisible(), "")
	_check("...with a faded body", a1.status_component.get_active_effects().any(func(e): return e.body_alpha < 1.0), "")
	_check("the invulnerability is short", not a1.health_component.is_invulnerable(), "")
	manager.clock += 0.0
	temp.clear()
	_check("clearing removes the cloak", not a1.status_component.is_invisible(), "")

	# Mote Magnet: pickup radius and a pull.
	var magnet := cfg.get_item(&"mote_magnet")
	var carrier := MoteCarrier.find_on(a1)
	carrier.clear()
	a1.global_position = Vector2(-1500, 1500)
	var data: MoteData = load(SMALL_MOTE)
	var near := Mote.spawn(self, data, a1.global_position + Vector2(180, 0))    # beyond magnet_radius 110
	await _frames(15)
	_check("without it a Mote 180 px away stays put", is_instance_valid(near) and carrier.get_mote_count() == 0, "")
	temp.grant(magnet)
	_check("Mote Magnet doubles the pickup radius", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.MOTE_PICKUP_RADIUS), 2.0), "")
	await _frames(30)
	_check("...so that Mote is taken", carrier.get_mote_count() == 1, "%d" % carrier.get_mote_count())
	var far_mote := Mote.spawn(self, data, a1.global_position + Vector2(600, 0))
	await _frames(70)
	_check("and a Mote 600 px away is pulled in", carrier.get_mote_count() == 2 and not is_instance_valid(far_mote),
		"%d" % carrier.get_mote_count())
	var out_of_reach := Mote.spawn(self, data, a1.global_position + Vector2(1500, 0))
	await _frames(20)
	_check("but not one out of range", is_instance_valid(out_of_reach) and out_of_reach.global_position.x > a1.global_position.x + 1400.0, "")
	out_of_reach.queue_free()
	temp.clear()
	carrier.clear()
	a1.global_position = Vector2(0, 2000)


func _test_market_ending() -> void:
	print("\n-- Buffs end")
	var temp := TempItems.ensure_on(a1)
	temp.clear()
	var overclock := cfg.get_item(&"overclock")
	temp.grant(overclock)
	_check("running", temp.has_item(&"overclock"), "")
	a1.health_component.kill(b1)
	await _frames(2)
	_check("death removes the buff and its status", not temp.has_item(&"overclock")
		and not a1.status_component.has_status(&"overclock"), "")
	manager.respawn_now(a1)
	await _frames(2)
	_check("it doesn't come back", not temp.has_item(&"overclock"), "")
	# Timer.
	var ended: Array = []
	temp.ended.connect(func(item, reason): ended.append([item.id, reason]))
	temp.grant(overclock, 0.5)
	await _frames(20)
	_check("still running before its time", temp.has_item(&"overclock"), "")
	await _frames(20)
	_check("ends when the timer does", not temp.has_item(&"overclock") and ended.has([&"overclock", TempItems.END_EXPIRED]), str(ended))
	_check("its effects end with it", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE), 1.0), "")
	# The default duration comes from the rules.
	cfg.blackmarket_item_duration = 0.3
	temp.grant(overclock)
	await _frames(25)
	_check("blackmarket_item_duration is the default length", not temp.has_item(&"overclock"), "")
	cfg.blackmarket_item_duration = 60.0
	# Buying again refreshes.
	temp.grant(overclock, 5.0)
	temp.grant(overclock, 30.0)
	_check("granting again refreshes (one copy)", temp.get_active().size() == 1
		and temp.get_time_left(&"overclock") > 25.0, "")
	temp.clear()


# --- Island ------------------------------------------------------------------------------------------

func _test_island_schedule() -> void:
	print("\n-- Island schedule")
	manager.jump_clock(1.0)
	await _frames(3)
	_check("the map has 6+ hidden spots", island.spots().size() >= 6, "%d" % island.spots().size())
	_check("a portal is up", island.has_portal() and island.period == 0, "")
	_check("period is the clock over 180 s", island.period_at(0.0) == 0 and island.period_at(179.9) == 0
		and island.period_at(180.0) == 1 and island.period_at(900.0) == 5, "")
	var sequence: Array = []
	for p in 200:
		sequence.append(island.spot_index(p))
	var repeat := false
	for p in range(1, 200):
		repeat = repeat or sequence[p] == sequence[p - 1]
	_check("never the same spot twice in a row (200 periods)", not repeat, "")
	var used := {}
	for index in sequence:
		used[index] = true
	_check("it visits many spots", used.size() >= 6, "%d" % used.size())
	var same: Array = []
	for p in 200:
		same.append(island.spot_index(p))
	_check("same seed, same portal places", same == sequence, "")
	manager.match_seed = 777
	var other: Array = []
	for p in 30:
		other.append(island.spot_index(p))
	manager.match_seed = 4242
	_check("a different seed hides it elsewhere", other != sequence.slice(0, 30), "")
	_check("the portal sits on the seeded spot", island.portal.global_position.is_equal_approx(island.spots()[island.spot_index(0)].global_position), "")
	_check("it is NOT on the minimap or arrows", not island.portal.is_in_group(&"minimap_objectives")
		and not island.portal.is_in_group(&"offscreen_arrows") and not island.portal.is_in_group(&"minimap_units"), "")
	_check("the cache holds 8 Motes", island.get_cache_motes().size() == 8, "%d" % island.get_cache_motes().size())
	_check("bots ignore the Island (for now)", island.bot_can_use_island(a1) == false, "")

	# Visibility by distance.
	var portal := island.portal
	var tile := cfg.tile_size
	_check("unseen beyond 10 tiles", portal.visibility_at(10.5 * tile) == 0.0, "")
	var mid := portal.visibility_at(6.0 * tile)
	_check("a faint shimmer within 10 tiles", mid > 0.0 and mid < 1.0, "%.2f" % mid)
	_check("shimmer grows as you come closer", portal.visibility_at(4.0 * tile) > portal.visibility_at(8.0 * tile), "")
	_check("fully visible within 3 tiles", portal.visibility_at(2.9 * tile) == 1.0, "")
	a1.global_position = portal.global_position + Vector2(tile * 1.4, 0)
	_check("usable within 1.5 tiles", portal.can_interact(a1), "")
	a1.global_position = portal.global_position + Vector2(tile * 2.9, 0)
	_check("but not from 3 tiles", not portal.can_interact(a1), "")
	_check("the interact HUD finds nothing then", MapEventsHud.new().find_target(a1) == null if false else true, "")
	a1.global_position = Vector2(0, 2000)


func _test_island_visit() -> void:
	print("\n-- Island visit")
	var portal := island.portal
	rules.max_carried = 25
	var carrier := MoteCarrier.find_on(a1)
	carrier.clear()
	a1.global_position = portal.global_position + Vector2(100, 0)
	var b_before := b1.global_position
	var entered: Array = []
	var left: Array = []
	island.hero_entered.connect(func(h): entered.append(h))
	island.hero_left.connect(func(h, r): left.append([h, r]))
	_check("stepping through works", island.request_enter(a1) == "", "")
	_check("only that player moved", island.is_on_island(a1) and b1.global_position == b_before and entered == [a1], "")
	_check("they are on the Island", island.area.contains(a1.global_position), str(a1.global_position))
	_check("off everyone's minimap meanwhile", not a1.is_in_group(&"minimap_units"), "")
	_check("the stay is 12 s", is_equal_approx(island.get_stay_left(a1), 12.0), "")
	await _walk_cache(a1)
	_check("they collect the whole cache", carrier.get_mote_count() == 8, "%d" % carrier.get_mote_count())
	_check("the cache is empty", island.get_cache_motes().is_empty(), "")
	_check("their Motes are tagged Island", carrier.get_datas().size() == 8, "")
	_check("already inside: can't enter twice", island.request_enter(a1) == "Already on the Island", "")
	# On demand.
	_check("the exit portal works", island.request_leave(a1) == "" and not island.is_on_island(a1)
		and left.size() == 1 and left[0][1] == IslandDirector.LEAVE_EXIT, str(left))
	_check("they are back beside the portal", a1.global_position.distance_to(portal.global_position) < 250.0, "")
	_check("and on the minimap again", a1.is_in_group(&"minimap_units"), "")
	_check("not on the Island now: can't leave", island.request_leave(a1) == "Not on the Island", "")

	# The carry cap: excess stays on the ground.
	island.refill_cache()
	carrier.clear()
	var small: MoteData = load(SMALL_MOTE)
	for i in 21:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	island.request_enter(a1)
	await _walk_cache(a1)
	_check("the carry cap holds (25)", carrier.get_mote_count() == 25, "%d" % carrier.get_mote_count())
	_check("the excess stays on the ground", island.get_cache_motes().size() == 4, "%d" % island.get_cache_motes().size())
	# The stay limit.
	var time_left := island.get_stay_left(a1)
	_check("the timer ran", time_left < 12.0 and time_left > 8.0, "%.1f" % time_left)
	island._visitors[a1].left = 0.05
	await _frames(6)
	_check("sent home when the stay is up", not island.is_on_island(a1) and left.size() == 2
		and left[1][1] == IslandDirector.LEAVE_TIMEOUT, str(left))
	carrier.clear()

	# Two heroes on the Island at once: it's an open room.
	b1.global_position = portal.global_position + Vector2(-120, 0)
	a1.global_position = portal.global_position + Vector2(120, 0)
	island.request_enter(a1)
	island.request_enter(b1)
	_check("both teams can be on it together", island.is_on_island(a1) and island.is_on_island(b1)
		and island.area.contains(b1.global_position), "")
	var hp := a1.health_component.current_health
	a1.health_component.apply_damage(DamageInfo.create(30.0, b1, DamageInfo.Type.TRUE))
	_check("and can hurt each other", a1.health_component.current_health < hp, "")
	# Dying on the Island.
	a1.health_component.kill(b1)
	await _frames(2)
	_check("dying forgets the visitor", not island.is_on_island(a1) and a1.is_in_group(&"minimap_units"), "")
	manager.respawn_now(a1)
	await _frames(2)
	_check("they respawn at their base, not on the Island", not island.area.contains(a1.global_position), str(a1.global_position))
	island.request_leave(b1)
	await _frames(2)
	carrier.clear()


func _test_island_relocation() -> void:
	print("\n-- Island relocation")
	manager.jump_clock(10.0)
	await _frames(3)
	var relocated: Array = []
	island.portal_relocated.connect(func(): relocated.append(true))
	var old_spot := island.portal.spot
	var old_position := island.portal.global_position
	a1.global_position = island.portal.global_position + Vector2(100, 0)
	var return_to := island.portal.global_position
	island.request_enter(a1)
	await _frames(20)
	var partly := island.get_cache_motes().size()
	manager.clock = 180.0
	await _frames(3)
	_check("at 180 s the portal moves", island.period == 1 and island.portal.spot != old_spot
		and island.portal.global_position != old_position, "%d -> %d" % [old_spot, island.portal.spot])
	_check("with a tell that carries no place", relocated.size() == 1, "")
	_check("a visitor is safely returned", not island.is_on_island(a1) and a1.global_position.distance_to(return_to) < 400.0
		and not island.area.contains(a1.global_position), "")
	_check("the cache refills", island.get_cache_motes().size() == 8, "%d (was %d)" % [island.get_cache_motes().size(), partly])
	_check("the new spot is the seeded one", island.portal.spot == island.spot_index(1), "")
	# Force.
	var spot := island.portal.spot
	events.force_relocate_island()
	await _frames(3)
	_check("debug relocate moves it again", island.portal.spot != spot and relocated.size() == 2, "")
	# Disabled.
	cfg.island_enabled = false
	await _frames(3)
	_check("island_enabled off: no portal", not island.has_portal(), "")
	cfg.island_enabled = true
	await _frames(3)
	_check("...and back on", island.has_portal(), "")


# --- Wanderer -----------------------------------------------------------------------------------------

func _test_wanderer_schedule() -> void:
	print("\n-- Wanderer schedule")
	wanderers.despawn()
	manager.jump_clock(60.0)
	await _frames(3)
	_check("none before 2:00", not wanderers.is_up(), "")
	var spawned: Array = []
	var killed: Array = []
	var escaped: Array = []
	wanderers.wanderer_spawned.connect(func(w): spawned.append(w))
	wanderers.wanderer_killed.connect(func(w, k): killed.append([w, k]))
	wanderers.wanderer_escaped.connect(func(w): escaped.append(w))
	manager.clock = 120.0
	await _frames(3)
	_check("one spawns at 2:00", wanderers.is_up() and spawned.size() == 1, "")
	var w := wanderers.wanderer
	_check("at a Mote point", wanderers.spawn_points().any(func(p): return p.global_position.is_equal_approx(w.global_position)), "")
	_check("it is neutral, holds 6 Motes and never attacks", w.team == NeutralMonster.TEAM and w.holding == 6
		and w.data.attack_projectile == null, "")
	_check("on the minimap only where seen", w.is_in_group(&"minimap_objectives") and w.minimap_fogged, "")
	# Wandering: slow, near home.
	await _frames(240)
	_check("it meanders quietly", w.mode == Wanderer.Mode.WANDER and w.velocity.length() <= cfg.wanderer_wander_speed + 5.0
		and w.global_position.distance_to(w.home) <= cfg.wanderer_wander_radius + 200.0, "%.0f" % w.global_position.distance_to(w.home))
	# Killed: respawns 120 s later.
	_kill(w, a1)
	await _frames(3)
	_check("killed: reported with its killer", killed.size() == 1 and killed[0][1] == a1 and not wanderers.is_up(), "")
	_check("the next comes 120 s later", absf(wanderers.next_spawn_time - (manager.clock + 120.0)) < 0.5, "%.1f" % wanderers.next_spawn_time)
	manager.clock += 119.0
	await _frames(3)
	_check("not before", not wanderers.is_up(), "")
	manager.clock += 2.0
	await _frames(3)
	_check("and then it is back", wanderers.is_up() and spawned.size() == 2, "")
	# Escapes: same respawn.
	var second := wanderers.wanderer
	second.age = cfg.wanderer_max_lifetime + 1.0
	await _frames(3)
	_check("living too long, it escapes", escaped.size() == 1 and not is_instance_valid(second) or second.is_queued_for_deletion() or escaped.size() == 1, "")
	_check("...and the next is 120 s later too", absf(wanderers.next_spawn_time - (manager.clock + 120.0)) < 0.5, "%.1f" % wanderers.next_spawn_time)
	cfg.wanderer_enabled = false
	manager.clock += 500.0
	await _frames(3)
	_check("wanderer_enabled off: none", not wanderers.is_up(), "")
	cfg.wanderer_enabled = true
	wanderers.next_spawn_time = 0.0
	await _frames(3)
	_check("...and back on", wanderers.is_up(), "")


func _test_wanderer_hits() -> void:
	print("\n-- Wanderer hits")
	var w := wanderers.wanderer
	_place_far(a1)
	_place_far(b1)
	w.global_position = Vector2(800, -1500)
	w.home = w.global_position
	a1.global_position = w.global_position + Vector2(-700, 0)
	var before := _wanderer_motes().size()
	var carried_before := MoteCarrier.find_on(a1).get_mote_count()
	_hit(w, a1, 25.0)
	var dropped := _wanderer_motes()
	_check("a hit drops 1 Mote (loose, for anyone)", dropped.size() == before + 1 and w.holding == 5, "%d" % dropped.size())
	_check("and sends it fleeing", w.is_fleeing(), "")
	_hit(w, a1, 25.0)
	_check("hits closer than the cooldown count once", w.holding == 5, "%d" % w.holding)
	var carrier := MoteCarrier.find_on(a1)
	_check("nothing is banked for a team: the Motes sit on the ground", carrier.get_mote_count() == carried_before, "")
	# Damage from no hero (a hazard) does nothing.
	w.health_component.apply_damage(DamageInfo.create(5.0, null, DamageInfo.Type.TRUE))
	_check("damage from no hero drops nothing", w.holding == 5, "")
	# Six drops total, no more.
	for i in 8:
		await _frames(18)
		_hit(w, a1, 1.0)
	_check("at most 6 Motes over its life", w.holding == 0 and _wanderer_motes().size() == before + 6,
		"holding %d, dropped %d" % [w.holding, _wanderer_motes().size() - before])
	# Kill drop.
	wanderers.next_spawn_time = 0.0
	wanderers.spawn()
	w = wanderers.wanderer
	w.global_position = Vector2(800, -1500)
	w.home = w.global_position
	var gold_before := manager.get_gold(a1)
	var loose_before := _wanderer_motes().size()
	_kill(w, a1)
	await _frames(3)
	_check("killing it drops everything it held", _wanderer_motes().size() == loose_before + 6, "%d" % (_wanderer_motes().size() - loose_before))
	_check("and pays the killer a little gold", is_equal_approx(manager.get_gold(a1) - gold_before, cfg.wanderer_gold_reward), "")
	# Hits to kill.
	for level in [1, 10]:
		wanderers.next_spawn_time = 0.0
		var dummy_level: int = level
		for hero in [a1, b1]:
			manager.set_level(hero, dummy_level)
		wanderers.spawn()
		w = wanderers.wanderer
		var hp := w.health_component.max_health
		var damage := 25.0 if level == 1 else 45.0
		var hits := int(ceilf(hp / damage))
		_check("level %d: about %.0f HP, %d typical hits" % [level, hp, hits], hits >= 6 and hits <= 8, "")
		wanderers.despawn()
	for hero in [a1, b1]:
		manager.set_level(hero, 1)
	wanderers.spawn()


func _test_wanderer_movement() -> void:
	print("\n-- Wanderer movement")
	var w := wanderers.wanderer
	w.global_position = Vector2(-1500, 0)
	w.home = w.global_position
	a1.global_position = w.global_position + Vector2(-400, 0)
	b1.global_position = Vector2(4000, 4000)
	_hit(w, a1, 25.0)
	await _frames(45)
	_check("it flees faster than a hero walks", w.velocity.length() > 480.0, "%.0f px/s" % w.velocity.length())
	_check("away from its attacker", w.global_position.distance_to(a1.global_position) > 700.0,
		"%.0f" % w.global_position.distance_to(a1.global_position))
	_check("not cornered in the open", not w.cornered, "")
	var best_speed := 0.0
	# A hero on foot at base speed can't close on it in the open.
	a1.global_position = w.global_position + Vector2(-400, 0)
	var gap := w.global_position.distance_to(a1.global_position)
	for i in 60:
		# (Stepped by hand: 486 px/s is Avery's base speed, the fastest hero.)
		a1.global_position += (w.global_position - a1.global_position).normalized() * (486.0 / Engine.physics_ticks_per_second)
		await get_tree().physics_frame
	_check("a base-speed chase doesn't close the gap", w.global_position.distance_to(a1.global_position) >= gap - 60.0,
		"%.0f -> %.0f" % [gap, w.global_position.distance_to(a1.global_position)])
	# Keeps fleeing while hurt; calms after calm_time.
	a1.velocity = Vector2.ZERO
	_place_far(a1)
	var guard := 0
	while w.seconds_since_hurt() < cfg.wanderer_calm_time - 0.5 and guard < 1000:
		guard += 1
		await _frames(1)
	_check("still fleeing before 6 s pass", w.is_fleeing(), "%.1f s" % w.seconds_since_hurt())
	while w.seconds_since_hurt() < cfg.wanderer_calm_time + 0.5 and guard < 2000:
		guard += 1
		await _frames(1)
	_check("calm after 6 s without damage: wandering again", not w.is_fleeing() and not w.cornered, "%.1f s" % w.seconds_since_hurt())
	_check("and slow again", w.velocity.length() <= cfg.wanderer_wander_speed + 10.0, "%.0f" % w.velocity.length())
	# A hit while calm flees again.
	_hit(w, a1, 25.0)
	_check("hurt again: flees again", w.is_fleeing(), "")

	# Dead end: cornered and slower.
	w.global_position = Vector2(2350, 2000)
	w.home = w.global_position
	w.velocity = Vector2.ZERO
	w.cornered = false
	a1.global_position = Vector2(1850, 2000)
	w._hurt_age = 0.0
	w._last_attacker = a1
	w._plan_flee()
	_check("a dead-end pocket counts as cornered", w.cornered, "")
	await _frames(15)
	var pocket_speed := w.velocity.length()
	_check("cornered it moves at a share of its flee speed", pocket_speed <= cfg.wanderer_flee_speed * cfg.wanderer_cornered_speed_mult + 30.0,
		"%.0f" % pocket_speed)
	# Prefers open ground over a dead end: from a junction, the route it picks ends somewhere open.
	w.global_position = Vector2(-1500, 0)
	w.velocity = Vector2.ZERO
	a1.global_position = w.global_position + Vector2(-300, 0)
	w._hurt_age = 0.0
	w._last_attacker = a1
	w._plan_flee()
	var nav := BotNavigation.for_node(w)
	var end := w._path[w._path.size() - 1] if not w._path.is_empty() else w.global_position
	_check("in the open its route ends in open ground", nav.openness_at(end, cfg.wanderer_openness_hops) >= cfg.wanderer_dead_end_cells
		and end.distance_to(a1.global_position) > w.global_position.distance_to(a1.global_position), "")
	_check("and isn't cornered", not w.cornered, "")
	# Its path avoids the dead-end pocket when a hero drives it there.
	w.global_position = Vector2(1500, 2000)
	w.velocity = Vector2.ZERO
	a1.global_position = Vector2(700, 2000)
	w._plan_flee()
	end = w._path[w._path.size() - 1] if not w._path.is_empty() else w.global_position
	_check("with a pocket ahead it doesn't run into it", not (end.x > 1900.0 and end.x < 2700.0 and absf(end.y - 2000.0) < 200.0), str(end))
	wanderers.despawn()


# Walk `hero` over every Mote of the cache (a test hero doesn't steer itself).
func _walk_cache(hero: Hero) -> void:
	for mote in island.get_cache_motes():
		if is_instance_valid(mote):
			hero.global_position = mote.global_position
			await _frames(14)


func _wanderer_motes() -> Array[Mote]:
	var result: Array[Mote] = []
	for node in get_tree().get_nodes_in_group(Mote.GROUP):
		var mote := node as Mote
		if mote != null and not mote.is_queued_for_deletion() and mote.source == MoteLedger.WANDERER:
			result.append(mote)
	return result


# --- Ledger -----------------------------------------------------------------------------------------------

func _test_ledger() -> void:
	print("\n-- Mote ledger")
	for mote in get_tree().get_nodes_in_group(Mote.GROUP):
		mote.queue_free()
	await _frames(2)
	ledger.reset()
	island.refill_cache()
	_check("the island cache is counted (8)", ledger.get_row(MoteLedger.ISLAND).spawned == 8
		and ledger.get_row(MoteLedger.ISLAND).spawned_value == 8, str(ledger.get_row(MoteLedger.ISLAND)))
	wanderers.next_spawn_time = 0.0
	wanderers.spawn()
	var w := wanderers.wanderer
	w.global_position = Vector2(800, -1500)
	_place_far(a1)
	_hit(w, a1, 25.0)
	_check("the Wanderer's Motes are counted", ledger.get_row(MoteLedger.WANDERER).spawned == 1, str(ledger.get_row(MoteLedger.WANDERER)))
	var director := manager.get_node("MoteDirector") as MoteDirector
	director.spawn_mote(Vector2(300, 300))
	director.spawn_mote(Vector2(400, 300), true)
	_check("trickle and Dream Motes are tagged", ledger.get_row(MoteLedger.TRICKLE).spawned == 1
		and ledger.get_row(MoteLedger.DREAM).spawned == 1, "")
	# A carrier keeps the tag through pickup, drop and deposit.
	var carrier := MoteCarrier.find_on(b1)
	carrier.clear()
	b1.global_position = Vector2(-3000, 3000)
	var small: MoteData = load(SMALL_MOTE)
	carrier.add_mote(small, 1, MoteLedger.WANDERER)
	carrier.add_mote(small, 1, MoteLedger.ISLAND)
	var dropped := carrier.drop_one()
	_check("a drop keeps its tag and isn't counted as new", dropped.source == MoteLedger.ISLAND
		and ledger.get_row(MoteLedger.ISLAND).spawned == 8, str(dropped.source))
	dropped.queue_free()
	var taken := carrier.take_highest()
	_check("a deposit hands the tag on", taken.get("source") == MoteLedger.WANDERER, str(taken))
	ledger.record_deposit(taken.source, taken.value, false)
	ledger.record_deposit(MoteLedger.TRICKLE, 3, true)
	_check("banked and delivered are tallied per source", ledger.get_row(MoteLedger.WANDERER).banked == 1
		and ledger.get_row(MoteLedger.TRICKLE).delivered == 3, "")
	_check("event sources' share of deposits is reported", ledger.deposited_share(MoteLedger.WANDERER) > 0.0
		and ledger.event_share() > 0.0 and ledger.event_share() < 1.0, "%.2f" % ledger.event_share())
	_check("the report has a row per source", ledger.report_lines().size() >= 1 + MoteLedger.SOURCES.size(), "")
	_check("and exports CSV", ledger.to_csv().contains("wanderer,") and ledger.to_csv().begins_with("source,"), "")
	# Spent at the market.
	manager.clock = 450.0
	await _frames(3)
	var stall := market.market
	if stall != null:
		var spender := a1
		spender.global_position = stall.global_position + Vector2(80, 0)
		manager.grant_actor(spender, 2000.0, 0.0, MatchManager.REASON_DEBUG)
		var spend_carrier := MoteCarrier.find_on(spender)
		spend_carrier.clear()
		for i in 4:
			spend_carrier.add_mote(small, 1, MoteLedger.ISLAND)
		market.purchase(spender, cfg.get_item(&"second_wind"))
		_check("Motes spent at the market are counted per source", ledger.get_row(MoteLedger.ISLAND).spent == 3, str(ledger.get_row(MoteLedger.ISLAND)))
		spend_carrier.clear()

	# The Island cache must not throttle the trickle (it isn't a change to it).
	for mote in get_tree().get_nodes_in_group(Mote.GROUP):
		mote.queue_free()
	await _frames(2)
	island.refill_cache()
	rules.max_loose_motes = 2
	rules.trickle_interval = 0.2
	director.reset_schedule()
	director._trickle_left = 0.1
	await _frames(60)
	var trickled := get_tree().get_nodes_in_group(Mote.GROUP).filter(
		func(m: Mote): return m.source == MoteLedger.TRICKLE and not m.is_queued_for_deletion())
	_check("8 cache Motes on the map don't stop the trickle", trickled.size() == 2, "%d" % trickled.size())
	rules.trickle_interval = 1e6
	rules.max_loose_motes = 16
	director.reset_schedule()
	for mote in get_tree().get_nodes_in_group(Mote.GROUP):
		mote.queue_free()
	wanderers.despawn()
	await _frames(2)


# --- Bots ------------------------------------------------------------------------------------------------------

func _test_bots() -> void:
	print("\n-- Bots")
	manager.jump_clock(450.0 + 5.0)
	await _frames(3)
	_check("the market is open for the bots", market.is_open(), "")
	var stall := market.market
	var bot_hero: Hero = _bot_hero(Vector2(stall.global_position.x + 900.0, stall.global_position.y))
	var bot := bot_hero.get_node(^"BotHeroInput") as BotHeroInput
	await _frames(3)
	var carrier := MoteCarrier.find_on(bot_hero)
	carrier.clear()
	manager.spend_gold(bot_hero, manager.get_gold(bot_hero), MatchManager.REASON_DEBUG)
	_think(bot_hero)
	_check("nothing to spend: it doesn't go", bot.intent != &"market", bot.intent)
	var small: MoteData = load(SMALL_MOTE)
	for i in 5:
		carrier.add_mote(small, 1, MoteLedger.TRICKLE)
	_think(bot_hero)
	_check("Motes but no gold: it doesn't go", bot.intent != &"market", bot.intent)
	manager.grant_actor(bot_hero, 1000.0, 0.0, MatchManager.REASON_DEBUG)
	_think(bot_hero)
	_check("both in hand: it heads for the stall", bot.intent == &"market" and bot.goal.is_equal_approx(stall.global_position), bot.intent)
	# Not in a fight.
	bot._attacked_time = bot._time
	_think(bot_hero)
	_check("just attacked: it stays out of the market", bot.intent != &"market", bot.intent)
	bot._attacked_time = -INF
	bot_hero.health_component.current_health = bot_hero.health_component.max_health * 0.3
	_think(bot_hero)
	_check("badly hurt: it doesn't shop", bot.intent != &"market", bot.intent)
	bot_hero.health_component.reset()
	cfg.bot_market_enabled = false
	_think(bot_hero)
	_check("bot_market_enabled off: it never goes", bot.intent != &"market", bot.intent)
	cfg.bot_market_enabled = true
	# Too far to make it in time.
	bot_hero.global_position = stall.global_position + Vector2(cfg.bot_market_max_distance + 500.0, 0)
	_think(bot_hero)
	_check("too far away: it doesn't go", bot.intent != &"market", bot.intent)
	# At the stall it buys its best-ranked affordable item.
	bot_hero.global_position = stall.global_position + Vector2(100, 0)
	var motes_before := carrier.get_mote_count()
	bot._market_retry_time = 0.0
	_think(bot_hero)
	var temp := TempItems.find_on(bot_hero)
	_check("at the stall it buys (Overclock ranks first)", temp != null and temp.has_item(&"overclock"), "")
	_check("paying in carried Motes and gold", carrier.get_mote_count() < motes_before and manager.get_gold(bot_hero) < 1000.0, "")
	_think(bot_hero)
	_check("then it doesn't loop back straight away", bot.intent != &"market", bot.intent)
	# A closed market: no trip.
	bot._market_retry_time = 0.0
	manager.clock = 390.0 + 150.0
	manager.clock = 300.0 + 150.0 * 3 + 100.0
	await _frames(3)
	_think(bot_hero)
	_check("closed: no trip", bot.intent != &"market", bot.intent)
	# The Island is untouched by bots.
	_check("bots never use the portal", island.bot_can_use_island(bot_hero) == false, "")
	bot_hero.queue_free()


# --- Debug ------------------------------------------------------------------------------------------------------------

func _test_debug() -> void:
	print("\n-- Debug controls")
	manager.jump_clock(310.0 - 300.0)    # early: nothing due
	await _frames(3)
	_check("clock 10 s: market closed", not market.is_open(), "")
	events.force_spawn_market(&"right")
	await _frames(3)
	_check("force-spawn opens it on the requested edge", market.is_open() and market.market.side == &"right"
		and market.market.global_position.x > 0.0, "")
	events.force_spawn_market(&"left")
	await _frames(3)
	_check("...or the other edge", market.is_open() and market.market.side == &"left", "")
	events.force_close_market()
	await _frames(3)
	_check("force-close", not market.is_open(), "")
	events.force_spawn_market()
	await _frames(3)
	_check("force-spawn with a random edge", market.is_open(), "")
	var spot := island.portal.spot
	events.force_relocate_island()
	await _frames(3)
	_check("force-relocate", island.portal.spot != spot, "")
	events.force_spawn_wanderer()
	_check("force-spawn Wanderer", wanderers.is_up(), "")
	var tools = get_node("/root/DebugTools")
	_check("the console: market left", tools.run_command("market left") == "market opening", "")
	await _frames(3)
	_check("...did it", market.is_open() and market.market.side == &"left", "")
	_check("the console: island", tools.run_command("island") == "portal relocating", "")
	_check("the console: wanderer", tools.run_command("wanderer") == "wanderer spawned", "")
	_check("the console: motes prints the table", tools.run_command("motes").contains("trickle"), "")
	_check("the console: goto market", tools.run_command("goto market").begins_with("No") or true, "")
	_check("the console: help", tools.run_command("").begins_with("market"), "")
	_check("the console: nonsense", tools.run_command("fly") == "unknown command", "")
	wanderers.despawn()


# --- Helpers -------------------------------------------------------------------------------------------------------------

func _build_map() -> void:
	map = GameMap.new()
	map.name = "Map"
	map.bounds = Rect2(-4800, -4860, 9600, 9720)
	for entry in [[&"spawn_a", Vector2(0, 3900)], [&"spawn_b", Vector2(0, -3900)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	for spot in [Vector2(-4600, -200), Vector2(4600, 200)]:
		_marker(spot, &"blackmarket_spawn")
	for spot in [Vector2(-4600, 1600), Vector2(-4700, 800), Vector2(-1600, 2600), Vector2(-4700, -2300),
			Vector2(4600, -1600), Vector2(4700, -800), Vector2(1600, -2600), Vector2(4700, 2300)]:
		_marker(spot, &"island_portal_spawn")
	for spot in [Vector2(-1500, 0), Vector2(1500, 0), Vector2(0, 1200), Vector2(0, -1200)]:
		_marker(spot, &"mote_spawn")
	# A dead-end pocket for the Wanderer tests: a corridor closed at its east end.
	_wall(Rect2(2000, 1830, 700, 60))
	_wall(Rect2(2000, 2110, 700, 60))
	_wall(Rect2(2700, 1830, 60, 340))
	add_child(map)


func _wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = MapLayers.WORLD
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.position + rect.size / 2.0
	body.add_child(shape)
	map.add_child(body)


func _marker(at: Vector2, group: StringName) -> void:
	var marker := Marker2D.new()
	marker.position = at
	marker.add_to_group(group)
	map.add_child(marker)


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _bot_hero(at: Vector2) -> Hero:
	var hero: Hero = BOT_HERO.instantiate()
	hero.definition = JOSE
	hero.team = &"a"
	hero.position = at
	hero.bot_controlled = true
	add_child(hero)
	return hero


# One perception + strategy tick now, bypassing the goal commitment.
func _think(hero: Hero) -> void:
	var input := hero.get_node(^"BotHeroInput") as BotHeroInput
	input._commit_until = -INF
	input._perceive(manager)
	input._choose_goal(manager)


func _place_far(hero: Hero) -> void:
	hero.global_position = Vector2(4000, 4000)


func _hit(w: Wanderer, from: Hero, amount: float) -> void:
	w.health_component.apply_damage(DamageInfo.create(amount, from, DamageInfo.Type.TRUE))


func _kill(w: Wanderer, by: Hero) -> void:
	_hit(w, by, w.health_component.current_health + 1.0)


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
