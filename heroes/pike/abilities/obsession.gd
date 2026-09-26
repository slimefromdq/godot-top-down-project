extends PassiveAbility

# Obsession: while Pike's Beloved (see beloved_ability.gd) has no line of
# sight to her (CombatQueries.has_line_of_sight: walls, bushes), she carries
# unseen_status (faster, faded). The moment they see her again her next knife
# is an AMBUSH: double damage and ambush_status (a root), at most once per
# values/ambush_cooldown. The knives ask consume_ambush().
#
# Cues: <id>_unseen, <id>_seen (the heart could flinch), <id>_ambush_ready.

var _unseen := false
var _ambush_ready := false
var _ambush_wait: float = 0.0


func get_obsession_data() -> PikeObsessionData:
	return data as PikeObsessionData


func is_unseen() -> bool:
	return _unseen


func is_ambush_ready() -> bool:
	return _ambush_ready


# The knives: true (once) if this knife is the ambush.
func consume_ambush() -> bool:
	if not _ambush_ready:
		return false
	_ambush_ready = false
	_ambush_wait = data.get_value(&"ambush_cooldown", get_stats())
	return true


func get_beloved() -> Node2D:
	var beloved := controller.get_ability_for_slot(&"ability_1")
	return beloved.get_beloved() if beloved != null and beloved.has_method(&"get_beloved") else null


func _physics_process(delta: float) -> void:
	super(delta)
	if _ambush_wait > 0.0:
		_ambush_wait -= delta
	if actor == null or actor.health_component.is_dead():
		return
	var beloved := get_beloved()
	var unseen := beloved != null and not CombatQueries.has_line_of_sight(beloved, actor)
	var obsession := get_obsession_data()
	if unseen:
		actor.status_component.apply(obsession.unseen_status, actor)
		if not _unseen:
			actor.trigger_cue(StringName(str(ability_id) + "_unseen"))
	elif _unseen:
		actor.status_component.remove_from(obsession.unseen_status.id, actor)
		actor.trigger_cue(StringName(str(ability_id) + "_seen"))
		if beloved != null and _ambush_wait <= 0.0:
			_ambush_ready = true
			actor.trigger_cue(StringName(str(ability_id) + "_ambush_ready"))
	_unseen = unseen
