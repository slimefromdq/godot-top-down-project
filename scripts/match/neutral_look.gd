extends Node2D
class_name NeutralLook

# Placeholder look for a neutral monster: a glossy gel blob in the data's
# colour with two sleepy eyes that open wide (and glow) while it fights.
# Big ones (the Nightmare) get a ring of wobbling horns and a dark swirl.
# Cosmetic only: NeutralData.look_scene points here; a sprite scene can
# replace it.

const INK := Color(0.1, 0.06, 0.16)
const SHADOW := Color(0, 0, 0, 0.25)
## Size from which the horns and swirl appear.
const BOSS_SIZE := 120.0

var monster: NeutralMonster
var _t := randf() * 10.0


func setup_neutral(owner_monster: NeutralMonster) -> void:
	monster = owner_monster


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if monster == null or monster.data == null:
		return
	var data := monster.data
	var r := data.size * 0.5
	var fighting := monster.is_fighting()
	var bob := sin(_t * (5.0 if fighting else 2.0)) * r * 0.05
	var squash := Vector2(1.0 + 0.04 * sin(_t * 3.0), 1.0 - 0.04 * sin(_t * 3.0))
	draw_set_transform(Vector2(0, r * 0.7), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r * 0.95, SHADOW)
	if r * 2.0 >= BOSS_SIZE:
		_draw_horns(r, data.color)
	draw_set_transform(Vector2(0, bob), 0.0, squash)
	draw_circle(Vector2.ZERO, r, data.color.darkened(0.35))
	draw_circle(Vector2(0, -r * 0.06), r * 0.92, data.color)
	if r * 2.0 >= BOSS_SIZE:
		for i in 3:
			var a := _t * 0.8 + TAU * i / 3.0
			draw_arc(Vector2.ZERO, r * (0.35 + 0.15 * i), a, a + 2.2, 24,
				Color(data.color.darkened(0.6), 0.5), r * 0.06, true)
	# Gel shine.
	draw_set_transform(Vector2(-r * 0.25, -r * 0.45 + bob), -0.3, Vector2(1.0, 0.55) * squash)
	draw_circle(Vector2.ZERO, r * 0.42, Color(1, 1, 1, 0.45))
	draw_set_transform(Vector2(0, bob), 0.0, squash)
	# Eyes: sleepy slits at rest, wide and glowing while fighting.
	var look := monster.aim_direction * r * 0.08
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * r * 0.3, -r * 0.05) + look
		if fighting:
			draw_circle(eye, r * 0.19, Color(1, 1, 1))
			draw_circle(eye + look * 0.6, r * 0.11, Color("ff4d6d") if r * 2.0 >= BOSS_SIZE else INK)
		else:
			draw_arc(eye, r * 0.15, 0.2, PI - 0.2, 12, INK, maxf(r * 0.05, 2.0), true)
	draw_set_transform(Vector2.ZERO)


func _draw_horns(r: float, color: Color) -> void:
	draw_set_transform(Vector2.ZERO)
	var count := 7
	for i in count:
		var a := -PI + PI * (i + 0.5) / count + sin(_t * 2.0 + i) * 0.08
		var dir := Vector2.from_angle(a)
		var base := dir * r * 0.8
		var side := dir.orthogonal() * r * 0.16
		draw_colored_polygon(PackedVector2Array([base + side, base - side, dir * r * 1.35]),
			color.darkened(0.55))
