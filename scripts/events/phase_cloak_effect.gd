extends TempEffect
class_name PhaseCloakEffect

# A short invulnerable dash, then the item's status (invisibility) for its
# duration. The dash goes the way the hero is moving (else where they aim).
#
#   values.dash_distance   pixels
#   values.dash_time       seconds (the dash is a forced move, so it is exact)
#   values.invuln_grace    extra invulnerable seconds after the dash ends
#
# The status (invisible + a faded body) starts when the dash lands, and
# `duration` counts from then.

var _dash_left: float = 0.0


func applies_status_on_start() -> bool:
	return false


func total_time() -> float:
	return _dash_total() + duration


func _dash_total() -> float:
	return item.value_of(&"dash_time", 0.25)


func _on_start() -> void:
	var direction := hero.move_direction
	if direction.length() < 0.1:
		direction = hero.aim_direction
	if direction.length() < 0.1:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var time := maxf(_dash_total(), 0.05)
	_dash_left = time
	hero.health_component.set_invulnerable_for(time + item.value_of(&"invuln_grace", 0.1))
	hero.movement_component.start_forced_move(direction * item.value_of(&"dash_distance", 450.0) / time, time, false)
	hero.trigger_cue(&"dash", {"direction": direction})


func _on_tick(delta: float) -> void:
	if _dash_left <= 0.0:
		return
	_dash_left -= delta
	if _dash_left <= 0.0:
		_apply_status(duration)
