extends MinigameInstance
class_name AirlockMinigame

# The airlock (Sam's Close Encounter): a short maze. Find the way from the
# left of the room, around the inner walls, to the door strip on the right,
# and stand in it for door_hold to escape. The player slides along walls.
# One of the data's layouts is picked per run (random, or `layout_index`).
#
# Result: {"escaped": true} or {"timeout": true} (at max_duration).
# bot_input() (an AI victim) follows the shortest way at bot_speed_scale.
# The same shortest-way field (direction_home) is what tests use for a
# flawless run.

const CELL := 10.0

var player := Vector2.ZERO
var door_time: float = 0.0
var layout: MazeLayout
var layout_index: int = -1

# Distance field (cells to the door) for the shortest way.
var _field: PackedInt32Array
var _cols: int = 0
var _rows: int = 0


func _init(minigame_data: MinigameData = null, index: int = -1) -> void:
	super(minigame_data)
	layout_index = index


func get_airlock() -> AirlockData:
	return data as AirlockData


func _on_start() -> void:
	var room := get_airlock()
	if layout_index < 0 or layout_index >= room.layouts.size():
		layout_index = randi() % room.layouts.size()
	layout = room.layouts[layout_index]
	player = room.start
	_build_field()


func bot_input() -> Vector2:
	return direction_home(player) * get_airlock().bot_speed_scale


func _tick(delta: float, move: Vector2) -> void:
	var room := get_airlock()
	var step := move * room.player_speed * delta
	# Slide along walls: each axis separately.
	for axis in [Vector2(step.x, 0), Vector2(0, step.y)]:
		var next: Vector2 = player + axis
		if is_free(next):
			player = next
	if player.x >= room.door_x:
		door_time += delta
		if door_time >= room.door_hold:
			finish({"escaped": true, "layout": layout_index})
	else:
		door_time = 0.0


# Can the player stand at `at` (inside the room, clear of every wall)?
func is_free(at: Vector2) -> bool:
	var room := get_airlock()
	var r := room.player_radius
	if at.x < r or at.y < r or at.x > room.room_size.x - r or at.y > room.room_size.y - r:
		return false
	for wall in layout.walls:
		var nearest := Vector2(clampf(at.x, wall.position.x, wall.end.x), clampf(at.y, wall.position.y, wall.end.y))
		if nearest.distance_to(at) < r:
			return false
	return true


# The unit direction of the shortest way to the door from `at`.
func direction_home(at: Vector2) -> Vector2:
	var cell := _cell_of(at)
	var best := _dist(cell)
	var best_dir := Vector2.ZERO
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := cell + Vector2i(dx, dy)
			var d := _dist(n)
			if d >= 0 and (best < 0 or d < best):
				best = d
				best_dir = Vector2(dx, dy)
	if best_dir == Vector2.ZERO:
		return Vector2.RIGHT if at.x < get_airlock().door_x else Vector2.ZERO
	return best_dir.normalized()


# Length (px) of the shortest way from the start to the door, and the time a
# flawless run takes (plus door_hold).
func shortest_time() -> float:
	var steps := _dist(_cell_of(get_airlock().start))
	return steps * CELL / get_airlock().player_speed + get_airlock().door_hold if steps >= 0 else INF


func _build_field() -> void:
	var room := get_airlock()
	_cols = int(ceil(room.room_size.x / CELL))
	_rows = int(ceil(room.room_size.y / CELL))
	_field = PackedInt32Array()
	_field.resize(_cols * _rows)
	_field.fill(-1)
	var queue: Array[Vector2i] = []
	for y in _rows:
		for x in _cols:
			var p := _center(Vector2i(x, y))
			if p.x >= room.door_x and is_free(p):
				_field[y * _cols + x] = 0
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := _field[c.y * _cols + c.x]
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if n.x < 0 or n.y < 0 or n.x >= _cols or n.y >= _rows or _field[n.y * _cols + n.x] >= 0:
				continue
			if not is_free(_center(n)):
				continue
			_field[n.y * _cols + n.x] = d + 1
			queue.append(n)


func _center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _cell_of(at: Vector2) -> Vector2i:
	return Vector2i(clampi(int(at.x / CELL), 0, _cols - 1), clampi(int(at.y / CELL), 0, _rows - 1))


func _dist(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= _cols or c.y >= _rows:
		return -1
	return _field[c.y * _cols + c.x]


func draw_view(canvas: CanvasItem, rect: Rect2) -> void:
	var room := get_airlock()
	var scale := minf(rect.size.x / room.room_size.x, rect.size.y / room.room_size.y)
	var origin := rect.position + (rect.size - room.room_size * scale) / 2.0
	canvas.draw_rect(Rect2(origin, room.room_size * scale), Color(0.12, 0.08, 0.2))
	var door := Rect2(origin + Vector2(room.door_x, 0) * scale, Vector2(room.room_size.x - room.door_x, room.room_size.y) * scale)
	canvas.draw_rect(door, Color(0.3, 1.0, 0.7, 0.2 + 0.6 * clampf(door_time / maxf(room.door_hold, 0.01), 0.0, 1.0)))
	if layout != null:
		for wall in layout.walls:
			canvas.draw_rect(Rect2(origin + wall.position * scale, wall.size * scale), Color(0.75, 0.8, 0.95))
	canvas.draw_circle(origin + player * scale, room.player_radius * scale, Color(1, 0.95, 0.4))
	var time_left := maxf(data.max_duration - elapsed, 0.0)
	canvas.draw_rect(Rect2(origin + Vector2(0, -10), Vector2(room.room_size.x * scale * time_left / data.max_duration, 6)), Color(1, 0.5, 0.8))
