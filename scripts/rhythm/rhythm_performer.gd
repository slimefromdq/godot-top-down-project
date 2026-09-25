extends Node
class_name RhythmPerformer

# Runs one RhythmPhrase at a time on an actor. Abilities start it with
# play(); the player input (or an AI, or a test) calls press_note() for
# each press. The actor keeps moving and casting while it runs.
#
#   phrase_started(phrase)
#   note_graded(index, grade)      RhythmResults.Grade: PERFECT / GOOD / MISS
#   phrase_finished(results)       also when cancelled (results.cancelled)
#
# Cues on the actor, per note: "<cue_prefix>_note_perfect" / "_good" /
# "_miss", with context.index and context.pitch (the phrase's note pitch).
#
# Timing is summed physics deltas, so it is deterministic. A stun (and a
# silence, if the phrase says so) ends the phrase early.

signal phrase_started(phrase: RhythmPhrase)
signal note_graded(index: int, grade: int)
signal phrase_finished(results: RhythmResults)

const NODE_NAME := &"RhythmPerformer"
const RING_SCRIPT := preload("res://scripts/rhythm/rhythm_ring.gd")

var phrase: RhythmPhrase
var results: RhythmResults
## Seconds since the phrase started (physics time).
var time: float = 0.0
var cue_prefix: StringName = &""

var _next_index: int = 0    # first note not graded yet
var _ring: Node2D


# The performer on an actor, created on first use under Components.
static func find_or_create(actor: Node) -> RhythmPerformer:
	var existing := find_on(actor)
	if existing != null:
		return existing
	var performer := RhythmPerformer.new()
	performer.name = NODE_NAME
	var parent := actor.get_node_or_null(^"Components")
	(parent if parent != null else actor).add_child(performer)
	return performer


static func find_on(actor: Node) -> RhythmPerformer:
	if actor == null or not is_instance_valid(actor):
		return null
	var node := actor.get_node_or_null(NodePath("Components/" + NODE_NAME))
	if node == null:
		node = actor.get_node_or_null(NodePath(NODE_NAME))
	return node as RhythmPerformer


func is_playing() -> bool:
	return phrase != null


func get_input_action() -> StringName:
	return phrase.input_action if phrase != null else &""


# Start `new_phrase`. A phrase already running is cancelled first.
func play(new_phrase: RhythmPhrase, prefix: StringName) -> void:
	if is_playing():
		cancel()
	phrase = new_phrase
	cue_prefix = prefix
	time = 0.0
	_next_index = 0
	results = RhythmResults.new()
	results.phrase = new_phrase
	_spawn_ring()
	phrase_started.emit(new_phrase)


# End now; graded notes count, ungraded ones are simply not played.
func cancel() -> void:
	if not is_playing():
		return
	results.cancelled = true
	_finish()


# A press. Grades the nearest ungraded note if the press is inside its
# good window; otherwise it's ignored (no penalty for an early tap outside
# the window). Returns the grade, or -1 if ignored.
func press_note() -> int:
	if not is_playing() or _next_index >= phrase.note_count:
		return -1
	var offset := absf(time - phrase.get_beat_time(_next_index))
	if offset > phrase.good_window + StatusEffectComponent.TICK_EPSILON:
		return -1
	var grade := RhythmResults.Grade.PERFECT if offset <= phrase.perfect_window + StatusEffectComponent.TICK_EPSILON \
		else RhythmResults.Grade.GOOD
	_grade(grade)
	return grade


# 0..1 progress of the approach ring for the next note (1 = on the beat).
func get_approach(index: int = -1) -> float:
	if not is_playing():
		return 0.0
	if index < 0:
		index = _next_index
	var interval := phrase.get_beat_interval()
	var until := phrase.get_beat_time(index) - time
	return clampf(1.0 - until / interval, 0.0, 1.0)


func get_next_index() -> int:
	return _next_index


func _physics_process(delta: float) -> void:
	if not is_playing():
		return
	var actor := _get_actor()
	var status: StatusEffectComponent = actor.get(&"status_component") if actor != null else null
	if status != null and ((phrase.cancel_on_stun and status.is_stunned())
			or (phrase.cancel_on_silence and status.is_silenced())):
		cancel()
		return
	var health: HealthComponent = actor.get(&"health_component") if actor != null else null
	if health != null and health.is_dead():
		cancel()
		return
	time += delta
	# Every note whose good window has fully passed is a miss.
	while is_playing() and _next_index < phrase.note_count \
			and time > phrase.get_beat_time(_next_index) + phrase.good_window + StatusEffectComponent.TICK_EPSILON:
		_grade(RhythmResults.Grade.MISS)


func _grade(grade: int) -> void:
	var index := _next_index
	_next_index += 1
	results.grades.append(grade)
	var actor := _get_actor()
	if actor != null and actor.has_method(&"trigger_cue"):
		actor.trigger_cue(StringName("%s_note_%s" % [cue_prefix, RhythmResults.grade_name(grade)]), {
			"index": index, "pitch": phrase.get_pitch(index), "grade": grade})
	if is_instance_valid(_ring):
		_ring.flash(grade)
	note_graded.emit(index, grade)
	if _next_index >= phrase.note_count:
		_finish()


func _finish() -> void:
	var done := results
	phrase = null
	if is_instance_valid(_ring):
		_ring.finish()
	_ring = null
	phrase_finished.emit(done)


func _spawn_ring() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	var actor := _get_actor() as Node2D
	if actor == null:
		return
	_ring = RING_SCRIPT.new()
	_ring.performer = self
	var visuals := actor.get_node_or_null(^"Visuals")
	(visuals if visuals != null else actor).add_child(_ring)


func _get_actor() -> Node:
	var parent := get_parent()
	if parent != null and parent.name == &"Components":
		return parent.get_parent()
	return parent
