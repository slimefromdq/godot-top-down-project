extends Node2D
class_name RegionAmbience

# One region's idle life, drawn from an AmbienceProfile: drifters wandering
# through the region's polygon and critters that scatter when a hero comes
# near, then settle back after a while. Made by MapAmbience, one per
# DreamZone; presentation only, never touches gameplay. Skips all work while
# the region is off screen (ScreenCull).

## Hero group checked for scaring critters.
const HEROES := &"heroes"

var profile: AmbienceProfile
var pair_id: StringName
## The region's outline in this node's coordinates (centred on it).
var polygon := PackedVector2Array()

var _bounds := Rect2()
var _radius: float = 0.0
var _t := 0.0
# Drifters: [base position, phase, size, use_alt]
var _drifters: Array = []
# Critters: {home, pos, vel, scared (seconds left, 0 = resting), phase}
var _critters: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _was_drawn := true


func setup(p_profile: AmbienceProfile, p_polygon: PackedVector2Array, p_pair: StringName, seed_value: int) -> void:
	profile = p_profile
	polygon = p_polygon
	pair_id = p_pair
	_rng.seed = seed_value
	# Sit at the region's centre so ScreenCull measures from there.
	var outer := Rect2(p_polygon[0], Vector2.ZERO)
	for p in p_polygon:
		outer = outer.expand(p)
	position += outer.get_center()
	polygon = Transform2D(0.0, -outer.get_center()) * p_polygon
	_bounds = Rect2(outer.position - outer.get_center(), outer.size)
	_radius = _bounds.size.length() * 0.5
	var area := _bounds.size.x * _bounds.size.y
	var count := int(profile.density * area / 1000000.0)
	for i in count:
		_drifters.append([_random_point(), _rng.randf() * TAU,
				_rng.randf_range(profile.size_min, profile.size_max), _rng.randf() < 0.5])
	for i in profile.critter_count:
		var home := _random_point()
		_critters.append({home = home, pos = home, vel = Vector2.ZERO, scared = 0.0,
				phase = _rng.randf() * TAU})


func contains(local_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(local_point, polygon)


## Distance from this node to the region's farthest corner.
func get_reach() -> float:
	return _radius


func get_drifter_count() -> int:
	return _drifters.size()


func get_critters() -> Array[Dictionary]:
	return _critters


func is_critter_scared(index: int) -> bool:
	return _critters[index].scared > 0.0


## Scatters every resting critter within `radius` of a world point (a shot,
## an explosion). Returns how many took off.
func startle(world_point: Vector2, radius: float) -> int:
	var at := to_local(world_point)
	var count := 0
	for c in _critters:
		if c.scared <= 0.0 and c.pos.distance_to(at) < radius:
			_scare(c, c.pos - at)
			count += 1
	return count


func _scare(c: Dictionary, away: Vector2) -> void:
	var dir := away.normalized() if away.length() > 1.0 else Vector2.UP
	dir = dir.rotated(_rng.randf_range(-0.6, 0.6))
	c.vel = dir * profile.scatter_speed + Vector2(0, -profile.scatter_speed * 0.4)
	c.scared = profile.settle_time


func _random_point() -> Vector2:
	for attempt in 30:
		var p := Vector2(_rng.randf_range(_bounds.position.x, _bounds.end.x),
				_rng.randf_range(_bounds.position.y, _bounds.end.y))
		if contains(p):
			return p
	return _bounds.get_center()


func _process(delta: float) -> void:
	if profile == null:
		return
	var drifters := VisualToggles.is_on(&"drifters")
	var critters := VisualToggles.is_on(&"critters")
	if not drifters and not critters:
		if _was_drawn:
			_was_drawn = false
			queue_redraw()
		return
	_was_drawn = true
	_t += delta
	var busy := _tick_critters(delta) if critters else false
	if busy or ScreenCull.is_near(self, _radius):
		queue_redraw()


## Moves scattered critters; returns true while any is in flight.
func _tick_critters(delta: float) -> bool:
	if _critters.is_empty():
		return false
	var heroes := get_tree().get_nodes_in_group(HEROES)
	var busy := false
	for c in _critters:
		if c.scared > 0.0:
			busy = true
			c.scared -= delta
			c.pos += c.vel * delta
			if c.scared <= 0.0:
				c.scared = 0.0
				c.pos = c.home
			continue
		for hero in heroes:
			if not hero is Node2D or not hero.is_inside_tree():
				continue
			var away: Vector2 = c.pos - to_local(hero.global_position)
			if away.length() < profile.scatter_radius:
				_scare(c, away)
				busy = true
				break
	return busy


func _draw() -> void:
	if profile == null:
		return
	var size := _bounds.size
	var show_drifters := VisualToggles.is_on(&"drifters")
	var drift_dir := profile.drift.normalized() if profile.drift.length() > 0.01 else Vector2.RIGHT
	for d in _drifters if show_drifters else []:
		var base: Vector2 = d[0]
		var phase: float = d[1]
		var p := base + profile.drift * _t
		p.x = _bounds.position.x + fposmod(p.x - _bounds.position.x, size.x)
		p.y = _bounds.position.y + fposmod(p.y - _bounds.position.y, size.y)
		var side := drift_dir.orthogonal() * sin(_t * TAU * profile.sway_speed + phase) * profile.sway
		p += side
		if not contains(p):
			continue
		var col: Color = profile.color_alt if d[3] else profile.color
		if profile.twinkle > 0.0:
			var blink := 0.5 + 0.5 * sin(_t * TAU * profile.twinkle_speed + phase * 3.0)
			col.a *= lerpf(1.0, blink, profile.twinkle)
		var r: float = d[2]
		if profile.stretch > 1.01:
			draw_set_transform(p, drift_dir.angle(), Vector2(profile.stretch, 1.0))
			draw_circle(Vector2.ZERO, r, col)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_circle(p, r, col)
	for c in _critters if VisualToggles.is_on(&"critters") else []:
		var col2 := profile.critter_color
		var pos: Vector2 = c.pos
		if c.scared > 0.0:
			# Fade out as it flies off, back in once it has settled.
			col2.a *= clampf(c.scared / profile.settle_time * 3.0 - 2.0, 0.0, 1.0)
		else:
			pos += Vector2(0, sin(_t * 2.0 + c.phase) * 3.0)
		if col2.a <= 0.01:
			continue
		var s := profile.critter_size
		var flap := absf(sin(_t * (14.0 if c.scared > 0.0 else 3.0) + c.phase))
		draw_line(pos, pos + Vector2(-s * 1.4, -s * flap), col2, 2.0)
		draw_line(pos, pos + Vector2(s * 1.4, -s * flap), col2, 2.0)
		draw_circle(pos, s * 0.45, col2)
