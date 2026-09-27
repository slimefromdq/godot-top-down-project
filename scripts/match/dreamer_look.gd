extends Node2D
class_name DreamerLook

# The Dreamer's look (DreamerData.look_scene): a big sleeping creature built
# from soft glossy blobs in its team's pastel, with a head badge whose SHAPE
# says the team (Dawn: a little sun, Dusk: a crescent moon). Procedural until
# real art arrives; gameplay never reads any of it. It listens to its Dreamer:
#
#   asleep      a slow breath (one every ~3 s), Zzz bubbles floating up; now
#               and then it twitches, turns over or mumbles (dreamer_mumble)
#   waking      at 25 / 50 / 75% the breath quickens, the eyes flutter, the
#               Zzz thin out, and past 75% small tremors shake the ring
#   stirring    the eyes crack open and glow, the body rocks, the ground
#               ripples out once a second and a light pulses with the countdown
#   Lullaby     moon-and-star motes drift down onto it as it fills
#   settled     a big exhale, the eyes close, the Zzz come back
#   woke        the eyes slowly open wide and blaze (the win)
#   deposits    each Mote arcs from its carrier into the Dreamer's mouth: a
#               gulp and a glow when banked; a flinch and a burst of the
#               depositing team's colour when delivered
#
# The rings live on a child drawn under everyone; the body fades while a hero
# stands behind it, so it never hides a fight at its feet.

const SKIN := {&"a": Color("bff0da"), &"b": Color("ffd0c2")}
const INK := Color(0.22, 0.2, 0.3)
const LULLABY := Color("c4b5fd")
const FLIGHT_TIME := 0.35
const BEHIND_ALPHA := 0.4

var dreamer: Dreamer
var _t := 0.0
var _rings: Node2D
# Reactions (seconds left or 0..1 amounts; all cosmetic).
var _gulp := 0.0
var _flinch := 0.0
var _exhale := 0.0
var _twitch := 0.0
var _mumble := 0.0
var _turn := 0.0
var _turn_target := 0.0
var _next_idle := 4.0
var _eye_open := 0.0          # 0 closed .. 1 wide
var _flutter := 0.0
var _awake := false
var _flights: Array = []      # {from: Vector2 (global), t: float, color: Color, delivered: bool}
var _bursts: Array = []       # {t: float, color: Color}
var _ripples: Array = []      # ages
var _last_second := -1
var _lullaby_motes: Array = [] # {x, y0, speed, star}


func setup_dreamer(owner_dreamer: Dreamer) -> void:
	dreamer = owner_dreamer
	z_index = 1
	_rings = Node2D.new()
	_rings.name = "Rings"
	_rings.z_as_relative = false
	_rings.z_index = -5
	_rings.draw.connect(_draw_rings)
	add_child(_rings)
	dreamer.deposit_ticked.connect(_on_deposit)
	dreamer.settled.connect(func(_how): _exhale = 1.2)
	dreamer.stir_started.connect(func(): _ripples.append(0.0))
	dreamer.woke.connect(func(_team): _awake = true)
	for i in 18:
		_lullaby_motes.append({"x": randf_range(-1.0, 1.0), "phase": randf(), "speed": randf_range(0.25, 0.45),
			"star": i % 3 != 0})


func _process(delta: float) -> void:
	_t += delta
	_gulp = maxf(_gulp - delta * 3.0, 0.0)
	_flinch = maxf(_flinch - delta * 3.0, 0.0)
	_exhale = maxf(_exhale - delta, 0.0)
	_twitch = maxf(_twitch - delta * 4.0, 0.0)
	_mumble = maxf(_mumble - delta, 0.0)
	_flutter = maxf(_flutter - delta * 5.0, 0.0)
	_turn = lerpf(_turn, _turn_target, minf(delta * 1.5, 1.0))
	if dreamer != null:
		_update_state(delta)
	for flight in _flights:
		flight.t += delta / FLIGHT_TIME
		if flight.t >= 1.0:
			_on_arrival(flight)
	_flights = _flights.filter(func(f): return f.t < 1.0)
	for burst in _bursts:
		burst.t += delta
	_bursts = _bursts.filter(func(b): return b.t < 0.6)
	for i in _ripples.size():
		_ripples[i] += delta
	_ripples = _ripples.filter(func(a): return a < 1.4)
	_update_behind_fade(delta)
	if ScreenCull.is_near(self, 900.0):
		queue_redraw()
		_rings.queue_redraw()


func _update_state(delta: float) -> void:
	var wake := dreamer.get_wake_ratio()
	var stirring := dreamer.is_stirring()
	var want_open := 1.0 if _awake else (0.6 if stirring else 0.0)
	# The win opens its eyes slowly; everything else snaps a little quicker.
	_eye_open = move_toward(_eye_open, want_open, delta * (0.8 if _awake else 2.5))
	if stirring:
		var second := ceili(dreamer.stir_left)
		if second != _last_second:
			_last_second = second
			_ripples.append(0.0)
		return
	_last_second = -1
	# Idle life while asleep: twitch, turn over, mumble.
	_next_idle -= delta
	if _next_idle <= 0.0:
		_next_idle = randf_range(4.0, 9.0)
		match randi() % 3:
			0:
				_twitch = 1.0
			1:
				_turn_target = randf_range(-0.25, 0.25)
			2:
				_mumble = 1.0
				MatchManager.play_world_cue(dreamer, &"dreamer_mumble", {"position": dreamer.global_position})
	# Past half awake, the eyes flutter now and then.
	if wake >= 0.5 and _flutter <= 0.0 and randf() < delta * (0.5 if wake < 0.75 else 1.2):
		_flutter = 1.0


func _update_behind_fade(delta: float) -> void:
	if dreamer == null:
		return
	var r := dreamer.data.body_radius
	var behind := false
	for node in get_tree().get_nodes_in_group(&"heroes"):
		var offset: Vector2 = (node as Node2D).global_position - global_position
		if absf(offset.x) < r * 1.1 and offset.y < r * 0.2 and offset.y > -r * 1.9:
			behind = true
			break
	var target := BEHIND_ALPHA if behind else 1.0
	# self_modulate: only the body fades, never the rings (a child).
	self_modulate.a = move_toward(self_modulate.a, target, delta * 3.0)


func _on_deposit(hero: Hero, _value: int, delivered: bool, _index: int) -> void:
	if not is_instance_valid(hero):
		return
	_flights.append({"from": hero.global_position, "t": 0.0, "delivered": delivered,
		"color": MatchManager.team_color(hero.team)})


func _on_arrival(flight: Dictionary) -> void:
	if flight.delivered:
		_flinch = 1.0
		_bursts.append({"t": 0.0, "color": flight.color})
	else:
		_gulp = 1.0


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	if dreamer == null:
		return
	var team_color := MatchManager.team_color(dreamer.team)
	var r := dreamer.data.body_radius
	var wake := dreamer.get_wake_ratio()
	var stirring := dreamer.is_stirring()

	# Breathing: one breath about every 3 s, faster as it wakes; a big dip
	# on the settle's exhale; the gulp squashes, the flinch shakes.
	var breath_speed := lerpf(1.0, 2.2, wake) * (1.6 if stirring else 1.0)
	var breath := sin(_t * TAU / 3.0 * breath_speed)
	var exhale := sin(clampf(_exhale / 1.2, 0.0, 1.0) * PI)
	var rock := (sin(_t * 7.0) * 0.07 if stirring else 0.0) + _turn + sin(_t * 40.0) * 0.05 * _twitch
	var shake := Vector2(sin(_t * 60.0), cos(_t * 53.0)) * 10.0 * _flinch
	var squash := Vector2(1.0 + 0.04 * breath + 0.12 * _gulp - 0.06 * exhale,
		1.0 - 0.03 * breath - 0.12 * _gulp - 0.1 * exhale)
	var skin: Color = SKIN.get(dreamer.team, Color.WHITE)

	# Soft ground shadow, then the body: layered glossy blobs.
	draw_set_transform(Vector2(0, r * 0.3), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r * 1.08, Color(0, 0, 0, 0.2))
	draw_set_transform(shake, rock, squash)
	for i in 5:    # little lobes around the edge: a soft, lumpy silhouette
		var a := TAU * i / 5.0 + 0.3
		draw_circle(Vector2.from_angle(a) * r * 0.62 + Vector2(0, r * 0.12), r * 0.46, skin.darkened(0.12))
	draw_circle(Vector2.ZERO, r, skin.darkened(0.15))
	draw_circle(Vector2(0, -r * 0.05), r * 0.94, skin)
	draw_circle(Vector2(0, -r * 0.32), r * 0.62, skin.lightened(0.25))
	var sweep := fmod(_t * 0.4, TAU)
	draw_arc(Vector2.ZERO, r * 0.8, sweep, sweep + 0.7, 16, Color(1, 1, 1, 0.3), r * 0.1)
	draw_circle(Vector2(-r * 0.42, -r * 0.46), r * 0.2, Color(1, 1, 1, 0.6))
	draw_circle(Vector2(-r * 0.25, -r * 0.62), r * 0.07, Color(1, 1, 1, 0.8))
	if _gulp > 0.0:
		draw_circle(Vector2.ZERO, r * 1.05, Color(team_color, 0.35 * _gulp))
	if stirring:
		# A soft light pulsing with the countdown (brightest on each second).
		var pulse := 1.0 - fmod(dreamer.stir_left, 1.0)
		draw_circle(Vector2.ZERO, r * 1.15, Color(1, 1, 0.8, 0.1 + 0.2 * pulse * pulse))

	# Eyes: curved lids when asleep; they flutter, crack open and glow.
	var open := clampf(_eye_open + 0.35 * _flutter, 0.0, 1.0)
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * r * 0.35, -r * 0.05)
		if open > 0.05:
			var glow := Color(1.0, 0.95, 0.55, 0.35 * open)
			draw_circle(eye, r * (0.2 + 0.1 * open), glow)
			draw_set_transform(shake + eye.rotated(rock) * squash, rock, Vector2(1.0, open))
			draw_circle(Vector2.ZERO, r * 0.14, Color(1.0, 0.97, 0.7))
			draw_circle(Vector2.ZERO, r * 0.065, INK)
			draw_circle(Vector2(-r * 0.03, -r * 0.03), r * 0.025, Color.WHITE)
			draw_set_transform(shake, rock, squash)
		else:
			draw_arc(eye, r * 0.14, PI * 0.1, PI * 0.9, 12, INK, 5.0)
		draw_circle(eye + Vector2(side * r * 0.12, r * 0.22), r * 0.08, Color(1.0, 0.55, 0.6, 0.45))
	# Mouth: a small breathing "o"; it wobbles as it mumbles, gapes to gulp.
	var mouth := r * (0.07 + 0.02 * breath + 0.05 * _gulp + 0.03 * sin(_t * 18.0) * _mumble + 0.04 * exhale)
	draw_circle(Vector2(0, r * 0.3), mouth, INK)

	# Team badge on the head: Dawn's sun, Dusk's crescent moon.
	var badge := Vector2(0, -r * 0.82)
	if dreamer.team == &"a":
		for i in 8:
			var a := TAU * i / 8.0 + _t * 0.2
			draw_line(badge + Vector2.from_angle(a) * r * 0.2, badge + Vector2.from_angle(a) * r * 0.32,
				team_color.darkened(0.3), 6.0)
		draw_circle(badge, r * 0.17, team_color.darkened(0.1))
	else:
		draw_circle(badge, r * 0.22, team_color.darkened(0.2))
		draw_circle(badge + Vector2(r * 0.1, -r * 0.06), r * 0.19, skin)
	draw_set_transform(Vector2.ZERO)

	_draw_zzz(r, wake, stirring)
	_draw_exhale_puffs(r)
	_draw_lullaby_motes(r)
	_draw_flights(r)
	if stirring:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-80, -r - 70), "%d" % ceili(dreamer.stir_left), HORIZONTAL_ALIGNMENT_CENTER,
			160, 64, 10, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(-80, -r - 70), "%d" % ceili(dreamer.stir_left), HORIZONTAL_ALIGNMENT_CENTER, 160, 64,
			Color(1, 1, 1, 0.95))


# Zzz bubbles float up while it sleeps, fewer as it wakes.
func _draw_zzz(r: float, wake: float, stirring: bool) -> void:
	if stirring or _awake:
		return
	var count := 3 if wake < 0.5 else (2 if wake < 0.75 else 1)
	var back := clampf(1.0 - _exhale / 1.2, 0.0, 1.0)    # they come back after a settle
	var font := ThemeDB.fallback_font
	for i in count:
		var k := fmod(_t * 0.3 + i / 3.0, 1.0)
		var at := Vector2(r * 0.7 + k * 70.0 + sin(_t * 1.3 + i) * 12.0, -r * 0.75 - k * 170.0)
		var size := 18.0 + 22.0 * k
		var a := (1.0 - k) * back
		draw_circle(at, size, Color(1, 1, 1, 0.35 * a))
		draw_arc(at, size, 0, TAU, 20, Color(1, 1, 1, 0.7 * a), 2.0)
		draw_arc(at, size * 0.7, -2.4, -1.6, 6, Color(1, 1, 1, 0.9 * a), 2.5)
		draw_string(font, at + Vector2(-size * 0.45, size * 0.45), "z", HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(size * 1.3), Color(INK, 0.85 * a))


func _draw_exhale_puffs(r: float) -> void:
	if _exhale <= 0.0:
		return
	var k := 1.0 - _exhale / 1.2
	for i in 5:
		var a := -PI / 2 + (i - 2) * 0.35
		draw_circle(Vector2(0, r * 0.3) + Vector2.from_angle(a) * (40.0 + 160.0 * k), 20.0 + 30.0 * k,
			Color(1, 1, 1, 0.45 * (1.0 - k)))


# Moon-and-star motes drifting down onto it while the Lullaby fills.
func _draw_lullaby_motes(r: float) -> void:
	if not dreamer.is_stirring() or dreamer.lullaby <= 0.0:
		return
	var n := int(3 + dreamer.lullaby * 15)
	for i in mini(n, _lullaby_motes.size()):
		var m: Dictionary = _lullaby_motes[i]
		var k := fmod(_t * m.speed + m.phase, 1.0)
		var at := Vector2(m.x * r * 1.3 + sin(_t + i) * 20.0, lerpf(-r * 3.2, -r * 0.2, k))
		var a := sin(k * PI)
		if m.star:
			var s := 9.0
			draw_line(at + Vector2(-s, 0), at + Vector2(s, 0), Color(1, 1, 0.8, a), 3.0)
			draw_line(at + Vector2(0, -s), at + Vector2(0, s), Color(1, 1, 0.8, a), 3.0)
			draw_circle(at, 3.5, Color(1, 1, 1, a))
		else:
			draw_circle(at, 11.0, Color(LULLABY, a))
			draw_circle(at + Vector2(5, -3), 9.5, Color(LULLABY.darkened(0.4), a * 0.9))


# Deposited Motes arcing from their carrier into the mouth.
func _draw_flights(r: float) -> void:
	var small: MoteData = load("res://resources/match/small_mote.tres")
	for flight in _flights:
		var from: Vector2 = flight.from - global_position
		var to := Vector2(0, r * 0.3)
		var k: float = flight.t
		var at := from.lerp(to, k * k) + Vector2(0, -160.0 * 4.0 * k * (1.0 - k))
		MoteLook.draw_mote(self, at, small.size * lerpf(1.0, 0.5, k), _t + k * 3.0, (to - at).normalized() * 0.8,
			1.0, false, 1.0, 0.0, Vector2(1.0 - 0.2 * k, 1.0 + 0.2 * k))


func _draw_rings() -> void:
	if dreamer == null:
		return
	var rules := dreamer.get_rules()
	var team_color := MatchManager.team_color(dreamer.team)
	var r := dreamer.data.body_radius
	var wake := dreamer.get_wake_ratio()
	var stirring := dreamer.is_stirring()
	# Past 75% the ring trembles.
	var tremor := Vector2(sin(_t * 31.0), cos(_t * 27.0)) * 5.0 if wake >= 0.75 and not stirring else Vector2.ZERO
	var ring_alpha := 0.9 if Dreamer.debug_rings else 0.45
	_dashed_circle(_rings, tremor, rules.deposit_radius, Color(team_color, ring_alpha), 6.0 if Dreamer.debug_rings else 4.0)
	if stirring or Dreamer.debug_rings:
		var lullaby_color := Color(1.0, 0.45, 0.45, 0.7) if stirring and dreamer.is_lullaby_contested() else LULLABY
		_dashed_circle(_rings, Vector2.ZERO, rules.lullaby_radius, Color(lullaby_color, 0.6), 5.0)
		if stirring:
			_rings.draw_arc(Vector2.ZERO, rules.lullaby_radius, -PI / 2, -PI / 2 + TAU * dreamer.lullaby, 64,
				Color(lullaby_color, 0.95), 14.0)
	# Ground ripples while stirring (one a second), team bursts on delivery.
	for age in _ripples:
		var k: float = age / 1.4
		_rings.draw_arc(Vector2.ZERO, r * 1.2 + k * rules.lullaby_radius * 0.9, 0, TAU, 64,
			Color(1, 1, 0.85, 0.5 * (1.0 - k)), 8.0 * (1.0 - k) + 2.0)
	for burst in _bursts:
		var k: float = burst.t / 0.6
		_rings.draw_circle(Vector2.ZERO, r * (1.1 + 1.2 * k), Color(burst.color, 0.35 * (1.0 - k)))
	# The wake meter as an arc hugging the body.
	_rings.draw_arc(tremor, r + 34, 0, TAU, 48, Color(0, 0, 0, 0.25), 10.0)
	if wake > 0.0:
		_rings.draw_arc(tremor, r + 34, -PI / 2, -PI / 2 + TAU * wake, 48, team_color, 10.0)


func _dashed_circle(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 48
	for i in segments:
		if i % 2 == 0:
			var a := TAU * i / segments + _t * 0.05
			canvas.draw_arc(center, radius, a, a + TAU / segments, 4, color, width)
