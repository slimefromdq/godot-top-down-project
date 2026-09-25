extends Ability

# Performance (E): play a short RhythmPhrase on the tuba while moving.
# Per note (see MelodyPerformanceData):
#   PERFECT  +1 turn on the Key (counts toward encore strength), full
#            shield pulse to allies (herself included) in pulse_radius
#   GOOD     +1 turn, a weaker pulse
#   MISS     nothing but the sour honk (<id>_note_miss)
# Turns cap at the Key's max; extra hits still pulse. It never spends the
# Key. It can't start while another phrase plays (the Grand March).
#
# Cues: <id>_note_perfect/_good/_miss (from the performer, pitched per
# note), <id>_pulse (context.strength, .radius).

const KEY := preload("res://heroes/melody/abilities/melody_key.gd")

var _performer: RhythmPerformer


func get_performance_data() -> MelodyPerformanceData:
	return data as MelodyPerformanceData


func get_block_reason() -> String:
	var reason := super()
	if reason == "" and _performer != null and _performer.is_playing():
		return "Performing"
	return reason


func _activate(_target_position: Vector2) -> String:
	if get_performance_data().phrase == null:
		return "No phrase"
	_performer = RhythmPerformer.find_or_create(actor)
	if not _performer.note_graded.is_connected(_on_note_graded):
		_performer.note_graded.connect(_on_note_graded)
	_performer.play(get_performance_data().phrase, ability_id)
	return ""


func _on_note_graded(_index: int, grade: int) -> void:
	# The performer is shared (the march plays on it too): only our phrase.
	if _performer.cue_prefix != ability_id or grade == RhythmResults.Grade.MISS:
		return
	var perfect := grade == RhythmResults.Grade.PERFECT
	var key := KEY.find_on(actor)
	if key != null:
		key.note_scored(perfect, true)
	var strength := data.get_value(&"perfect_shield_strength" if perfect else &"good_shield_strength", get_stats())
	pulse_shield(strength)


# Shield every ally (herself included) within pulse_radius.
func pulse_shield(strength: float) -> void:
	var radius := data.get_value(&"pulse_radius", get_stats())
	for hurtbox in Hitbox.query(actor, actor.global_position, Vector2.RIGHT, HitShape.circle(radius),
			actor, Hitbox.Affects.ALLIES):
		if hurtbox.status_component != null:
			hurtbox.status_component.apply(get_performance_data().shield_status, actor, Vector2.ZERO, strength)
	actor.trigger_cue(StringName(str(ability_id) + "_pulse"), {"strength": strength, "radius": radius})
