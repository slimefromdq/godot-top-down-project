extends AreaTelegraphEffect

# Swarm Ride's landing telegraph: the shared warning circle, plus the army
# bunching up under him (bugs rushing in from the rim to a tight knot) and
# buzz marks that get denser as the burst approaches.

const Bug := preload("res://heroes/cpt_yellow/vfx/bug_draw.gd")

@export var bug_count: int = 26
@export var bug_size: float = 22.0


func _draw_extra(progress: float) -> void:
	var ease_in := progress * progress
	for i in bug_count:
		var a := i * 2.39996 + _t * 3.0
		var far := radius * (0.55 + 0.35 * fmod(i * 0.618, 1.0))
		var near := 26.0 + 30.0 * fmod(i * 0.371, 1.0)
		var at := Vector2.from_angle(a) * lerpf(far, near, ease_in)
		at += Vector2(sin(_t * 70.0 + i), cos(_t * 63.0 + i)) * 3.0 * progress
		Bug.draw_bug(self, at, -at, bug_size, 1.0, 0.5 + 0.5 * sin(_t * 80.0 + i))
	# Buzz: short jittery strokes around the knot.
	var strokes := int(lerpf(4.0, 16.0, progress))
	for i in strokes:
		var a := randf() * TAU
		var from := Vector2.from_angle(a) * randf_range(60.0, 90.0)
		draw_line(from, from + Vector2.from_angle(a + randf_range(-0.6, 0.6)) * 18.0, Color(1, 1, 0.6, 0.8), 3.0)
