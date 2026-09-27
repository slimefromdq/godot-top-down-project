@tool
extends Resource
class_name ShopCatalog

# Everything the shop sells (resources/items/shop_catalog.tres, set in
# MatchRules.shop_catalog). The shop panel lays it out as one row per
# family, in `families` order, and one column per tier.

@export var items: Array[ItemData] = []
## Row order and titles: family id -> row title. Families not listed come
## after, titled by their id.
@export var families: Dictionary[StringName, String] = {}


func get_item(item_id: StringName) -> ItemData:
	for item in items:
		if item != null and item.id == item_id:
			return item
	return null


## Family ids in display order.
func get_family_order() -> Array[StringName]:
	var order: Array[StringName] = []
	for family in families:
		order.append(family)
	for item in items:
		if item != null and not order.has(item.family):
			order.append(item.family)
	return order


func get_family_title(family: StringName) -> String:
	return families.get(family, str(family).capitalize())


func get_items(family: StringName, tier: int = -1) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in items:
		if item != null and item.family == family and (tier < 0 or item.tier == tier):
			result.append(item)
	return result


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for i in items.size():
		var item := items[i]
		if item == null:
			problems.append("catalog item %d is empty" % (i + 1))
			continue
		if seen.has(item.id):
			problems.append("catalog lists '%s' twice" % item.id)
		seen[item.id] = true
		problems.append_array(item.validate())
		if item.builds_from != null and not items.has(item.builds_from):
			problems.append("'%s' builds from '%s', which the shop doesn't sell" % [item.id, item.builds_from.id])
	return problems
