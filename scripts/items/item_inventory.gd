extends Node
class_name ItemInventory

# A hero's items in a match (MatchManager adds one to every hero it
# registers, next to the UltimateCharge). It buys and sells through the
# MatchManager's gold, and applies each item:
#
#   stat_modifiers    added to the StatsComponent, tagged with the owned
#                     copy's source id (so selling one of two copies
#                     removes only its own)
#   stat_multipliers  StatusEffectComponent persistent multipliers (they
#                     survive deaths and cleanses)
#   active_ability    built into the AbilityController's "item" slot
#                     (MatchRules.active_item_slot), like any other slot
#
# Rules (MatchRules, group Shop): up to item_slots passive items and
# max_active_items active ones; buying only where can_shop() allows it (your
# base's Shop, or anywhere while dead); an item that builds_from one you own
# costs that much less and uses it up; selling refunds sell_refund_pct.
#
# The reason strings ("Not enough gold" ...) are what the shop panel shows.
# Cues (match profiles, or the hero's own): item_bought, item_sold.

signal items_changed
signal item_bought(item: ItemData)
signal item_sold(item: ItemData, refund: int)

const NODE_NAME := "ItemInventory"

var hero: Hero
var manager: MatchManager


class Owned:
	var item: ItemData
	var source_id: StringName
	var modifiers: Array[StatModifier] = []
	var ability: Ability


# Owned, in purchase order.
var _owned: Array[Owned] = []
static var _serial: int = 1


static func find_on(node: Node) -> ItemInventory:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null(NODE_NAME) as ItemInventory


func _ready() -> void:
	hero = get_parent() as Hero
	if manager == null and is_inside_tree():
		manager = MatchManager.find(get_tree())


func get_rules() -> MatchRules:
	return manager.get_rules() if manager != null else MatchRules.current()


func get_catalog() -> ShopCatalog:
	return get_rules().shop_catalog


# --- Queries ------------------------------------------------------------------

func get_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for owned in _owned:
		result.append(owned.item)
	return result


func get_passive_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for owned in _owned:
		if not owned.item.is_active():
			result.append(owned.item)
	return result


func get_active_item() -> ItemData:
	for owned in _owned:
		if owned.item.is_active():
			return owned.item
	return null


## The ability the active item put in its slot, or null.
func get_active_ability() -> Ability:
	for owned in _owned:
		if owned.ability != null:
			return owned.ability
	return null


func has_item(item: ItemData) -> bool:
	return _find(item) != null


## Owned, or used up into an item you own (Pillow Fort counts as having
## had its Cozy Blanket).
func is_built(item: ItemData) -> bool:
	for owned in _owned:
		var step := owned.item
		while step != null:
			if step == item:
				return true
			step = step.builds_from
	return false


## The next item of `build` (a purchase order, components first) not yet
## built, skipping ones that can never fit (a second active item). null =
## the build is done. It may still be unaffordable: check can_buy().
func get_next_in_build(build: Array[ItemData]) -> ItemData:
	for item in build:
		if item == null or is_built(item):
			continue
		var reason := get_buy_block_reason(item)
		if reason == "Inventory full" or reason == "One active item only" or reason == "Not sold here":
			continue
		return item
	return null


## Buy as far down `build` as the gold allows (bots). Stops at the first
## item it can't afford, so it saves up for it instead of skipping ahead.
## Returns what it bought.
func buy_from_build(build: Array[ItemData], max_purchases: int = 6) -> Array[ItemData]:
	var bought: Array[ItemData] = []
	for i in max_purchases:
		var next := get_next_in_build(build)
		if next == null or not buy(next):
			break
		bought.append(next)
	return bought


func count_of(item: ItemData) -> int:
	return _owned.filter(func(o: Owned): return o.item == item).size()


func get_gold() -> float:
	return manager.get_gold(hero) if manager != null else 0.0


## Gold `item` costs this hero right now: its cost minus an owned component.
func price_of(item: ItemData) -> int:
	if item == null:
		return 0
	var price := item.cost
	if item.builds_from != null and has_item(item.builds_from):
		price -= item.builds_from.cost
	return maxi(price, 0)


func sell_value_of(item: ItemData) -> int:
	return floori(item.cost * get_rules().sell_refund_pct) if item != null else 0


## "" if the shop is reachable (in base, or dead), else why not.
func get_shop_block_reason() -> String:
	if manager == null:
		return "No match"
	return manager.get_shop_block_reason(hero)


func can_shop() -> bool:
	return get_shop_block_reason() == ""


## "" if `item` can be bought right now, else why not.
func get_buy_block_reason(item: ItemData) -> String:
	if item == null:
		return "No item"
	var shop_reason := get_shop_block_reason()
	if shop_reason != "":
		return shop_reason
	var catalog := get_catalog()
	if catalog != null and not catalog.items.has(item):
		return "Not sold here"
	var rules := get_rules()
	var uses_component := item.builds_from != null and has_item(item.builds_from)
	if item.is_active():
		var actives := _owned.filter(func(o: Owned): return o.item.is_active()).size()
		if uses_component and item.builds_from.is_active():
			actives -= 1
		if actives >= rules.max_active_items:
			return "One active item only"
	else:
		var passives := get_passive_items().size()
		if uses_component and not item.builds_from.is_active():
			passives -= 1
		if passives >= rules.item_slots:
			return "Inventory full"
	if get_gold() + 0.001 < price_of(item):
		return "Not enough gold"
	return ""


func can_buy(item: ItemData) -> bool:
	return get_buy_block_reason(item) == ""


func get_sell_block_reason(item: ItemData) -> String:
	if not has_item(item):
		return "Not owned"
	return get_shop_block_reason()


# --- Buying and selling ----------------------------------------------------------

## Pay for and equip `item`. Returns false (and changes nothing) if
## get_buy_block_reason() isn't empty.
func buy(item: ItemData) -> bool:
	if not can_buy(item):
		return false
	var price := price_of(item)
	if item.builds_from != null and has_item(item.builds_from):
		_unequip(_find(item.builds_from))
	manager.spend_gold(hero, price, MatchManager.REASON_SHOP)
	_equip(item)
	manager.play_match_cue(hero, &"item_bought", {"item": item.id})
	item_bought.emit(item)
	items_changed.emit()
	return true


## Sell one copy of `item` for sell_refund_pct of its cost.
func sell(item: ItemData) -> bool:
	if get_sell_block_reason(item) != "":
		return false
	var refund := sell_value_of(item)
	_unequip(_find(item))
	manager.grant_actor(hero, refund, 0.0, MatchManager.REASON_SHOP)
	manager.play_match_cue(hero, &"item_sold", {"item": item.id})
	item_sold.emit(item, refund)
	items_changed.emit()
	return true


## Equip without paying or any shop rule (tests, debug, a future reward).
func give(item: ItemData) -> void:
	if item == null:
		return
	_equip(item)
	items_changed.emit()


## Remove every item without a refund (debug).
func clear() -> void:
	for owned in _owned.duplicate():
		_unequip(owned)
	items_changed.emit()


func _find(item: ItemData) -> Owned:
	for owned in _owned:
		if owned.item == item:
			return owned
	return null


func _equip(item: ItemData) -> void:
	var owned := Owned.new()
	owned.item = item
	owned.source_id = StringName("item:%s:%d" % [item.id, _serial])
	_serial += 1
	for modifier in item.stat_modifiers:
		if modifier == null:
			continue
		var copy := modifier.duplicate() as StatModifier
		copy.source_id = owned.source_id
		owned.modifiers.append(copy)
	if not owned.modifiers.is_empty():
		hero.stats_component.add_modifiers(owned.modifiers)
	if not item.stat_multipliers.is_empty():
		hero.status_component.set_persistent_multipliers(owned.source_id, item.stat_multipliers)
	if item.active_ability != null:
		owned.ability = _build_active(item)
	_owned.append(owned)


func _unequip(owned: Owned) -> void:
	if owned == null:
		return
	_owned.erase(owned)
	# Losing max HP from a sale clamps current HP; it never grants any.
	hero.stats_component.remove_modifiers_from(owned.source_id, false)
	hero.status_component.remove_persistent_multipliers(owned.source_id)
	if owned.ability != null and is_instance_valid(owned.ability):
		hero.ability_controller.remove_ability(owned.ability)


func _build_active(item: ItemData) -> Ability:
	var data := item.active_ability
	if data.ability_script == null:
		push_warning("Active item '%s' has no ability script" % item.id)
		return null
	var ability: Ability = data.ability_script.new()
	var slot_id := get_rules().active_item_slot
	var slot := GameRules.current().get_slot(slot_id)
	ability.name = "Item%s" % str(item.id).to_pascal_case()
	ability.input_action = slot.input_action if slot != null else &""
	ability.set_data(data.duplicate_deep(Resource.DEEP_DUPLICATE_ALL))
	hero.ability_controller.add_ability(ability, slot_id)
	return ability
