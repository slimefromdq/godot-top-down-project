extends RefCounted
class_name RhythmResults

# What happened in one RhythmPhrase: a grade per note, in order.

enum Grade { PERFECT, GOOD, MISS }

var phrase: RhythmPhrase
var grades: Array[int] = []
## The phrase ended early (stun, silence, replaced). Graded notes still count.
var cancelled := false


func get_perfects() -> int:
	return grades.count(Grade.PERFECT)


func get_goods() -> int:
	return grades.count(Grade.GOOD)


func get_hits() -> int:
	return get_perfects() + get_goods()


func get_misses() -> int:
	return grades.count(Grade.MISS)


static func grade_name(grade: int) -> StringName:
	return [&"perfect", &"good", &"miss"][grade]
