extends Node
class_name UltimateCharge

# A hero's ultimate charge in a match. The MatchManager adds one to every
# hero in its roster (when MatchRules.ultimate_charge_enabled) and feeds it
# from the match's events: time, damage dealt and taken, healing, kills,
# assists and deposits. Every hero starts empty.
#
# While a hero has one, the abilities in charge-gated slots
# (SlotDefinition.ultimate_charge) ignore their cooldown: they are ready when
# the charge is full, and casting spends all of it (Ability.is_ready /
# _spend_cooldown ask for_ability()). Off the match (training maps, hero
# tests) there is no UltimateCharge and ultimates use their cooldowns.

signal charge_changed(value: float, maximum: float)
## The charge just reached full.
signal filled

const META_KEY := &"ultimate_charge"

var charge: float = 0.0
var maximum: float = 100.0


static func find_on(node: Node) -> UltimateCharge:
	if node != null and is_instance_valid(node) and node.has_meta(META_KEY):
		var found = node.get_meta(META_KEY)
		if is_instance_valid(found):
			return found
	return null


## The charge gating `ability`, or null when it uses its cooldown (not a
## charge-gated slot, or the hero isn't in a charging match).
static func for_ability(ability: Ability) -> UltimateCharge:
	if ability == null or ability.slot_id == &"" or ability.actor == null:
		return null
	var slot := GameRules.current().get_slot(ability.slot_id)
	if slot == null or not slot.ultimate_charge:
		return null
	return find_on(ability.actor)


func _enter_tree() -> void:
	var root := get_parent()
	if root != null:
		root.set_meta(META_KEY, self)


func _exit_tree() -> void:
	var root := get_parent()
	if root != null and root.get_meta(META_KEY, null) == self:
		root.remove_meta(META_KEY)


func get_ratio() -> float:
	return clampf(charge / maximum, 0.0, 1.0) if maximum > 0.0 else 1.0


func is_full() -> bool:
	return Ability.cooldowns_disabled or charge >= maximum


func add(amount: float) -> void:
	if amount <= 0.0 or charge >= maximum:
		return
	charge = minf(charge + amount, maximum)
	charge_changed.emit(charge, maximum)
	if charge >= maximum:
		filled.emit()


func set_charge(value: float) -> void:
	var was_full := charge >= maximum
	charge = clampf(value, 0.0, maximum)
	charge_changed.emit(charge, maximum)
	if charge >= maximum and not was_full:
		filled.emit()


## A cast: all of it (the debug "cooldowns off" switch keeps it full).
func spend() -> void:
	if Ability.cooldowns_disabled:
		return
	set_charge(0.0)
