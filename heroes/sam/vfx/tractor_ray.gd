extends Node2D

# Cosmetic, Tractor Beam's projectile visual: a translucent mint cone from
# Sam's UFO-antenna to the beam head (the projectile), widening toward the
# head, with rainbow scanlines sliding back toward Sam so it reads as suction.

const CORE := Color(0.6, 1.0, 0.8, 0.35)
const EDGE := Color(0.75, 1.0, 0.9, 0.8)
const SCANLINES := [Color(1.0, 0.6, 0.85), Color(0.7, 0.75, 1.0), Color(0.6, 1.0, 0.8), Color(1.0, 0.95, 0.6)]
const HEAD_HALF_WIDTH := 48.0
const ROOT_HALF_WIDTH := 10.0
const SCANLINE_GAP := 34.0
const SCANLINE_SPEED := 420.0

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var projectile := get_parent() as Projectile
	var from := Vector2(-60.0, 0.0)
	if projectile != null and projectile.damage_template != null and is_instance_valid(projectile.damage_template.source):
		from = to_local(projectile.damage_template.source.global_position)
	var length := from.length()
	if length < 1.0:
		return
	var axis := -from / length    # Sam -> head
	var side := axis.orthogonal()
	var cone := PackedVector2Array([from + side * ROOT_HALF_WIDTH, side * HEAD_HALF_WIDTH,
		-side * HEAD_HALF_WIDTH, from - side * ROOT_HALF_WIDTH])
	draw_colored_polygon(cone, CORE)
	draw_line(cone[0], cone[1], EDGE, 3.0, true)
	draw_line(cone[3], cone[2], EDGE, 3.0, true)
	# Scanlines drift from the head back to Sam.
	var offset := fmod(_t * SCANLINE_SPEED, SCANLINE_GAP)
	var d := length - offset
	var i := int(_t * SCANLINE_SPEED / SCANLINE_GAP)
	while d > 0.0:
		var t := d / length
		var half := lerpf(ROOT_HALF_WIDTH, HEAD_HALF_WIDTH, t)
		var at := from + axis * d
		var color: Color = SCANLINES[i % SCANLINES.size()]
		color.a = 0.35 + 0.45 * t
		draw_line(at + side * half, at - side * half, color, 4.0, true)
		d -= SCANLINE_GAP
		i += 1
	draw_circle(Vector2.ZERO, 14.0, Color(0.85, 1.0, 0.92, 0.9))
	draw_arc(Vector2.ZERO, HEAD_HALF_WIDTH, 0.0, TAU, 32, Color(EDGE, 0.5 + 0.3 * sin(_t * 20.0)), 3.0, true)
