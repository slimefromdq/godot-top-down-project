extends MinigameInstance
class_name AirlockMinigame

# The airlock (Sam's Close Encounter): walk from the left of a small room to
# the door on the right and stand in it for door_hold to escape, while Sam's
# affection fills the room: slow hearts along lanes, "HI!!" bubbles sweeping
# down columns, and a wobbly hug-arm reaching for you. Each hit pushes you
# back knockback px. All numbers are in AirlockData; patterns are fixed.
#
# Result: {"escaped": true, "hits": n} or {"timeout": true} (at max_duration).
# bot_input() (an AI victim) walks straight for the door without dodging.

class Hazard:
	var kind: StringName    # &"heart", &"bubble"
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO


var player := Vector2.ZERO
var hazards: Array[Hazard] = []
var arm_hand := Vector2.ZERO
var arm_out := false
var hits: int = 0
var door_time: float = 0.0

var _hit_wait: float = 0.0
var _hearts_sent: int = 0
var _bubbles_sent: int = 0


func get_airlock() -> AirlockData:
	return data as AirlockData


func _on_start() -> void:
	var room := get_airlock()
	player = Vector2(room.start_x, room.room_size.y / 2.0)
	arm_hand = Vector2(0.0, room.room_size.y / 2.0)


func bot_input() -> Vector2:
	return Vector2.RIGHT


func _tick(delta: float, move: Vector2) -> void:
	var room := get_airlock()
	player += move * room.player_speed * delta
	player.x = clampf(player.x, room.player_radius, room.room_size.x - room.player_radius)
	player.y = clampf(player.y, room.player_radius, room.room_size.y - room.player_radius)
	_spawn(room)
	for hazard in hazards:
		hazard.position += hazard.velocity * delta
	hazards = hazards.filter(func(h): return h.position.x > -60.0 and h.position.y < room.room_size.y + 60.0)
	_move_arm(room, delta)
	_hit_wait = maxf(_hit_wait - delta, 0.0)
	if _hit_wait <= 0.0 and _touching(room):
		hits += 1
		_hit_wait = room.hit_cooldown
		player.x = maxf(player.x - room.knockback, room.player_radius)
		door_time = 0.0
	if player.x >= room.door_x:
		door_time += delta
		if door_time >= room.door_hold:
			finish({"escaped": true, "hits": hits})
	else:
		door_time = 0.0


func _spawn(room: AirlockData) -> void:
	while room.heart_lanes.size() > 0 and elapsed >= room.heart_first + _hearts_sent * room.heart_interval:
		var heart := Hazard.new()
		heart.kind = &"heart"
		var lane := room.heart_lanes[_hearts_sent % room.heart_lanes.size()]
		heart.position = Vector2(room.room_size.x + room.heart_radius, lane * room.room_size.y)
		heart.velocity = Vector2.LEFT * room.heart_speed
		hazards.append(heart)
		_hearts_sent += 1
	while room.bubble_columns.size() > 0 and elapsed >= room.bubble_first + _bubbles_sent * room.bubble_interval:
		var bubble := Hazard.new()
		bubble.kind = &"bubble"
		var column := room.bubble_columns[_bubbles_sent % room.bubble_columns.size()]
		bubble.position = Vector2(column * room.room_size.x, -room.bubble_size.y / 2.0)
		bubble.velocity = Vector2.DOWN * room.bubble_speed
		hazards.append(bubble)
		_bubbles_sent += 1


func _move_arm(room: AirlockData, delta: float) -> void:
	arm_out = elapsed >= room.arm_delay
	if not arm_out:
		return
	var wobble := Vector2(0.0, sin(elapsed * 9.0) * room.arm_wobble)
	arm_hand = arm_hand.move_toward(player + wobble, room.arm_speed * delta)


# Is anything touching the player right now?
func _touching(room: AirlockData) -> bool:
	if arm_out and arm_hand.distance_to(player) < room.arm_radius + room.player_radius:
		return true
	for hazard in hazards:
		if hazard_hits(hazard, player, room.player_radius):
			return true
	return false


# Would `hazard` touch a player of `radius` at `at`? (Also for bots and tests.)
func hazard_hits(hazard: Hazard, at: Vector2, radius: float) -> bool:
	var room := get_airlock()
	if hazard.kind == &"heart":
		return hazard.position.distance_to(at) < room.heart_radius + radius
	var half := room.bubble_size / 2.0
	var nearest := Vector2(clampf(at.x, hazard.position.x - half.x, hazard.position.x + half.x),
		clampf(at.y, hazard.position.y - half.y, hazard.position.y + half.y))
	return nearest.distance_to(at) < radius


func draw_view(canvas: CanvasItem, rect: Rect2) -> void:
	var room := get_airlock()
	var scale := minf(rect.size.x / room.room_size.x, rect.size.y / room.room_size.y)
	var origin := rect.position + (rect.size - room.room_size * scale) / 2.0
	var to_screen := func(p: Vector2) -> Vector2: return origin + p * scale
	canvas.draw_rect(Rect2(origin, room.room_size * scale), Color(0.12, 0.08, 0.2))
	# Door strip: glows as it opens.
	var door := Rect2(to_screen.call(Vector2(room.door_x, 0)), Vector2(room.room_size.x - room.door_x, room.room_size.y) * scale)
	canvas.draw_rect(door, Color(0.3, 1.0, 0.7, 0.2 + 0.6 * clampf(door_time / maxf(room.door_hold, 0.01), 0.0, 1.0)))
	for hazard in hazards:
		if hazard.kind == &"heart":
			canvas.draw_circle(to_screen.call(hazard.position), room.heart_radius * scale, Color(1.0, 0.45, 0.75))
		else:
			var half := room.bubble_size / 2.0
			canvas.draw_rect(Rect2(to_screen.call(hazard.position - half), room.bubble_size * scale), Color(1, 1, 1, 0.9))
	if arm_out:
		canvas.draw_line(to_screen.call(Vector2(0, room.room_size.y / 2.0)), to_screen.call(arm_hand), Color(0.75, 0.65, 1.0), 10.0 * scale, true)
		canvas.draw_circle(to_screen.call(arm_hand), room.arm_radius * scale, Color(0.8, 0.7, 1.0))
	canvas.draw_circle(to_screen.call(player), room.player_radius * scale, Color(1, 0.95, 0.4))
	var time_left := maxf(data.max_duration - elapsed, 0.0)
	canvas.draw_rect(Rect2(origin + Vector2(0, -10), Vector2(room.room_size.x * scale * time_left / data.max_duration, 6)), Color(1, 0.5, 0.8))
