extends Node
class_name HealthComponent

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health: float = 200.0
## Optional. Reads the damage_taken multiplier from active status effects.
@export var status_component: StatusEffectComponent

var current_health: float
# Whoever landed the most recent hit. Visuals and audio use it on death to
# play the killer's kill effect.
var last_damage_source: Node = null

var _invulnerable_time_left: float = 0.0


func _ready() -> void:
	current_health = max_health


func _process(delta: float) -> void:
	_invulnerable_time_left = max(_invulnerable_time_left - delta, 0.0)


func is_dead() -> bool:
	return current_health <= 0.0


func is_invulnerable() -> bool:
	return _invulnerable_time_left > 0.0


# Longer windows win; a short window never cuts a longer one short.
func set_invulnerable_for(seconds: float) -> void:
	_invulnerable_time_left = max(_invulnerable_time_left, seconds)


func take_damage(amount: float, source: Node = null) -> void:
	if current_health <= 0.0:      # top: "was I ALREADY dead before this hit?"
		return
	if is_invulnerable():
		return

	amount *= StatusEffectComponent.multiplier_of(status_component, StatusEffect.DAMAGE_TAKEN)
	current_health -= amount
	current_health = max(current_health, 0.0)
	if source != null:
		last_damage_source = source
	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:      # bottom: "did THIS hit kill me?"
		died.emit()


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	var before := current_health
	current_health = min(current_health + amount, max_health)
	healed.emit(current_health - before)
	health_changed.emit(current_health, max_health)


# Full health again, e.g. for a respawning training dummy.
func reset() -> void:
	current_health = max_health
	last_damage_source = null
	health_changed.emit(current_health, max_health)
