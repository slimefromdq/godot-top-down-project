extends Node2D

# The rhythm ring drawn on the performing actor: a fixed target circle and
# an approach ring that shrinks onto it exactly on the beat, plus pips for
# the notes left and a flash per grade (gold PERFECT, white GOOD, red MISS).
# Cosmetic only; the performer owns the timing.

const PERFECT_COLOR := Color(1.0, 0.85, 0.25)
const GOOD_COLOR := Color(0.85, 0.95, 1.0)
const MISS_COLOR := Color(1.0, 0.3, 0.3)

var performer: RhythmPerformer
var target_color := Color(1, 1, 1, 0.55)
var approach_color := Color(1.0, 0.9, 0.5, 0.95)

var _flash_color := Color.WHITE
var _flash: float = 0.0
var _fade: float = 1.0
var _finishing := false


func _ready() -> void:
	z_index = 6


func flash(grade: int) -> void:
	_flash_color = [PERFECT_COLOR, GOOD_COLOR, MISS_COLOR][grade]
	_flash = 1.0


# The phrase ended: let the last flash play, then go.
func finish() -> void:
	_finishing = true


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.5, 0.0)
	if _finishing:
		_fade -= delta * 3.0
		if _fade <= 0.0:
			queue_free()
	queue_redraw()


func _draw() -> void:
	var playing := is_instance_valid(performer) and performer.is_playing() and not _finishing
	var phrase: RhythmPhrase = performer.phrase if playing else null
	var end_radius := phrase.ring_end_radius if phrase != null else 60.0
	var start_radius := phrase.ring_start_radius if phrase != null else 150.0
	var alpha := clampf(_fade, 0.0, 1.0)
	var target := target_color
	target.a *= alpha
	draw_arc(Vector2.ZERO, end_radius, 0.0, TAU, 48, target, 4.0, true)
	if phrase != null:
		var t := performer.get_approach()
		var radius := lerpf(start_radius, end_radius, t)
		var approach := approach_color
		approach.a *= lerpf(0.35, 1.0, t)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, approach, lerpf(3.0, 7.0, t), true)
		# Notes left, as pips under the ring.
		var left := phrase.note_count - performer.get_next_index()
		for i in left:
			var x := (i - (left - 1) / 2.0) * 16.0
			draw_circle(Vector2(x, end_radius + 18.0), 5.0, Color(1, 1, 1, 0.8 * alpha))
	if _flash > 0.0:
		var c := _flash_color
		c.a = _flash
		draw_arc(Vector2.ZERO, end_radius + (1.0 - _flash) * 40.0, 0.0, TAU, 48, c, 10.0 * _flash + 2.0, true)
