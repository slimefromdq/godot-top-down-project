extends Ability

# Close Encounter:
#   1. Target an enemy near the cursor (AllyTargeting, accepts ENEMIES). A
#      beam telegraph lands on their spot after values/telegraph; if they've
#      moved more than values/beam_radius from it, it misses.
#   2. Hit: they get abducted_status (untargetable, the UFO look) and play the
#      data's minigame (MinigameHost) while their body flies toward Sam's
#      cursor at values/ufo_speed (MovementComponent.set_cruise).
#   3. Meanwhile Sam can move and shoot (primary) but cast nothing else.
#   4. When the minigame ends (escaped, timed out, or Sam dies) they drop
#      where the UFO is, with daze_status.
# Cues: <id>_telegraph (context.position), <id>_miss, <id>_abduct
# (context.target), <id>_drop (context.position, target).

enum State { IDLE, TELEGRAPH, ABDUCTED }

var state := State.IDLE
var victim: Node2D
var beam_spot := Vector2.ZERO
var _telegraph_left: float = 0.0
var _host: MinigameHost
var _leaving := false


func get_encounter_data() -> SamEncounterData:
	return data as SamEncounterData


func is_abducting() -> bool:
	return state == State.ABDUCTED


func _activate(_target_position: Vector2) -> String:
	return "Busy" if state != State.IDLE else ""


func _on_active_start() -> void:
	victim = cast_ally
	if victim == null:
		return
	beam_spot = victim.global_position
	_telegraph_left = data.get_value(&"telegraph", get_stats())
	state = State.TELEGRAPH
	actor.trigger_cue(StringName(str(ability_id) + "_telegraph"), {"position": beam_spot,
		"radius": data.get_value(&"beam_radius", get_stats()), "duration": _telegraph_left})


func _physics_process(delta: float) -> void:
	super(delta)
	match state:
		State.TELEGRAPH:
			_telegraph_left -= delta
			if _telegraph_left <= 0.0:
				_land_beam()
		State.ABDUCTED:
			if StatusEffectComponent.is_actor_gone(actor) or StatusEffectComponent.is_actor_gone(victim):
				if is_instance_valid(_host) and _host.is_playing():
					_host.stop()
				else:
					_drop()
				return
			var to_cursor: Vector2 = actor.aim_point - victim.global_position
			var movement = victim.get(&"movement_component")
			if movement is MovementComponent:
				var speed := data.get_value(&"ufo_speed", get_stats())
				movement.set_cruise(self, to_cursor.normalized() if to_cursor.length() > 8.0 else Vector2.ZERO, speed)


# Sam removed (freed at death, or the hero swapped): the victim drops now.
func _exit_tree() -> void:
	super()
	if state != State.ABDUCTED:
		return
	_leaving = true    # no cues: the world is mid-removal
	if is_instance_valid(_host) and _host.is_playing():
		_host.stop()
	else:
		_drop()


func _land_beam() -> void:
	var reach := data.get_value(&"beam_radius", get_stats())
	var status := CombatQueries.status_of(victim)
	if StatusEffectComponent.is_actor_gone(victim) or status == null or status.is_untargetable() \
			or victim.global_position.distance_to(beam_spot) > reach:
		state = State.IDLE
		actor.trigger_cue(StringName(str(ability_id) + "_miss"), {"position": beam_spot})
		return
	var encounter := get_encounter_data()
	status.apply(encounter.abducted_status, actor, Vector2.ZERO, 1.0, encounter.minigame.max_duration + 1.0)
	_host = MinigameHost.find_or_create(victim)
	var game := AirlockMinigame.new(encounter.minigame) if encounter.minigame is AirlockData \
		else MinigameInstance.new(encounter.minigame)
	if not _host.play(game, actor):
		status.remove_from(encounter.abducted_status.id, actor)
		state = State.IDLE
		return
	_host.finished.connect(_on_minigame_finished, CONNECT_ONE_SHOT)
	state = State.ABDUCTED
	controller.lock_abilities(self, [&"primary"], [])
	actor.trigger_cue(StringName(str(ability_id) + "_abduct"), {"target": victim})


func _on_minigame_finished(_game: MinigameInstance, _result: Dictionary) -> void:
	_drop()


func _drop() -> void:
	if state != State.ABDUCTED:
		return
	state = State.IDLE
	controller.unlock_abilities(self)
	if is_instance_valid(victim):
		var movement = victim.get(&"movement_component")
		if movement is MovementComponent:
			movement.clear_cruise(self)
		if victim is CharacterBody2D:
			victim.velocity = Vector2.ZERO    # land on the spot, no glide
		var status := CombatQueries.status_of(victim)
		var encounter := get_encounter_data()
		if status != null:
			status.remove_from(encounter.abducted_status.id, actor)
			status.apply(encounter.daze_status, actor)
		if not _leaving:
			actor.trigger_cue(StringName(str(ability_id) + "_drop"), {"position": victim.global_position, "target": victim})
	victim = null
