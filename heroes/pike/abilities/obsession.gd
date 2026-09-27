extends PassiveAbility

# Obsession: when Pike breaks her Beloved's line of sight (see
# beloved_ability.gd; CombatQueries.has_line_of_sight: walls, bushes) she
# vanishes: unseen_status is invisible to every enemy (and faster, faded for
# her team). Invisibility itself blocks their sight, so she STAYS hidden when
# she walks back into view, until she:
#   * casts anything outside data.keeps_stealth_slots (There You Are keeps
#     it), or throws a knife: she reappears and, at most once per
#     values/ambush_cooldown, her next knife is an AMBUSH (double damage and
#     ambush_status, a root). The knives ask consume_ambush();
#   * is revealed (a StatusEffect.reveals status), loses her Beloved, or dies:
#     she reappears with no ambush.
# After reappearing she can't vanish again for values/restealth_delay.
#
# Cues: <id>_unseen, <id>_seen (the heart could flinch), <id>_ambush_ready.

var _unseen := false
var _ambush_ready := false
var _ambush_wait: float = 0.0
var _restealth_wait: float = 0.0
var _hooked: Array[Ability] = []


func get_obsession_data() -> PikeObsessionData:
	return data as PikeObsessionData


func is_unseen() -> bool:
	return _unseen


func is_ambush_ready() -> bool:
	return _ambush_ready


# The knives: true (once) if this knife is the ambush. A knife thrown from
# hiding reveals her first.
func consume_ambush() -> bool:
	if _unseen:
		_reveal(true)
	if not _ambush_ready:
		return false
	_ambush_ready = false
	_ambush_wait = data.get_value(&"ambush_cooldown", get_stats())
	return true


func get_beloved() -> Node2D:
	var beloved := controller.get_ability_for_slot(&"ability_1")
	return beloved.get_beloved() if beloved != null and beloved.has_method(&"get_beloved") else null


func _ready() -> void:
	super()
	if controller != null:
		controller.abilities_changed.connect(_hook_abilities)
		_hook_abilities.call_deferred()


func _hook_abilities() -> void:
	for ability in controller.abilities:
		if ability == self or ability in _hooked:
			continue
		_hooked.append(ability)
		ability.activated.connect(_on_ability_activated.bind(ability))


func _on_ability_activated(ability: Ability) -> void:
	if _unseen and not get_obsession_data().keeps_stealth_slots.has(ability.slot_id):
		_reveal(true)


func _physics_process(delta: float) -> void:
	super(delta)
	if _ambush_wait > 0.0:
		_ambush_wait -= delta
	if _restealth_wait > 0.0:
		_restealth_wait -= delta
	if actor == null:
		return
	if actor.health_component.is_dead():
		if _unseen:
			_reveal(false)
		return
	var beloved := get_beloved()
	var obsession := get_obsession_data()
	if _unseen:
		# Invisible, their sight only comes back through a reveal.
		if beloved == null or CombatQueries.has_line_of_sight(beloved, actor):
			_reveal(false)
		else:
			actor.status_component.apply(obsession.unseen_status, actor)
	elif beloved != null and _restealth_wait <= 0.0 and not CombatQueries.has_line_of_sight(beloved, actor):
		_unseen = true
		_ambush_ready = false
		actor.status_component.apply(obsession.unseen_status, actor)
		actor.trigger_cue(StringName(str(ability_id) + "_unseen"))


# Out of hiding. `attacking`: she chose to (arms the ambush if it's ready).
func _reveal(attacking: bool) -> void:
	_unseen = false
	_restealth_wait = data.get_value(&"restealth_delay", get_stats())
	actor.status_component.remove_from(get_obsession_data().unseen_status.id, actor)
	actor.trigger_cue(StringName(str(ability_id) + "_seen"))
	if attacking and _ambush_wait <= 0.0 and get_beloved() != null:
		_ambush_ready = true
		actor.trigger_cue(StringName(str(ability_id) + "_ambush_ready"))
