extends Node2D
class_name FountainRipple

# Rings spreading across a fountain's water: one every ripple_interval on
# its own, and an extra one when something splashes near it (a shot, see
# MapAmbience.startle). Made by MapAmbience for every node in the
# "fountains" group; the basin's radius comes from its collision polygon.
# Presentation only.

const GROUP := &"fountains"

var settings: AmbienceSet
var basin_radius: float = 150.0
var _t := 0.0
var _until_next := 0.0
# Live ripples: [centre (local), age]
var _ripples: Array = []
var _rng := RandomNumberGenerator.new()


func setup(fountain: Node2D, p_settings: AmbienceSet, seed_value: int) -> void:
	settings = p_settings
	_rng.seed = seed_value
	var far := 0.0
	for child in fountain.get_children():
		if child is CollisionPolygon2D:
			for p in child.polygon:
				far = maxf(far, p.length())
	if far > 0.0:
		basin_radius = far
	z_index = 1
	_until_next = _rng.randf() * settings.ripple_interval


func get_ripple_count() -> int:
	return _ripples.size()


## Starts a ripple at `local_point` (clamped inside the basin).
func splash(local_point: Vector2 = Vector2.ZERO) -> void:
	var limit := basin_radius * 0.6
	if local_point.length() > limit:
		local_point = local_point.normalized() * limit
	_ripples.append([local_point, 0.0])


func _process(delta: float) -> void:
	_t += delta
	_until_next -= delta
	if _until_next <= 0.0 and settings.ripple_interval > 0.0:
		_until_next = settings.ripple_interval * _rng.randf_range(0.7, 1.3)
		splash(Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * basin_radius * 0.5)
	for r in _ripples:
		r[1] += delta
	_ripples = _ripples.filter(func(r): return r[1] < settings.ripple_life)
	if not _ripples.is_empty() and ScreenCull.is_near(self, basin_radius):
		queue_redraw()
	elif _ripples.is_empty():
		queue_redraw()


func _draw() -> void:
	for r in _ripples:
		var k: float = r[1] / settings.ripple_life
		var radius: float = settings.ripple_speed * r[1]
		var centre: Vector2 = r[0]
		# Keep the ring on the water: shrink it where it would cross the rim.
		radius = minf(radius, basin_radius - centre.length() - 4.0)
		if radius <= 1.0:
			continue
		var c := settings.ripple_color
		c.a *= 1.0 - k
		draw_arc(centre, radius, 0.0, TAU, 32, c, 2.0, true)
