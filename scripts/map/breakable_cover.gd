extends StaticBody2D
class_name BreakableCover

# Dream-glass: full cover (blocks movement and shots) that anyone can shoot
# down. It shatters at 0 HP, stays down for data.regrow_time, shimmers for
# data.regrow_warning, then turns solid again. If a body stands where it
# would regrow, it waits (data.regrow_retry) instead of trapping them.
#
# Shape: the CollisionPolygon2D child, as on CoverBody. The piece builds its
# own HealthComponent and a HurtboxComponent a little larger than the shape,
# so shots stopped by the glass still hit it. It has no team: both teams hit
# it. Numbers in MapPieceData; cues (data.*_cue) through the match profiles.

enum State { INTACT, BROKEN, WARNING }

const GROUP := &"breakable_cover"
## How far the hurtbox reaches past the glass (px), so a shot stopped at the
## surface still lands.
const HURT_MARGIN := 14.0

signal shattered
signal restored

@export var data: MapPieceData
@export var fill_color := Color(0.8, 0.95, 1.0, 0.92)
@export var edge_color := Color(0.25, 0.45, 0.75, 1.0)

var state: State = State.INTACT
var health: HealthComponent
var hurtbox: HurtboxComponent
var _polygon := PackedVector2Array()
var _left := 0.0
var _flash := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(MatchManager.CLOCK_LISTENERS)
	collision_mask = 0
	for child in get_children():
		if child is CollisionPolygon2D:
			_polygon = child.transform * child.polygon
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = data.max_health if data else 600.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(shatter)
	hurtbox = HurtboxComponent.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health_component = health
	hurtbox.collision_layer = MapLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var bounds := _bounds()
	rect.size = bounds.size + Vector2.ONE * HURT_MARGIN * 2.0
	shape.shape = rect
	shape.position = bounds.get_center()
	hurtbox.add_child(shape)
	add_child(hurtbox)
	_set_solid(true)


func _bounds() -> Rect2:
	if _polygon.is_empty():
		return Rect2(-20, -20, 40, 40)
	var r := Rect2(_polygon[0], Vector2.ZERO)
	for p in _polygon:
		r = r.expand(p)
	return r


func is_solid() -> bool:
	return state == State.INTACT


func get_time_left() -> float:
	return _left


func _set_solid(on: bool) -> void:
	collision_layer = MapLayers.WORLD if on else 0
	hurtbox.set_deferred(&"monitorable", on)


func _on_damaged(_amount: float, _source: Node) -> void:
	_flash = 0.12
	if data and data.hit_cue != &"":
		MatchManager.play_world_cue(self, data.hit_cue)
	queue_redraw()


## Break now (0 HP, or a map event). Safe to call when already broken.
func shatter() -> void:
	if state != State.INTACT:
		return
	state = State.BROKEN
	_left = data.regrow_time if data else 25.0
	_set_solid(false)
	if data and data.break_cue != &"":
		MatchManager.play_world_cue(self, data.break_cue)
	shattered.emit()
	queue_redraw()


## Solid again at full HP (unless a body is in the way: see _try_restore).
func restore() -> void:
	state = State.INTACT
	_left = 0.0
	health.reset()
	_set_solid(true)
	if data and data.restore_cue != &"":
		MatchManager.play_world_cue(self, data.restore_cue)
	restored.emit()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	match state:
		State.BROKEN:
			_left -= delta
			if _left <= data.regrow_warning:
				state = State.WARNING
				if data.warning_cue != &"":
					MatchManager.play_world_cue(self, data.warning_cue)
		State.WARNING:
			_left -= delta
			if _left <= 0.0:
				if is_blocked():
					_left = data.regrow_retry
				else:
					restore()
	if state != State.INTACT or _flash > 0.0:
		if ScreenCull.is_near(self, _bounds().size.length()):
			queue_redraw()


## Debug clock jump: start the new time with the glass whole.
func on_clock_jumped(_from: float, _to: float) -> void:
	if state != State.INTACT and not is_blocked():
		restore()
	elif state == State.INTACT:
		health.reset()


## Is any character standing where the glass would regrow?
func is_blocked() -> bool:
	if _polygon.size() < 3:
		return false
	var shape := ConvexPolygonShape2D.new()
	shape.points = _polygon
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = MapLayers.CHARACTERS
	query.collide_with_bodies = true
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _draw() -> void:
	if _polygon.size() < 3:
		return
	match state:
		State.INTACT:
			var shadow := PackedVector2Array()
			for p in _polygon:
				shadow.append(p + Vector2(10, 16))
			draw_colored_polygon(shadow, CoverBody.SHADOW)
			var fill := fill_color.lerp(Color.WHITE, 0.7) if _flash > 0.0 else fill_color
			var batch := ShapeBatch.new()
			batch.draw_colored_polygon(_polygon, fill)
			AeroDraw.gloss_polygon(batch, _polygon, fill)
			batch.draw_on(self)
			var outline := _polygon.duplicate()
			outline.append(_polygon[0])
			draw_polyline(outline, edge_color, 4.0, true)
			_draw_cracks(1.0 - health.get_health_ratio())
		State.BROKEN, State.WARNING:
			# Shards on the ground where it stood.
			var b := _bounds()
			var shard := Color(edge_color, 0.35)
			for i in 7:
				var f := (i + 0.5) / 7.0
				var at := b.position + b.size * Vector2(f, fmod(f * 3.7, 1.0))
				draw_colored_polygon(PackedVector2Array([at, at + Vector2(10, 4), at + Vector2(3, 11)]), shard)
			if state == State.WARNING:
				var pulse := 0.35 + 0.35 * sin(_t * 12.0)
				var ghost := _polygon.duplicate()
				ghost.append(_polygon[0])
				draw_polyline(ghost, Color(edge_color, pulse), 3.0, true)
				draw_colored_polygon(_polygon, Color(fill_color, pulse * 0.3))


# More cracks the more it's hurt: lines from fixed points on the glass.
func _draw_cracks(damage: float) -> void:
	if damage <= 0.05:
		return
	var b := _bounds()
	var count := int(ceil(damage * 6.0))
	var col := Color(edge_color, 0.8)
	for i in count:
		var f := (i + 0.5) / 6.0
		var from := b.position + b.size * Vector2(f, 0.5)
		var dir := Vector2.from_angle(f * 9.0)
		var reach := b.size.length() * 0.18
		draw_line(from, from + dir * reach, col, 2.0)
		draw_line(from, from - dir.rotated(0.6) * reach * 0.7, col, 1.5)
