extends Node
class_name TempItems

# A hero's running Black Market buffs (added on the first grant, like the
# ItemInventory). They take no item slot and are not items: each is a
# TempEffect that ends on its timer or on the hero's death.
#
#   grant(item, seconds)   start one (buying again refreshes it)
#   get_active()           what is running, with time left (the HUD row)
#   clear()                end everything (death, debug)
#
# Signals: changed, granted(item), ended(item, reason).

signal changed
signal granted(item: BlackMarketItem)
signal ended(item: BlackMarketItem, reason: StringName)

const NODE_NAME := "TempItems"
const END_EXPIRED := &"expired"
const END_DEATH := &"death"
const END_CLEARED := &"cleared"
const END_REFRESHED := &"refreshed"

var hero: Hero
var _running: Array[TempEffect] = []
var _left: Dictionary = {}    # TempEffect -> seconds left


static func find_on(node: Node) -> TempItems:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null(NODE_NAME) as TempItems


## The hero's TempItems, made if it has none yet.
static func ensure_on(hero: Hero) -> TempItems:
	var existing := find_on(hero)
	if existing != null:
		return existing
	var made := TempItems.new()
	made.name = NODE_NAME
	hero.add_child(made)
	return made


func _ready() -> void:
	hero = get_parent() as Hero
	if hero != null:
		hero.health_component.died.connect(_on_died)


func has_item(id: StringName) -> bool:
	return _find(id) != null


func get_time_left(id: StringName) -> float:
	var effect := _find(id)
	return float(_left.get(effect, 0.0)) if effect != null else 0.0


func get_active() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for effect in _running:
		rows.append({"item": effect.item, "left": float(_left.get(effect, 0.0)), "duration": effect.duration})
	return rows


func get_active_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for effect in _running:
		ids.append(effect.item.id)
	return ids


## Start `item` on the hero for `seconds` (<= 0: the item's own / the rules'
## default). Granting one already running restarts it. Returns the effect.
func grant(item: BlackMarketItem, seconds: float = -1.0) -> TempEffect:
	if item == null or hero == null or hero.health_component.is_dead():
		return null
	if seconds <= 0.0:
		var manager := MatchManager.find(get_tree())
		var rules := manager.get_rules().map_events if manager != null else MatchRules.current().map_events
		seconds = rules.item_duration(item) if rules != null else maxf(item.duration, 60.0)
	var again := _find(item.id)
	if again != null:
		_end(again, END_REFRESHED)
	var effect := item.make_effect()
	effect.start(hero, item, seconds)
	granted.emit(item)
	if effect.is_instant():
		# Nothing to keep running.
		effect.stop()
		ended.emit(item, END_EXPIRED)
	else:
		_running.append(effect)
		_left[effect] = effect.total_time()
	changed.emit()
	return effect


func clear(reason: StringName = END_CLEARED) -> void:
	for effect in _running.duplicate():
		_end(effect, reason)
	changed.emit()


func _physics_process(delta: float) -> void:
	if _running.is_empty():
		return
	var any_ended := false
	for effect in _running.duplicate():
		_left[effect] = float(_left[effect]) - delta
		effect.tick(delta)
		if float(_left[effect]) <= 0.0 or effect.is_finished():
			_end(effect, END_EXPIRED)
			any_ended = true
	if any_ended:
		changed.emit()


func _on_died() -> void:
	if not _running.is_empty():
		clear(END_DEATH)


func _end(effect: TempEffect, reason: StringName) -> void:
	if not _running.has(effect):
		return
	_running.erase(effect)
	_left.erase(effect)
	effect.stop()
	ended.emit(effect.item, reason)


func _find(id: StringName) -> TempEffect:
	for effect in _running:
		if effect.item.id == id:
			return effect
	return null
