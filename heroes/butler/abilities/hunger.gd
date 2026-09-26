extends PassiveAbility

# Hunger (0 - max_hunger). It rises from damage taken (per 1% of max HP lost)
# and every second in combat. At the top Butler becomes STARVING: every slot
# in starving_abilities swaps to its Starving form (AbilityController
# swap_slot) for up to starving_duration. Bites feed him (feed()); at 0, or
# when the time runs out, he recovers: the Composed slots come back, he's
# rooted a moment (recover_status: straightening his tie), then gets
# recover_armor_status. Damage doesn't add Hunger while Starving.
#
# Cues: hunger_starving, hunger_recovered. The bar over his head is
# vfx/hunger_bar.gd (both teams see it).

signal hunger_changed(hunger: float, max_hunger: float)
signal starving_started
signal starving_ended

var hunger: float = 0.0
var _starving := false
var _starving_left: float = 0.0
var _armor_in: float = -1.0
var _last_combat: float = -INF
var _clock: float = 0.0


func get_hunger_data() -> ButlerHungerData:
	return data as ButlerHungerData


func _ready() -> void:
	super()
	if actor == null:
		return
	actor.combat_hooks.damage_taken.connect(_on_damage_taken)
	actor.combat_hooks.hit_dealt.connect(func(_info, _target): _last_combat = _clock)
	actor.health_component.died.connect(_on_died)
	var bar: Node2D = preload("res://heroes/butler/vfx/hunger_bar.gd").new()
	bar.hunger = self
	actor.get_node(^"Visuals").add_child.call_deferred(bar)


func get_max_hunger() -> float:
	return data.get_value(&"max_hunger", get_stats())


func is_starving() -> bool:
	return _starving


func get_starving_time_left() -> float:
	return _starving_left if _starving else 0.0


func get_hud_meter() -> float:
	return hunger / get_max_hunger()


func add_hunger(amount: float) -> void:
	if _starving or amount <= 0.0:
		return
	_set_hunger(hunger + amount)
	# A hair of tolerance: ten 10% hits must fill it despite float rounding.
	if hunger >= get_max_hunger() - 0.001:
		start_starving()


# A Bite landed: less Hunger; at 0 he recovers.
func feed(amount: float) -> void:
	if not _starving:
		return
	_set_hunger(hunger - amount)
	if hunger <= 0.0:
		recover()


# Hunger full, Starving for the whole duration (the ultimate uses this).
func start_starving() -> void:
	_set_hunger(get_max_hunger())
	_starving_left = data.get_value(&"starving_duration", get_stats())
	if _starving:
		return
	_starving = true
	_armor_in = -1.0
	var hunger_data := get_hunger_data()
	for slot in hunger_data.starving_abilities:
		controller.swap_slot(slot, hunger_data.starving_abilities[slot])
	actor.trigger_cue(&"hunger_starving")
	starving_started.emit()


func recover() -> void:
	if not _starving:
		return
	_starving = false
	_set_hunger(0.0)
	var hunger_data := get_hunger_data()
	for slot in hunger_data.starving_abilities:
		controller.restore_slot(slot)
	if hunger_data.recover_status != null:
		actor.status_component.apply(hunger_data.recover_status, actor)
	_armor_in = data.get_value(&"recover_armor_delay", get_stats())
	actor.trigger_cue(&"hunger_recovered")
	starving_ended.emit()


func _physics_process(delta: float) -> void:
	super(delta)
	_clock += delta
	if actor == null or actor.health_component.is_dead():
		return
	if _armor_in >= 0.0:
		_armor_in -= delta
		if _armor_in < 0.0 and get_hunger_data().recover_armor_status != null:
			actor.status_component.apply(get_hunger_data().recover_armor_status, actor)
	if _starving:
		_starving_left -= delta
		if _starving_left <= 0.0:
			recover()
		return
	if _clock - _last_combat <= data.get_value(&"combat_window", get_stats()):
		add_hunger(data.get_value(&"hunger_per_second", get_stats()) * delta)


func _on_damage_taken(info: DamageInfo) -> void:
	_last_combat = _clock
	var max_hp := actor.health_component.max_health
	if max_hp <= 0.0 or info.final_amount <= 0.0:
		return
	add_hunger(info.final_amount / max_hp * 100.0 * data.get_value(&"hunger_per_hp_percent", get_stats()))


func _on_died() -> void:
	if _starving:
		recover()
	_set_hunger(0.0)


func _set_hunger(value: float) -> void:
	hunger = clampf(value, 0.0, get_max_hunger())
	hunger_changed.emit(hunger, get_max_hunger())
