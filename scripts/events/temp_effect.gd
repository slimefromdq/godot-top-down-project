extends RefCounted
class_name TempEffect

# One running copy of a Black Market item's effect on one hero (made by
# BlackMarketItem.make_effect, owned by the hero's TempItems). The base class
# only applies the item's status for the buff's duration; small subclasses
# add what a status can't do (PhaseCloakEffect, MoteMagnetEffect,
# SecondWindEffect). Numbers come from item.values, never from the scripts.
#
# Reusable on its own: TempItems.grant(item) works for any BlackMarketItem on
# any hero, which is what the debug panel's "Give temp item" does.

var hero: Hero
var item: BlackMarketItem
## Seconds the buff was granted for.
var duration: float = 0.0
var age: float = 0.0
var _status_applied := false


## True once nothing is left to run: TempItems drops it. The default runs for
## `duration`.
func is_finished() -> bool:
	return age >= total_time()


## Seconds this effect runs from start() (0 for an instant one).
func total_time() -> float:
	return duration


## Instant items (Second Wind) act on start() and are finished right away.
func is_instant() -> bool:
	return false


func start(p_hero: Hero, p_item: BlackMarketItem, p_duration: float) -> void:
	hero = p_hero
	item = p_item
	duration = 0.0 if is_instant() else p_duration
	age = 0.0
	if applies_status_on_start():
		_apply_status(p_duration)
	_on_start()


func tick(delta: float) -> void:
	age += delta
	_on_tick(delta)


## Ended by the timer, a death or a debug clear. Takes its status off.
func stop() -> void:
	if _status_applied and item != null and item.status != null and is_instance_valid(hero):
		hero.status_component.remove(item.status.id)
	_status_applied = false
	_on_stop()


func applies_status_on_start() -> bool:
	return true


func _apply_status(seconds: float) -> void:
	if item == null or item.status == null or not is_instance_valid(hero):
		return
	hero.status_component.apply(item.status, hero, Vector2.ZERO, 1.0, seconds)
	_status_applied = true


func _on_start() -> void:
	pass


func _on_tick(_delta: float) -> void:
	pass


func _on_stop() -> void:
	pass
