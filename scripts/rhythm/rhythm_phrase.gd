@tool
extends Resource
class_name RhythmPhrase

# A short timing minigame: `note_count` beats, one every beat_interval
# seconds after `lead_in`. Pressing close to a beat grades it PERFECT or
# GOOD; a beat whose good window passes unpressed is a MISS. A
# RhythmPerformer on the actor plays it (see rhythm_performer.gd) and draws
# the shrinking ring ON the actor, so it reads in a busy fight.
#
# All timing is in seconds of physics time.

@export var note_count: int = 4
## Beats per minute. One note per beat.
@export var bpm: float = 160.0
## Seconds before the first beat (time to read the ring).
@export var lead_in: float = 0.4
## Seconds either side of a beat that still count as GOOD.
@export var good_window: float = 0.12
## Seconds either side of a beat that count as PERFECT.
@export var perfect_window: float = 0.05
## Input action whose presses play the notes (the player input routes it to
## RhythmPerformer.press_note() while the phrase runs).
@export var input_action: StringName = &"hero_cc"

@export_group("Interruptions")
## A stun ends the phrase early (notes already graded still count).
@export var cancel_on_stun: bool = true
## A silence ends the phrase early.
@export var cancel_on_silence: bool = false

@export_group("Presentation")
## The approach ring shrinks from start to end radius and lands on the beat.
@export var ring_start_radius: float = 150.0
@export var ring_end_radius: float = 60.0
## Pitch multiplier per note (cycled), passed as context.pitch on the note
## cues, so a phrase plays a melody instead of one repeated beep.
@export var note_pitches: Array[float] = [1.0]


func get_beat_interval() -> float:
	return 60.0 / bpm if bpm > 0.0 else 0.5


# Physics-time offset of note `index` from the phrase start.
func get_beat_time(index: int) -> float:
	return lead_in + index * get_beat_interval()


# When the phrase has nothing left to grade.
func get_total_time() -> float:
	return get_beat_time(note_count - 1) + good_window


func get_pitch(index: int) -> float:
	return note_pitches[index % note_pitches.size()] if not note_pitches.is_empty() else 1.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if note_count < 1 or bpm <= 0.0:
		problems.append("phrase needs note_count >= 1 and bpm > 0")
	if lead_in < 0.0 or perfect_window < 0.0 or good_window < perfect_window:
		problems.append("phrase windows must be >= 0 with good_window >= perfect_window")
	elif good_window * 2.0 >= get_beat_interval():
		problems.append("phrase good_window overlaps the next beat (beat interval %.2f s)" % get_beat_interval())
	if ring_start_radius < ring_end_radius or ring_end_radius < 0.0:
		problems.append("phrase ring radii are inverted or negative")
	return problems
