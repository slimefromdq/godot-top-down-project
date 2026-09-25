extends Ability

# Grand March (Q). On cast, allies within gather_radius join a parade line
# behind Melody (formation_status: a breakable follow-trail compel) and
# everyone in it gets speed_status. An 8-note march_phrase starts on the E
# key (Performance can't start meanwhile). Per note:
#   PERFECT  +perfect_extension seconds, shield the formation
#   GOOD     a weaker formation shield
#   MISS     nothing
# March notes wind the Key only if notes_add_turns. Melody keeps her
# primary, RMB and Shift; her dash drags the line along (it follows her
# trail). Only the cast gathers: allies walking in later don't join.
# Ends when time runs out or Melody is stunned (or dies): followers are
# released where they stand (a forced move in progress plays out).
#
# Cues: <id>_start (context.followers), <id>_extend, <id>_end.

const KEY := preload("res://heroes/melody/abilities/melody_key.gd")

var followers: Array[Node2D] = []
var _marching := false
var _time_left: float = 0.0
var _performer: RhythmPerformer


func get_march_data() -> MelodyGrandMarchData:
	return data as MelodyGrandMarchData


func is_marching() -> bool:
	return _marching


func get_time_left() -> float:
	return _time_left if _marching else 0.0


func _activate(_target_position: Vector2) -> String:
	if get_march_data().march_phrase == null:
		return "No phrase"
	return ""


func _on_active_start() -> void:
	_start_march()


func _start_march() -> void:
	var march := get_march_data()
	followers.clear()
	var radius := data.get_value(&"gather_radius", get_stats())
	for hurtbox in Hitbox.query(actor, actor.global_position, Vector2.RIGHT, HitShape.circle(radius),
			actor, Hitbox.Affects.ALLIES):
		var ally := hurtbox.owner as Node2D
		if ally == null or ally == actor or followers.has(ally):
			continue
		followers.append(ally)
	# Nearest first: they take the slots closest to her.
	followers.sort_custom(func(a, b): return actor.global_position.distance_squared_to(a.global_position) \
		< actor.global_position.distance_squared_to(b.global_position))
	_marching = true
	_time_left = data.get_value(&"march_duration", get_stats())
	for ally in followers:
		_status_of(ally).apply(march.formation_status, actor, Vector2.ZERO, 1.0, _time_left + 1.0)
	for member in _members():
		_status_of(member).apply(march.speed_status, actor, Vector2.ZERO, 1.0, _time_left + 1.0)
	_performer = RhythmPerformer.find_or_create(actor)
	if not _performer.note_graded.is_connected(_on_note_graded):
		_performer.note_graded.connect(_on_note_graded)
	_performer.play(march.march_phrase, ability_id)    # replaces a Performance in progress
	actor.trigger_cue(StringName(str(ability_id) + "_start"), {"followers": followers.size(), "duration": _time_left})


# Melody plus everyone still in the line.
func _members() -> Array[Node2D]:
	var result: Array[Node2D] = [actor]
	for ally in followers:
		if is_instance_valid(ally):
			result.append(ally)
	return result


func _physics_process(delta: float) -> void:
	super(delta)
	if not _marching:
		return
	if actor.health_component.is_dead() or actor.status_component.is_stunned():
		end_march()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		end_march()
		return
	# Whoever broke free has left the parade: no more march buff.
	var march := get_march_data()
	for ally in followers.duplicate():
		var status := _status_of(ally)
		if status == null or not status.has_status_from(march.formation_status.id, actor):
			followers.erase(ally)
			if status != null:
				status.remove_from(march.speed_status.id, actor)


func _on_note_graded(_index: int, grade: int) -> void:
	if not _marching or _performer.cue_prefix != ability_id or grade == RhythmResults.Grade.MISS:
		return
	var march := get_march_data()
	var perfect := grade == RhythmResults.Grade.PERFECT
	var key := KEY.find_on(actor)
	if key != null:
		key.note_scored(perfect, march.notes_add_turns)
	if perfect:
		_time_left += data.get_value(&"perfect_extension", get_stats())
		# Keep the statuses running as long as the march.
		for ally in followers:
			if is_instance_valid(ally):
				_status_of(ally).apply(march.formation_status, actor, Vector2.ZERO, 1.0, _time_left + 1.0)
		for member in _members():
			_status_of(member).apply(march.speed_status, actor, Vector2.ZERO, 1.0, _time_left + 1.0)
		actor.trigger_cue(StringName(str(ability_id) + "_extend"), {"time_left": _time_left})
	var strength := data.get_value(&"perfect_shield_strength" if perfect else &"good_shield_strength", get_stats())
	for member in _members():
		_status_of(member).apply(march.shield_status, actor, Vector2.ZERO, strength)


func end_march() -> void:
	if not _marching:
		return
	_marching = false
	_time_left = 0.0
	var march := get_march_data()
	for member in _members():
		var status := _status_of(member)
		if status != null:
			status.remove_from(march.formation_status.id, actor)
			status.remove_from(march.speed_status.id, actor)
	followers.clear()
	if _performer != null and _performer.is_playing() and _performer.cue_prefix == ability_id:
		_performer.cancel()
	if is_instance_valid(actor):
		actor.trigger_cue(StringName(str(ability_id) + "_end"), {})


func _exit_tree() -> void:
	end_march()
	super()


static func _status_of(node: Node) -> StatusEffectComponent:
	if not is_instance_valid(node):
		return null
	return node.get(&"status_component") as StatusEffectComponent
