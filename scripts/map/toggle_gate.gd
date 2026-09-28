extends StaticBody2D
class_name ToggleGate

# A door in the map (a shop shutter, a hedge gate) that opens and closes on
# its own. Its shape is the CollisionPolygon2D child (the closed leaf).
#
#   cycle      open for data.gate_open_time, closed for data.gate_closed_time,
#              repeating on MapClock (the match clock), shifted by
#              cycle_offset. It flashes for data.gate_warning before changing.
#              Both halves of a mirrored pair share one cycle.
#   lever      when lever_offset isn't zero, a small post there that anyone
#              can shoot: a hit flips the gate for data.lever_hold_time, then
#              it rejoins its cycle (data.lever_cooldown between flips).
#   force()    a map event holds it open or closed for a while.
#   no crush   when it closes, every character in the doorway is pushed out
#              to the nearer side (data.gate_push_margin past its edge).
#
# Closed, it's full cover (or low cover when !data.gate_blocks_shots). Bots
# route around it only while it's closed (BotNavigation). Cues through the
# match profiles: data.open_cue / close_cue / hit_cue (lever).

const GROUP := &"toggle_gates"

signal opened
signal closed

@export var data: MapPieceData
## Seconds added to the match clock for this gate's cycle.
@export var cycle_offset: float = 0.0
## Where the lever post stands (local). Zero = no lever.
@export var lever_offset := Vector2.ZERO
@export var color := Color(0.55, 0.62, 0.78)

var is_closed_now := false
var lever: HurtboxComponent
var _polygon := PackedVector2Array()
var _held_until := -1.0    # MapClock time a lever/event hold ends
var _held_closed := false
var _lever_ready_at := -1.0
var _until_change := INF
var _t := 0.0
var _initialized := false


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(MatchManager.CLOCK_LISTENERS)
	collision_mask = 0
	for child in get_children():
		if child is CollisionPolygon2D:
			_polygon = child.transform * child.polygon
	if lever_offset != Vector2.ZERO:
		_make_lever()
	_update(true)


func _make_lever() -> void:
	var health := HealthComponent.new()
	health.name = "LeverHealth"
	health.max_health = 100000.0
	add_child(health)
	health.damaged.connect(func(_a, source): _on_lever_hit(source))
	lever = HurtboxComponent.new()
	lever.name = "Lever"
	lever.health_component = health
	lever.collision_layer = MapLayers.ENEMY_HURTBOX
	lever.collision_mask = 0
	lever.position = lever_offset
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	shape.shape = circle
	lever.add_child(shape)
	add_child(lever)


## Closed right now?
func is_closed() -> bool:
	return is_closed_now


## Where the gate blocks (global), for bots.
func get_block_polygon() -> PackedVector2Array:
	return global_transform * _polygon


func get_time_to_change() -> float:
	return _until_change


func is_held() -> bool:
	return _held_until >= 0.0 and MapClock.now(self) < _held_until


## Hold it open (closed = false) or closed for `seconds` (map events, debug).
func force(closed_state: bool, seconds: float) -> void:
	_held_closed = closed_state
	_held_until = MapClock.now(self) + seconds
	_update()


func release() -> void:
	_held_until = -1.0
	_update()


func _on_lever_hit(_source: Node) -> void:
	lever.health_component.reset()
	var now := MapClock.now(self)
	if now < _lever_ready_at:
		return
	_lever_ready_at = now + data.lever_cooldown
	if data.hit_cue != &"":
		MatchManager.play_world_cue(self, data.hit_cue, {"position": to_global(lever_offset)})
	force(not is_closed_now, data.lever_hold_time)


## The state the cycle (or a hold) wants now, and seconds until it changes.
func _wanted() -> Array:
	var now := MapClock.now(self)
	if is_held():
		return [_held_closed, _held_until - now]
	var p := MapClock.phase(now, data.gate_open_time, data.gate_closed_time, cycle_offset)
	return [not p[0], p[1]]


func _physics_process(delta: float) -> void:
	_t += delta
	_update()
	if ScreenCull.is_near(self, 400.0):
		queue_redraw()


func _update(first: bool = false) -> void:
	var wanted := _wanted()
	_until_change = wanted[1]
	var want_closed: bool = wanted[0]
	if first or not _initialized:
		_initialized = true
		_apply(want_closed, false)
	elif want_closed != is_closed_now:
		_apply(want_closed, true)


func _apply(closed_state: bool, announce: bool) -> void:
	is_closed_now = closed_state
	if closed_state:
		_push_out()
		collision_layer = MapLayers.WORLD if data.gate_blocks_shots else MapLayers.LOW_COVER
		if announce:
			if data.close_cue != &"":
				MatchManager.play_world_cue(self, data.close_cue)
			closed.emit()
	else:
		collision_layer = 0
		if announce:
			if data.open_cue != &"":
				MatchManager.play_world_cue(self, data.open_cue)
			opened.emit()
	queue_redraw()


# Everyone standing in the doorway steps out to the nearer side.
func _push_out() -> void:
	if _polygon.size() < 3 or not is_inside_tree():
		return
	var bounds := _bounds()
	# The thin axis is the one bodies cross.
	var across := Vector2(0, 1) if bounds.size.x >= bounds.size.y else Vector2(1, 0)
	var half := (bounds.size.y if across.y != 0.0 else bounds.size.x) * 0.5
	var shape := ConvexPolygonShape2D.new()
	shape.points = _polygon
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = MapLayers.CHARACTERS
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body := hit.collider as Node2D
		if body == null:
			continue
		var local := to_local(body.global_position) - bounds.get_center()
		var side := signf(local.dot(across))
		if side == 0.0:
			side = 1.0
		var along := local - across * local.dot(across)
		var target := to_global(bounds.get_center() + along + across * side * (half + data.gate_push_margin))
		if body is Actor:
			body.teleport_to(target)
		else:
			body.global_position = target


func _bounds() -> Rect2:
	var r := Rect2(_polygon[0], Vector2.ZERO)
	for p in _polygon:
		r = r.expand(p)
	return r


## Debug clock jump: drop any hold; the cycle follows the new time.
func on_clock_jumped(_from: float, _to: float) -> void:
	_held_until = -1.0
	_lever_ready_at = -1.0
	_update()


func _draw() -> void:
	if _polygon.size() < 3:
		return
	var warn := _until_change <= data.gate_warning
	var flash := warn and fmod(_t * 4.0, 1.0) < 0.5
	var outline := _polygon.duplicate()
	outline.append(_polygon[0])
	if is_closed_now:
		var shadow := PackedVector2Array()
		for p in _polygon:
			shadow.append(p + Vector2(8, 12))
		draw_colored_polygon(shadow, CoverBody.SHADOW)
		var fill := color.lightened(0.35) if flash else color
		draw_colored_polygon(_polygon, fill)
		# Shutter slats across the long axis.
		var b := _bounds()
		var horizontal := b.size.x >= b.size.y
		var n := 6
		for i in range(1, n):
			var f := float(i) / n
			if horizontal:
				draw_line(Vector2(b.position.x + b.size.x * f, b.position.y), Vector2(b.position.x + b.size.x * f, b.end.y), color.darkened(0.3), 2.0)
			else:
				draw_line(Vector2(b.position.x, b.position.y + b.size.y * f), Vector2(b.end.x, b.position.y + b.size.y * f), color.darkened(0.3), 2.0)
		draw_polyline(outline, color.darkened(0.5), 4.0, true)
	else:
		# Open: just the frame on the floor, dashed; flashing before it shuts.
		var edge := Color(color.darkened(0.3), 0.9 if flash else 0.45)
		for i in _polygon.size():
			draw_dashed_line(outline[i], outline[i + 1], edge, 3.0, 12.0)
	if lever != null:
		var lever_color := Color(1, 0.85, 0.3) if MapClock.now(self) >= _lever_ready_at else Color(0.5, 0.5, 0.5)
		draw_circle(lever_offset, 22.0, color.darkened(0.4))
		draw_circle(lever_offset, 14.0, lever_color)
		var tilt := Vector2.from_angle(-PI / 4 if is_closed_now else -3 * PI / 4) * 30.0
		draw_line(lever_offset, lever_offset + tilt, lever_color.darkened(0.3), 5.0)
