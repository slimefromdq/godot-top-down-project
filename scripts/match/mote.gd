extends Node2D
class_name Mote

# A loose Mote on the ground: the match's collectible. Spawn one with
# Mote.spawn(); the MoteDirector does, and so does a MoteCarrier dropping
# what it holds.
#
#   idle      bobs, looks toward the nearest hero, waits
#   landing   flying from where it was dropped to where it lands (no pickup)
#   magnet    a hero came within data.magnet_radius: it's pulled to them over
#             data.magnet_time, then attaches (MoteCarrier.add_mote) and frees
#
# Only heroes whose MoteCarrier has room (and isn't abducted) pull it in.
# A claimed Mote (claim(): a slain neutral's reward) only answers heroes of
# the claiming team until the claim runs out.
# A dropped Mote fades after data.fade_time, blinking for the last
# data.blink_time. Its last carrier can't grab it back for data.regrab_lockout.
# A decoy looks and pulls the same, but pops on pickup and adds nothing.
#
# Signals: picked_up(hero), faded. Cues (through the match's cue profiles):
# mote_spawn / dream_mote_spawn, mote_pickup, mote_fade, mote_decoy_pop.

signal picked_up(hero: Hero)
signal faded

const GROUP := &"motes"
const SCENE := "res://scenes/match/mote.tscn"
const LOOK_RANGE := 500.0
const LAND_TIME := 0.35
## Cosmetic: how long the spawn / landing pop wobbles.
const POP_TIME := 0.45

enum State { IDLE, LANDING, MAGNET }

@export var data: MoteData
## Worth this much (data.value times any late-match multiplier at spawn).
var value: int = 1
var is_decoy: bool = false
## Dropped by a carrier: fades after data.fade_time. Spawned Motes don't.
var dropped: bool = false
## Who dropped it, and how long before they may grab it again.
var last_carrier: Hero
var lockout_left: float = 0.0
## claim(): only this team's heroes can take it while claim_left > 0.
var claim_team: StringName = &""
var claim_left: float = 0.0
## Set by the director: the spawn point or dreaming-zone half it came from.
var origin: Node
## On the minimap only where your team can see it (the Dream Mote is always
## shown instead).
var minimap_fogged: bool = true
var minimap_icon_scale: float = 0.6
## For the HUD's off-screen arrow (Dream Mote).
var arrow_color := Color("fde68a")

var state: State = State.IDLE
var age: float = 0.0
var _target: Hero
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _move_t: float = 0.0
var _look := Vector2.ZERO
var _look_node: Node


## Put a Mote into the current scene at `at`. With `land_from`, it flies
## from there to `at` first (a drop). `locked` can't pick it up for a moment.
static func spawn(context: Node, mote_data: MoteData, at: Vector2, mote_value: int = -1,
		is_dropped: bool = false, land_from: Variant = null, locked: Hero = null) -> Mote:
	var mote: Mote = load(SCENE).instantiate()
	mote.data = mote_data
	mote.value = mote_value if mote_value >= 0 else mote_data.value
	mote.dropped = is_dropped
	mote.last_carrier = locked
	mote.lockout_left = mote_data.regrab_lockout if locked != null else 0.0
	if land_from is Vector2:
		mote.state = State.LANDING
		mote._from = land_from
		mote._to = at
		mote.position = land_from
	else:
		mote.position = at
	context.get_tree().current_scene.add_child(mote)
	return mote


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"minimap_objectives")
	if data == null:
		data = load("res://resources/match/small_mote.tres")
	if data.is_dream:
		minimap_fogged = false
		minimap_icon_scale = 1.3
		add_to_group(&"offscreen_arrows")
	if data.look_scene != null:
		_look_node = data.look_scene.instantiate()
		add_child(_look_node)
		if _look_node.has_method(&"setup_mote"):
			_look_node.setup_mote(self)
	if not dropped:
		MatchManager.play_world_cue(self, &"dream_mote_spawn" if data.is_dream else &"mote_spawn",
			{"position": global_position})
	var director := MoteDirector.find(get_tree())
	if director != null:
		director.on_mote_appeared(self)


## The minimap's icon: a star for the Dream Mote, a small dot otherwise.
func draw_minimap_icon(canvas: Object, at: Vector2, _viewer_team: StringName) -> void:
	if is_dream():
		var spin := Time.get_ticks_msec() / 600.0
		var points := PackedVector2Array()
		for i in 10:
			points.append(at + Vector2.from_angle(spin + TAU * i / 10.0) * (9.0 if i % 2 == 0 else 4.0))
		canvas.draw_colored_polygon(points, Color.BLACK)
		var inner := PackedVector2Array()
		for p in points:
			inner.append(at + (p - at) * 0.78)
		canvas.draw_colored_polygon(inner, Color.from_hsv(fmod(spin * 0.1, 1.0), 0.3, 1.0))
	else:
		canvas.draw_circle(at, 2.8, Color.BLACK)
		canvas.draw_circle(at, 2.0, Color("fde047"))


## Only `team` can pick it up for `seconds` (a neutral objective's reward).
func claim(team: StringName, seconds: float) -> void:
	claim_team = team
	claim_left = seconds


func is_claimed_against(hero: Hero) -> bool:
	return claim_left > 0.0 and claim_team != &"" and hero.team != claim_team


func is_dream() -> bool:
	return data != null and data.is_dream


func is_landing() -> bool:
	return state == State.LANDING


func _physics_process(delta: float) -> void:
	age += delta
	lockout_left = maxf(lockout_left - delta, 0.0)
	claim_left = maxf(claim_left - delta, 0.0)
	match state:
		State.LANDING:
			_move_t += delta / LAND_TIME
			var t := minf(_move_t, 1.0)
			global_position = _from.lerp(_to, t) + Vector2(0, -90.0 * 4.0 * t * (1.0 - t))
			if t >= 1.0:
				global_position = _to
				state = State.IDLE
				age = 0.0
		State.IDLE:
			if dropped and age >= data.fade_time:
				fade()
				return
			var hero := _nearest_taker()
			if hero != null:
				_target = hero
				_from = global_position
				_move_t = 0.0
				state = State.MAGNET
		State.MAGNET:
			if not _can_take(_target, true):
				_target = null
				state = State.IDLE
				return
			_move_t += delta / maxf(data.magnet_time, 0.01)
			var t := minf(_move_t, 1.0)
			global_position = _from.lerp(_target.global_position, t * t)
			if t >= 1.0:
				_attach(_target)


func _process(_delta: float) -> void:
	var nearest: Node2D = null
	var best := LOOK_RANGE
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		var d := hero.global_position.distance_to(global_position)
		if d < best and not hero.health_component.is_dead():
			best = d
			nearest = hero
	var want := (nearest.global_position - global_position) / LOOK_RANGE if nearest != null else Vector2.ZERO
	_look = _look.lerp(want.limit_length(1.0), 0.1)


# Cosmetic, for the look scene.
func get_look_direction() -> Vector2:
	return _look


# Cosmetic, for the look scene: a squash-and-stretch. Spawning (or landing)
# grows it in with a wobbly pop; a magnet pull stretches it toward the hero.
func get_look_squash() -> Vector2:
	match state:
		State.MAGNET:
			var k := minf(_move_t, 1.0)
			return Vector2(1.0 - 0.25 * k, 1.0 + 0.3 * k)
		State.LANDING:
			return Vector2(0.9, 1.12)
	if age < POP_TIME:
		var grow := minf(age / 0.12, 1.0)
		var wobble := 0.35 * sin(age * 22.0) * exp(-age * 9.0)
		return Vector2(grow * (1.0 + wobble), grow * (1.0 - wobble))
	return Vector2.ONE


func get_look_alpha() -> float:
	if not dropped or state != State.IDLE:
		return 1.0
	var left := data.fade_time - age
	if left > data.blink_time:
		return 1.0
	# Faster and faster as it runs out.
	var speed := lerpf(3.0, 12.0, 1.0 - left / maxf(data.blink_time, 0.01))
	return 0.35 + 0.65 * (0.5 + 0.5 * cos(age * speed * TAU))


func fade() -> void:
	MatchManager.play_world_cue(self, &"mote_fade", {"position": global_position})
	faded.emit()
	queue_free()


func _nearest_taker() -> Hero:
	var best: Hero = null
	var best_distance := data.magnet_radius
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var hero := node as Hero
		var d := hero.global_position.distance_to(global_position)
		if d <= best_distance and _can_take(hero, false):
			best = hero
			best_distance = d
	return best


func _can_take(hero: Hero, pulling: bool) -> bool:
	if hero == null or not is_instance_valid(hero) or not hero.is_inside_tree():
		return false
	if hero == last_carrier and lockout_left > 0.0 and not pulling:
		return false
	if is_claimed_against(hero):
		return false
	var carrier := MoteCarrier.find_on(hero)
	return carrier != null and carrier.can_pick_up()


func _attach(hero: Hero) -> void:
	var carrier := MoteCarrier.find_on(hero)
	if is_decoy:
		MatchManager.play_world_cue(self, &"mote_decoy_pop", {"position": global_position, "source": hero})
	elif not carrier.add_mote(data, value):
		# Another Mote filled the last slot first.
		_target = null
		state = State.IDLE
		return
	picked_up.emit(hero)
	queue_free()
