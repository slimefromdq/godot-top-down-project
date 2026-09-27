extends Node2D

# Headless checks for items and shops: the catalog (3 families x 3 tiers,
# rising prices, every item valid), buying (gold spent, stats and fire rate
# applied, the shop reach rule: in base or dead only), build paths (a
# component comes off the price and is used up), selling (refund, stats
# restored, max HP never granted back), the slot limits (inventory full, one
# active item), active items (the ability lands in the "item" slot, casts,
# and leaves when sold), items surviving death, cooldown_rate, the Dream
# Mote's value and Dream Basin's shops.
#
#   godot --headless res://tools/match/items_test.tscn
#
# Exits with the number of failed checks (0 = all passed).

const HERO := "res://tools/heroes/ranged_test/ranged_test_hero.tscn"
const CATALOG := "res://resources/items/shop_catalog.tres"
const DREAM_BASIN := "res://scenes/maps/dream_basin.tscn"

var failures := 0
var manager: MatchManager
var rules: MatchRules
var catalog: ShopCatalog
var map: GameMap
var shop: Shop
var a1: Hero
var b1: Hero


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	catalog = load(CATALOG)
	_build_map()
	rules = MatchRules.current().duplicate()
	rules.warmup_time = 0.0
	rules.passive_gold_per_second = 0.0
	rules.passive_xp_per_second = 0.0
	rules.objectives_enabled = false
	rules.trickle_interval = 1000.0
	rules.zone_first_time = 1e6
	rules.dream_mote_first_time = 1e6
	manager = MatchManager.new()
	manager.rules = rules
	manager.auto_start = false
	add_child(manager)
	a1 = _hero(&"a", Vector2(0, 2000))
	b1 = _hero(&"b", Vector2(0, -2000))
	await _frames(3)
	manager.start_warmup()
	await _frames(2)

	_test_catalog()
	await _test_shop_reach()
	_test_buy_and_stats()
	_test_build_path()
	_test_sell()
	_test_limits()
	await _test_active_item()
	await _test_death_keeps_items()
	await _test_cooldown_rate()
	_test_dream_mote_value()
	await _test_dream_basin_shops()

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(failures)


func _test_catalog() -> void:
	print("\n-- Catalog")
	_check("catalog is valid", catalog.validate().is_empty(), str(catalog.validate()))
	_check("MatchRules uses the catalog", MatchRules.current().shop_catalog == catalog, "")
	for family in [&"health", &"fire_rate", &"magic"]:
		var tiers: Array = []
		for tier in 3:
			var items := catalog.get_items(family, tier)
			tiers.append(items[0] if items.size() == 1 else null)
		var complete := not tiers.has(null)
		_check("%s has one item per tier" % family, complete, "")
		if not complete:
			continue
		_check("%s prices rise with tier" % family, tiers[0].cost < tiers[1].cost and tiers[1].cost < tiers[2].cost,
			"%d / %d / %d" % [tiers[0].cost, tiers[1].cost, tiers[2].cost])
		_check("%s tiers build from the one below" % family,
			tiers[1].builds_from == tiers[0] and tiers[2].builds_from == tiers[1], "")
		_check("%s: more cost, more buffs" % family,
			tiers[0].describe_stats().size() <= tiers[1].describe_stats().size()
			and tiers[1].describe_stats().size() <= tiers[2].describe_stats().size(),
			"%s | %s | %s" % [tiers[0].describe_stats(), tiers[1].describe_stats(), tiers[2].describe_stats()])
	var actives := catalog.get_items(&"active")
	_check("the shop sells active items", actives.size() >= 1 and actives.all(func(i): return i.is_active()), "")
	_check("the item slot exists and is optional",
		GameRules.current().get_slot(rules.active_item_slot) != null
		and not GameRules.current().get_slot(rules.active_item_slot).required, "")
	_check("every hero gets an inventory", ItemInventory.find_on(a1) != null and ItemInventory.find_on(b1) != null, "")


func _test_shop_reach() -> void:
	print("\n-- Where you can shop")
	var inv := ItemInventory.find_on(a1)
	var blanket := catalog.get_item(&"cozy_blanket")
	_give_gold(a1, 5000)
	a1.global_position = shop.global_position + Vector2(rules.shop_radius - 50.0, 0)
	_check("in reach of your shop: can buy", inv.can_buy(blanket), inv.get_buy_block_reason(blanket))
	a1.global_position = Vector2(3000, 0)
	_check("out in the map: can't", not inv.can_buy(blanket) and inv.get_buy_block_reason(blanket) != "",
		inv.get_buy_block_reason(blanket))
	_check("buy() refuses and keeps the gold", not inv.buy(blanket) and is_equal_approx(manager.get_gold(a1), 5000.0), "")
	a1.global_position = Vector2(0, -2000)    # the enemy's spawn area
	_check("the enemy's spawn area isn't your base", not inv.can_shop(), "")
	a1.global_position = Vector2(0, 2000)    # own spawn area, far from the shop stall
	_check("your own spawn area counts as base", inv.can_shop(), inv.get_shop_block_reason())
	a1.global_position = Vector2(3000, 0)
	a1.health_component.kill()
	await _frames(1)
	_check("dead: can shop from anywhere", inv.can_buy(blanket), inv.get_buy_block_reason(blanket))
	rules.shop_while_dead = false
	_check("...unless shop_while_dead is off", not inv.can_shop(), "")
	rules.shop_while_dead = true
	manager.respawn_now(a1)
	await _frames(1)
	a1.global_position = shop.global_position


func _test_buy_and_stats() -> void:
	print("\n-- Buying applies stats")
	var inv := ItemInventory.find_on(a1)
	_set_gold(a1, 1000)
	var hp_before := a1.stats_component.get_health()
	var current_before := a1.health_component.current_health
	var blanket := catalog.get_item(&"cozy_blanket")
	_check("buy Cozy Blanket", inv.buy(blanket), "")
	_check("gold spent", is_equal_approx(manager.get_gold(a1), 1000.0 - blanket.cost), str(manager.get_gold(a1)))
	_check("+150 max health", is_equal_approx(a1.stats_component.get_health(), hp_before + 150.0),
		"%.0f -> %.0f" % [hp_before, a1.stats_component.get_health()])
	_check("current health gained too", is_equal_approx(a1.health_component.current_health, current_before + 150.0), "")
	var fire_before := a1.status_component.get_multiplier(StatusEffect.FIRE_RATE)
	var gun := a1.get_ranged_ability()
	var interval_before := gun.get_fire_interval() if gun != null else 0.0
	var sugar := catalog.get_item(&"sugar_rush")
	_check("buy Sugar Rush", inv.buy(sugar), "")
	_check("fire rate x1.12", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE), fire_before * 1.12),
		str(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE)))
	if gun != null:
		_check("the gun shoots faster", gun.get_fire_interval() < interval_before,
			"%.3f -> %.3f s" % [interval_before, gun.get_fire_interval()])
	var gold := manager.get_gold(a1)
	var tome := catalog.get_item(&"crown_of_reverie")
	_check("can't afford the Crown", not inv.can_buy(tome) and inv.get_buy_block_reason(tome) == "Not enough gold",
		inv.get_buy_block_reason(tome))
	_check("gold unchanged by a refused buy", is_equal_approx(manager.get_gold(a1), gold), "")


func _test_build_path() -> void:
	print("\n-- Build paths")
	var inv := ItemInventory.find_on(a1)
	var blanket := catalog.get_item(&"cozy_blanket")
	var fort := catalog.get_item(&"pillow_fort")
	var heart := catalog.get_item(&"dreamheart")
	_check("owning the component lowers the price", inv.price_of(fort) == fort.cost - blanket.cost,
		"%d" % inv.price_of(fort))
	_set_gold(a1, inv.price_of(fort))
	var hp_base := a1.stats_component.get_health() - 150.0
	_check("buy Pillow Fort with exactly the reduced price", inv.buy(fort), "")
	_check("the Blanket was used up", not inv.has_item(blanket) and inv.has_item(fort), str(inv.get_items()))
	_check("health is the Fort's, not both", is_equal_approx(a1.stats_component.get_health(), hp_base + 350.0),
		"%.0f" % a1.stats_component.get_health())
	_check("Fort gives armor", is_equal_approx(a1.stats_component.get_stat(StatBlock.ARMOR),
		a1.stats_component.stat_block.value_at(StatBlock.ARMOR, a1.get_level()) + 15.0), "")
	_set_gold(a1, inv.price_of(heart))
	_check("upgrade to Dreamheart", inv.buy(heart), "")
	_check("Dreamheart: +600 and +10% health", is_equal_approx(a1.stats_component.get_health(), (hp_base + 600.0) * 1.1),
		"%.0f" % a1.stats_component.get_health())
	_check("Dreamheart: move speed", a1.status_component.get_multiplier(StatusEffect.MOVE_SPEED) > 1.0, "")


func _test_sell() -> void:
	print("\n-- Selling")
	var inv := ItemInventory.find_on(a1)
	var heart := catalog.get_item(&"dreamheart")
	var sugar := catalog.get_item(&"sugar_rush")
	var gold := manager.get_gold(a1)
	var base_hp := a1.stats_component.stat_block.value_at(StatBlock.HEALTH, a1.get_level())
	a1.health_component.current_health = a1.health_component.max_health * 0.5
	var current := a1.health_component.current_health
	_check("sell Dreamheart", inv.sell(heart), "")
	_check("refund is sell_refund_pct of the full cost",
		is_equal_approx(manager.get_gold(a1), gold + floorf(heart.cost * rules.sell_refund_pct)), str(manager.get_gold(a1)))
	_check("max health back to base", is_equal_approx(a1.stats_component.get_health(), base_hp), "")
	_check("selling never grants health", a1.health_component.current_health <= current + 0.01, "")
	_check("move speed back to 1", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.MOVE_SPEED), 1.0), "")
	inv.sell(sugar)
	_check("fire rate back to 1", is_equal_approx(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE), 1.0), "")
	_check("inventory empty", inv.get_items().is_empty(), str(inv.get_items()))
	a1.global_position = Vector2(3000, 0)
	inv.give(sugar)
	_check("can't sell away from base", not inv.sell(sugar), "")
	a1.global_position = shop.global_position
	inv.clear()


func _test_limits() -> void:
	print("\n-- Slot limits")
	var inv := ItemInventory.find_on(a1)
	var blanket := catalog.get_item(&"cozy_blanket")
	_set_gold(a1, 100000)
	for i in rules.item_slots:
		inv.buy(blanket)
	_check("bought %d passives" % rules.item_slots, inv.get_passive_items().size() == rules.item_slots, "")
	_check("a 7th is refused: inventory full", inv.get_buy_block_reason(blanket) == "Inventory full",
		inv.get_buy_block_reason(blanket))
	var fort := catalog.get_item(&"pillow_fort")
	_check("an upgrade still fits (it uses up its component)", inv.can_buy(fort), inv.get_buy_block_reason(fort))
	var before := a1.stats_component.get_health()
	inv.sell(blanket)
	_check("selling one copy removes only its stats", is_equal_approx(a1.stats_component.get_health(), before - 150.0), "")
	var bubble := catalog.get_item(&"dream_bubble")
	var overdrive := catalog.get_item(&"pocket_overdrive")
	_check("an active item doesn't need a passive slot", inv.buy(bubble), "")
	_check("a second active is refused", inv.get_buy_block_reason(overdrive) == "One active item only",
		inv.get_buy_block_reason(overdrive))
	inv.clear()


func _test_active_item() -> void:
	print("\n-- Active items")
	var inv := ItemInventory.find_on(a1)
	var bubble := catalog.get_item(&"dream_bubble")
	_set_gold(a1, bubble.cost)
	var count := a1.ability_controller.abilities.size()
	_check("slot empty before", a1.get_ability(rules.active_item_slot) == null, "")
	inv.buy(bubble)
	var ability := a1.get_ability(rules.active_item_slot)
	_check("the ability is in the item slot", ability != null and ability == inv.get_active_ability(), "")
	_check("one more ability", a1.ability_controller.abilities.size() == count + 1, "")
	_check("bound to the item key", ability != null and ability.input_action == &"hero_item", "")
	var ok := a1.request_slot(rules.active_item_slot, a1.global_position + Vector2.RIGHT)
	await _frames(4)
	_check("casting it shields you", ok and a1.status_component.get_shield_total() > 0.0,
		"shield %.0f" % a1.status_component.get_shield_total())
	_check("then it's on cooldown", ability.cooldown_remaining > 0.0, "")
	inv.sell(bubble)
	await _frames(1)
	_check("selling removes the ability", a1.get_ability(rules.active_item_slot) == null
		and a1.ability_controller.abilities.size() == count, "")
	var overdrive := catalog.get_item(&"pocket_overdrive")
	_set_gold(a1, overdrive.cost)
	_check("now another active fits", inv.buy(overdrive), "")
	a1.request_slot(rules.active_item_slot, a1.global_position + Vector2.RIGHT)
	await _frames(4)
	_check("Pocket Overdrive speeds up firing", a1.status_component.get_multiplier(StatusEffect.FIRE_RATE) > 1.5, "")
	inv.clear()
	a1.status_component.clear()


func _test_death_keeps_items() -> void:
	print("\n-- Items survive death")
	var inv := ItemInventory.find_on(a1)
	inv.give(catalog.get_item(&"sugar_rush"))
	inv.give(catalog.get_item(&"cozy_blanket"))
	var hp := a1.stats_component.get_health()
	a1.health_component.kill()
	await _frames(1)
	manager.respawn_now(a1)
	await _frames(1)
	_check("fire rate kept through a respawn (statuses cleared)",
		is_equal_approx(a1.status_component.get_multiplier(StatusEffect.FIRE_RATE), 1.12), "")
	_check("health kept", is_equal_approx(a1.stats_component.get_health(), hp)
		and is_equal_approx(a1.health_component.current_health, hp), "")
	inv.clear()


func _test_cooldown_rate() -> void:
	print("\n-- cooldown_rate")
	var ability := a1.get_ability(&"ability_1")
	if ability == null:
		ability = a1.get_ability(&"movement")
	ability.cooldown_remaining = 10.0
	await _frames(30)
	var plain := 10.0 - ability.cooldown_remaining
	var inv := ItemInventory.find_on(a1)
	var crown := catalog.get_item(&"crown_of_reverie")
	inv.give(crown)
	ability.cooldown_remaining = 10.0
	await _frames(30)
	var fast := 10.0 - ability.cooldown_remaining
	_check("Crown of Reverie: cooldowns tick 20% faster", absf(fast / plain - 1.2) < 0.02,
		"%.3f vs %.3f" % [fast, plain])
	_check("Crown of Reverie: +100 Magic", is_equal_approx(a1.stats_component.get_magic(),
		a1.stats_component.stat_block.value_at(StatBlock.MAGIC, a1.get_level()) + 100.0), "")
	inv.clear()
	ability.cooldown_remaining = 0.0


func _test_dream_mote_value() -> void:
	print("\n-- Dream Mote")
	var dream: MoteData = load("res://resources/match/dream_mote.tres")
	_check("the Dream Mote is worth 10", dream.value == 10, str(dream.value))


func _test_dream_basin_shops() -> void:
	print("\n-- Dream Basin")
	var basin: Node = load(DREAM_BASIN).instantiate()
	var shops: Array = basin.find_children("*", "Node2D", true, false).filter(func(n): return n is Shop)
	var teams := shops.map(func(s): return s.team)
	teams.sort()
	_check("one shop per team", teams == [&"a", &"b"], str(teams))
	for s in shops:
		var own_spawns: Array = basin.find_children("*", "Marker2D", true, false).filter(
			func(m): return m.is_in_group(StringName("spawn_%s" % s.team)))
		var near := own_spawns.any(func(m): return m.position.distance_to(s.position) < 1200.0)
		_check("the %s shop sits by its spawn points" % s.team, near, str(s.position))
	basin.free()


# --- Helpers -----------------------------------------------------------------

func _build_map() -> void:
	map = GameMap.new()
	map.name = "Map"
	map.bounds = Rect2(-4000, -4000, 8000, 8000)
	for entry in [[&"spawn_a", Vector2(0, 2000)], [&"spawn_b", Vector2(0, -2000)]]:
		var marker := Marker2D.new()
		marker.position = entry[1]
		marker.add_to_group(entry[0])
		map.add_child(marker)
	shop = Shop.new()
	shop.team = &"a"
	shop.position = Vector2(-2500, 2500)
	map.add_child(shop)
	add_child(map)


func _hero(team: StringName, at: Vector2) -> Hero:
	var hero: Hero = load(HERO).instantiate()
	hero.team = team
	hero.position = at
	add_child(hero)
	return hero


func _give_gold(hero: Hero, amount: float) -> void:
	manager.grant_actor(hero, amount, 0.0, MatchManager.REASON_DEBUG)


func _set_gold(hero: Hero, amount: float) -> void:
	manager.get_record(hero).gold = amount


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
