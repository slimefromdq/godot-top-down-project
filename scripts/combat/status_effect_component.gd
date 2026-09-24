extends Node
class_name StatusEffectComponent

# Holds the buffs and debuffs currently on an actor. Other components ask it
# for multipliers instead of being edited directly, so an effect ending always
# restores the original values.

signal status_applied(effect: StatusEffect)
signal status_removed(effect: StatusEffect)

# id -> { "effect": StatusEffect, "time_left": float }
var _active: Dictionary = {}


func apply(effect: StatusEffect) -> void:
	if effect == null:
		return
	var is_new := not _active.has(effect.id)
	_active[effect.id] = {"effect": effect, "time_left": effect.duration}
	if is_new:
		status_applied.emit(effect)


func remove(effect_id: StringName) -> void:
	if not _active.has(effect_id):
		return
	var effect: StatusEffect = _active[effect_id].effect
	_active.erase(effect_id)
	status_removed.emit(effect)


func clear() -> void:
	for effect_id in _active.keys():
		remove(effect_id)


func has_status(effect_id: StringName) -> bool:
	return _active.has(effect_id)


func get_multiplier(stat: StringName) -> float:
	var result := 1.0
	for entry in _active.values():
		result *= entry.effect.stat_multipliers.get(stat, 1.0)
	return result


func _process(delta: float) -> void:
	for effect_id in _active.keys():
		_active[effect_id].time_left -= delta
		if _active[effect_id].time_left <= 0.0:
			remove(effect_id)


# Lets components treat a missing StatusEffectComponent as "no modifiers".
static func multiplier_of(component: StatusEffectComponent, stat: StringName) -> float:
	if component == null:
		return 1.0
	return component.get_multiplier(stat)
