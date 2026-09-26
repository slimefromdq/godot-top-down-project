extends PassiveAbility

# Steady Hand: every full second Nimbus stands still adds a stack (up to
# values/max_stacks); his next rifle shot deals values/bonus_per_stack more
# per stack and uses them up. Moving (faster than values/still_speed)
# drops them. Shown as pips on the ability bar.

var _still_time: float = 0.0
var stacks: int = 0


func get_max_stacks() -> int:
	return roundi(data.get_value(&"max_stacks", get_stats()))


# Damage bonus for the next shot (0.4 = +40%).
func get_bonus() -> float:
	return stacks * data.get_value(&"bonus_per_stack", get_stats())


# The rifle fired: the bonus is spent, the count starts over.
func consume() -> void:
	stacks = 0
	_still_time = 0.0


func get_hud_pips() -> Vector2i:
	return Vector2i(stacks, get_max_stacks())


func _physics_process(delta: float) -> void:
	super(delta)
	if actor == null or actor.health_component.is_dead():
		return
	if actor.velocity.length() > data.get_value(&"still_speed", get_stats()) or actor.is_airborne():
		_still_time = 0.0
		stacks = 0
		return
	_still_time += delta
	stacks = mini(floori(_still_time + 0.0001), get_max_stacks())
