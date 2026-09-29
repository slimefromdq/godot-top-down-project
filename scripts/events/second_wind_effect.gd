extends TempEffect
class_name SecondWindEffect

# Instant: heal values.heal_pct of max HP (0.6 = 60%) and cleanse every
# harmful status (StatusEffectComponent.cleanse). Nothing lingers, so the
# buff is over the moment it is bought.


func is_instant() -> bool:
	return true


func _on_start() -> void:
	var health := hero.health_component
	health.heal(health.max_health * item.value_of(&"heal_pct", 0.6), hero, &"second_wind")
	hero.status_component.cleanse()
