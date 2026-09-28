extends StaticBody2D
class_name MoteGeyser

# A Mote geyser: a small mound (low cover) that anyone can hit. Every hit
# (a damage event, whatever its size) fills it; data.hits_to_pop hits pop
# data.mote_count Motes around it for anyone to grab, then it goes dormant
# for data.cooldown. Hits fade if nobody hits it for data.hit_decay_time.
#
# It builds its own HealthComponent (topped up after every hit: it never
# dies) and HurtboxComponent. No team: both teams hit it. Numbers in
# MapPieceData; cues through the match profiles (hit_cue, break_cue = the
# pop, restore_cue = ready again).

enum State { READY, DORMANT }

const GROUP := &"mote_geysers"
const SMALL_MOTE := "res://resources/match/small_mote.tres"

signal popped(motes: Array[Mote])
signal ready_again

@export var data: MapPieceData
@export var color := Color(0.93, 0.68, 0.3)

var state: State = State.READY
var hits: int = 0
var health: HealthComponent
var hurtbox: HurtboxComponent
var _idle := 0.0
var _left := 0.0
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(MatchManager.CLOCK_LISTENERS)
	collision_layer = MapLayers.LOW_COVER
	collision_mask = 0
	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.body_radius
	body_shape.shape = circle
	add_child(body_shape)
	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = data.max_health
	add_child(health)
	health.damaged.connect(_on_damaged)
	hurtbox = HurtboxComponent.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health_component = health
	hurtbox.collision_layer = MapLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	var hurt_shape := CollisionShape2D.new()
	var hurt_circle := CircleShape2D.new()
	hurt_circle.radius = data.body_radius + 10.0
	hurt_shape.shape = hurt_circle
	hurtbox.add_child(hurt_shape)
	add_child(hurtbox)


func is_ready() -> bool:
	return state == State.READY


func get_fill() -> float:
	return float(hits) / maxf(1.0, data.hits_to_pop)


func _on_damaged(_amount: float, _source: Node) -> void:
	health.reset()
	if state != State.READY:
		return
	hits += 1
	_idle = 0.0
	_flash = 0.12
	if data.hit_cue != &"":
		MatchManager.play_world_cue(self, data.hit_cue)
	if hits >= data.hits_to_pop:
		pop()
	queue_redraw()


## Pop now: Motes fly out for anyone, then dormant for data.cooldown.
func pop() -> Array[Mote]:
	var motes: Array[Mote] = []
	if state != State.READY:
		return motes
	state = State.DORMANT
	hits = 0
	_left = data.cooldown
	hurtbox.set_deferred(&"monitorable", false)
	var mote_data: MoteData = data.mote_data if data.mote_data != null else load(SMALL_MOTE)
	var director := MoteDirector.find(get_tree())
	var mult := director.get_value_multiplier() if director != null else 1.0
	var value := roundi(data.mote_value * mult)
	var start := randf() * TAU
	for i in data.mote_count:
		var dir := Vector2.from_angle(start + TAU * i / maxf(1.0, data.mote_count))
		motes.append(Mote.spawn(self, mote_data, global_position + dir * data.mote_burst_radius,
				value, true, global_position))
	if data.break_cue != &"":
		MatchManager.play_world_cue(self, data.break_cue)
	popped.emit(motes)
	queue_redraw()
	return motes


func make_ready() -> void:
	state = State.READY
	hits = 0
	_left = 0.0
	hurtbox.set_deferred(&"monitorable", true)
	if data.restore_cue != &"":
		MatchManager.play_world_cue(self, data.restore_cue)
	ready_again.emit()
	queue_redraw()


## Debug clock jump: start the new time ready and empty.
func on_clock_jumped(_from: float, _to: float) -> void:
	if state != State.READY:
		make_ready()
	hits = 0


func get_time_left() -> float:
	return _left


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if state == State.DORMANT:
		_left -= delta
		if _left <= 0.0:
			make_ready()
	elif hits > 0:
		_idle += delta
		if _idle >= data.hit_decay_time:
			hits = 0
	if ScreenCull.is_near(self, data.body_radius * 3.0):
		queue_redraw()


func _draw() -> void:
	var r := data.body_radius
	draw_circle(Vector2(6, 9), r, CoverBody.SHADOW)
	var mound := color.darkened(0.35) if state == State.DORMANT else color
	if _flash > 0.0:
		mound = mound.lerp(Color.WHITE, 0.6)
	draw_circle(Vector2.ZERO, r, mound)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, mound.darkened(0.45), 3.0, true)
	# The vent: brighter and bubbling the fuller it is.
	var fill := get_fill() if state == State.READY else 0.0
	var vent := Color(1, 0.95, 0.6).lerp(Color(1, 1, 1), fill)
	vent.a = 0.35 + 0.65 * fill if state == State.READY else 0.15
	draw_circle(Vector2.ZERO, r * 0.45, vent)
	if state == State.READY:
		for i in 3:
			var phase := fmod(_t * (0.8 + fill * 2.0) + i / 3.0, 1.0)
			draw_circle(Vector2(sin(i * 2.1) * r * 0.2, -phase * r * 0.9), 3.0 + fill * 3.0,
					Color(1, 1, 0.85, (1.0 - phase) * (0.3 + fill * 0.7)))
		if hits > 0:
			draw_arc(Vector2.ZERO, r + 8.0, -PI / 2, -PI / 2 + TAU * fill, 32, Color(1, 0.95, 0.6, 0.9), 4.0, true)
