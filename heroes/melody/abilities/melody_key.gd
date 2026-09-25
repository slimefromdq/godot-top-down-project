extends PassiveAbility

# The Key: Melody's passive, in the "passive" slot. Owns `turns` (0 to
# values/max_turns), the wind-up key on her back and the pips on her bar.
#
# ENCORE RULE, in one place: an ability that has an encore asks
#   var strength: float = key.consume_encore(self)   # < 0 = no encore
# at the moment it commits (a cast, or a charge's release). With turns >=
# values/encore_threshold it gets the encore: ALL turns are spent and it
# receives the encore strength. can_encore() peeks without spending (for
# abilities that decide early and commit later).
#
# ENCORE STRENGTH = 1 + min(perfects since the key was last emptied x
# values/encore_per_perfect, values/encore_cap). Encore numbers read
# encore_value(), which scales an ability's named value's BASE (never its
# Magic ratio), so encores stay useful without snowballing late.
#
# UNWIND: values/unwind_delay seconds without scoring a note, then one turn
# lost every values/unwind_interval.
#
# Signals: turns_changed(turns, max_turns), encore_triggered(ability_id,
# strength). Cues: the_key_turn (context.turns), the_key_unwind,
# <ability_id>_encore (context.strength).

signal turns_changed(turns: int, max_turns: int)
signal encore_triggered(ability_id: StringName, strength: float)

const VISUAL := preload("res://heroes/melody/vfx/wind_key.gd")

var turns: int = 0
## Perfect notes scored since the key was last emptied.
var perfects: int = 0

var _since_note: float = 0.0
var _unwind_timer: float = 0.0


func _ready() -> void:
	super()
	if actor != null:
		var visual: Node2D = VISUAL.new()
		visual.key = self
		actor.get_node(^"Visuals").add_child(visual)
		actor.health_component.died.connect(_empty)


func get_max_turns() -> int:
	return roundi(data.get_value(&"max_turns", get_stats()))


func get_encore_threshold() -> int:
	return roundi(data.get_value(&"encore_threshold", get_stats()))


func get_hud_pips() -> Vector2i:
	return Vector2i(turns, get_max_turns())


# A note was scored (PERFECT or GOOD) somewhere in her kit. Resets the
# unwind clock; `add_turn` false for notes that don't wind (the march).
func note_scored(perfect: bool, add_turn: bool = true) -> void:
	_since_note = 0.0
	_unwind_timer = 0.0
	if perfect:
		perfects += 1
	if add_turn:
		set_turns(turns + 1)


func set_turns(value: int) -> void:
	value = clampi(value, 0, get_max_turns())
	if value == turns:
		return
	var gained := value > turns
	turns = value
	if turns == 0:
		perfects = 0
	turns_changed.emit(turns, get_max_turns())
	actor.trigger_cue(&"the_key_turn" if gained else &"the_key_unwind", {"turns": turns})


func can_encore() -> bool:
	return turns >= get_encore_threshold()


# 1 + perfect bonus (capped). The one encore-strength formula.
func get_encore_strength() -> float:
	return 1.0 + minf(perfects * data.get_value(&"encore_per_perfect", get_stats()),
		data.get_value(&"encore_cap", get_stats()))


# Spend the key for `ability`'s encore. Returns the strength, or -1.0 if
# the key isn't wound enough (turns kept).
func consume_encore(ability: Ability) -> float:
	if not can_encore():
		return -1.0
	var strength := get_encore_strength()
	_empty()
	encore_triggered.emit(ability.ability_id, strength)
	actor.trigger_cue(StringName(str(ability.ability_id) + "_encore"), {"strength": strength})
	return strength


# An encore number: the BASE of `ability_data`'s named value x strength.
static func encore_value(ability_data: AbilityData, key: StringName, strength: float) -> float:
	var value: ScalingValue = ability_data.values.get(key)
	return value.base * strength if value != null else 0.0


func _empty() -> void:
	set_turns(0)
	perfects = 0


func _physics_process(delta: float) -> void:
	super(delta)
	if turns <= 0:
		return
	_since_note += delta
	if _since_note < data.get_value(&"unwind_delay", get_stats()):
		return
	_unwind_timer += delta
	var interval := data.get_value(&"unwind_interval", get_stats())
	if interval > 0.0 and _unwind_timer + StatusEffectComponent.TICK_EPSILON >= interval:
		_unwind_timer -= interval
		set_turns(turns - 1)


# The key of an actor (her passive slot), or null. Her abilities use this.
static func find_on(actor: Node) -> Ability:
	var hero := actor as Hero
	if hero == null:
		return null
	var key := hero.get_ability(&"passive")
	return key if key != null and key.has_method(&"consume_encore") else null
