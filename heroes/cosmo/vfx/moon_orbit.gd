extends Node2D

# Cosmo's moons, orbiting her: how enemies read her strength at a glance.
# One slot per moon (her primary's magazine). Ready moons glow; spent ones
# are a faint ring; the next moon to come back fades in with its regen.
# Positions come from the passive's orbit (the same ones Moonshot fires
# from). Cosmetic only.

const MOON := Color(0.86, 0.9, 1.0)
const GLOW := Color(0.6, 0.75, 1.0, 0.35)

var passive: Node    # waxing_moon.gd


func _ready() -> void:
	z_index = 3


func _process(_delta: float) -> void:
	if not is_instance_valid(passive):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var gun: RangedAttackAbility = passive.get_gun()
	if gun == null:
		return
	var count := gun.get_max_ammo()
	var ready := gun.get_ammo()
	for i in count:
		var at: Vector2 = passive.get_moon_offset(i, count)
		if i < ready:
			draw_circle(at, 17.0, GLOW)
			draw_circle(at, 11.0, MOON)
			draw_circle(at + Vector2(4, -3), 9.0, Color(0.72, 0.78, 0.95))    # a soft terminator
		elif i == ready:
			var fade: float = gun.get_regen_ratio()
			var c := MOON
			c.a = 0.15 + 0.6 * fade
			draw_circle(at, 11.0 * (0.5 + 0.5 * fade), c)
			draw_arc(at, 12.0, -PI / 2.0, -PI / 2.0 + TAU * fade, 20, Color(0.8, 0.88, 1.0, 0.8), 2.0)
		else:
			draw_arc(at, 11.0, 0.0, TAU, 20, Color(0.8, 0.88, 1.0, 0.3), 1.5)
