extends Area2D
class_name HazardZone

# A patch of the map that hurts or hinders whoever stands in it (sleep-fog
# that slows, a thorn bed that nicks, a slick fountain spill). Its shape is
# the CollisionPolygon2D child. Everything it does is in MapPieceData:
#
#   ticks      every data.hazard_tick while active: data.hazard_status on
#              everyone inside, data.hazard_damage true damage.
#   cycle      with hazard_dormant_time > 0 it runs on MapClock: active for
#              hazard_active_time, off for hazard_dormant_time, and drawn as
#              a warning for data.hazard_telegraph before it turns on. It's
#              always drawn, so nobody walks into it blind.
#   credit     a hero pushed, pulled or carried in by an enemy (Actor
#              .displaced) within data.displacement_credit_time: while they
#              stay inside, its ticks count as that enemy's.
#
# It affects heroes of both teams and neutral monsters alike (it has no team).
# Cues: data.open_cue when it turns on (match profiles).

const GROUP := &"hazard_zones"

@export var data: MapPieceData
@export var color := Color(0.7, 0.6, 1.0, 0.32)
@export var cycle_offset: float = 0.0

var active := true
var _polygon := PackedVector2Array()
var _inside: Array[Node2D] = []
# Actor instance id -> the enemy that pushed them in (valid while inside).
var _credit: Dictionary = {}
var _tick_left := 0.0
var _until_change := INF
var _t := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = MapLayers.CHARACTERS
	monitorable = false
	z_index = -7
	for child in get_children():
		if child is CollisionPolygon2D:
			_polygon = child.transform * child.polygon
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)
	_refresh_cycle(true)


func is_active() -> bool:
	return active


func get_occupants() -> Array[Node2D]:
	return _inside.filter(func(n): return is_instance_valid(n))


## Who gets credit for `body`'s ticks (null = the hazard itself).
func get_credit(body: Node) -> Node:
	var who: Node = _credit.get(body.get_instance_id())
	return who if is_instance_valid(who) else null


func _on_entered(body: Node2D) -> void:
	if not _inside.has(body):
		_inside.append(body)
	if body is Actor:
		var by: Node = body.get_last_displacer(data.displacement_credit_time)
		if by != null and CombatQueries.team_of(by) != CombatQueries.team_of(body):
			_credit[body.get_instance_id()] = by


func _on_exited(body: Node2D) -> void:
	_inside.erase(body)
	_credit.erase(body.get_instance_id())


func _refresh_cycle(first: bool = false) -> void:
	var p := MapClock.phase(MapClock.now(self), data.hazard_active_time, data.hazard_dormant_time, cycle_offset)
	_until_change = p[1]
	var on: bool = p[0]
	if on and not active and not first and data.open_cue != &"":
		MatchManager.play_world_cue(self, data.open_cue, {"position": to_global(_center())})
	if on and not active:
		_tick_left = 0.0
	active = on


func _physics_process(delta: float) -> void:
	_t += delta
	_refresh_cycle()
	if active:
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = data.hazard_tick
			tick()
	if ScreenCull.is_near(self, 600.0):
		queue_redraw()


## One tick on everyone inside (called on the tick timer; public for tests).
func tick() -> void:
	for body in get_occupants():
		if not body is Actor or body.health_component.is_dead():
			continue
		var source: Node = get_credit(body)
		if source == null:
			source = self
		if data.hazard_status != null and body.status_component != null:
			body.status_component.apply(data.hazard_status, source)
		if data.hazard_damage > 0.0:
			var info := DamageInfo.create(data.hazard_damage, source)
			info.type = DamageInfo.Type.TRUE
			info.label = &"hazard"
			body.hurtbox.take_hit(info)


func _center() -> Vector2:
	var c := Vector2.ZERO
	for p in _polygon:
		c += p
	return c / maxf(1.0, _polygon.size())


func _draw() -> void:
	if _polygon.size() < 3:
		return
	var outline := _polygon.duplicate()
	outline.append(_polygon[0])
	var telegraph := not active and _until_change <= data.hazard_telegraph
	if active:
		var pulse := 0.85 + 0.15 * sin(_t * 3.0)
		draw_colored_polygon(_polygon, Color(color, color.a * pulse))
		draw_polyline(outline, Color(color.darkened(0.3), 0.8), 4.0, true)
	elif telegraph:
		var blink := 0.5 + 0.5 * sin(_t * 12.0)
		draw_colored_polygon(_polygon, Color(color, color.a * 0.4 * blink))
		for i in _polygon.size():
			draw_dashed_line(outline[i], outline[i + 1], Color(color.darkened(0.3), 0.9), 4.0, 14.0)
	else:
		for i in _polygon.size():
			draw_dashed_line(outline[i], outline[i + 1], Color(color.darkened(0.3), 0.35), 3.0, 14.0)
